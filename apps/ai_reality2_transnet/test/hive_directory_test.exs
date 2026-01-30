defmodule AiReality2Transnet.HiveDirectoryTest do
  @moduledoc """
  Tests for HiveDirectory merge semantics, query logic, confidence decay,
  persistence round-tripping, and pruning.

  Because HiveDirectory.init/1 calls Reality2.Bootstrap, HiveIdentity, and
  Reality2.Sentants (unavailable in unit tests), these tests operate directly
  on the plain-map data structures that mirror the GenServer's internal state.
  Helper functions replicate the private logic so we can validate the
  algorithmic invariants without starting the full umbrella.

  Run with:  mix test --include integration
  """

  use ExUnit.Case, async: true

  @moduletag :integration

  alias AiReality2Transnet.TestNodeFactory

  # ---------------------------------------------------------------------------
  # Constants (must mirror the module under test)
  # ---------------------------------------------------------------------------
  @confidence_minimum 5
  @confidence_decay_rate 0.95
  @prune_absent_days 7

  # ===========================================================================
  # Helpers — pure-function replicas of HiveDirectory private logic
  # ===========================================================================

  # -- Timestamp comparison ---------------------------------------------------

  defp compare_timestamps(nil, _), do: :lt
  defp compare_timestamps(_, nil), do: :gt
  defp compare_timestamps(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end

  # -- Merge ------------------------------------------------------------------

  defp merge_directories(local, remote) do
    remote_nodes = Map.get(remote, :nodes, %{}) |> ensure_string_keys()
    local_nodes = local.nodes

    merged_nodes = Map.merge(local_nodes, remote_nodes, fn node_id, local_entry, remote_entry ->
      merge_node_entries(node_id, local_entry, remote_entry, local.my_node_id)
    end)

    new_nodes = Map.merge(remote_nodes, merged_nodes)

    remote_trusted = Map.get(remote, :trusted_hives, %{}) |> ensure_string_keys()
    merged_trusted = Map.merge(local.trusted_hives, remote_trusted, fn _hive_id, local_trust, remote_trust ->
      if compare_timestamps(local_trust[:established_at], remote_trust[:established_at]) == :gt do
        local_trust
      else
        remote_trust
      end
    end)

    %{local |
      nodes: new_nodes,
      trusted_hives: merged_trusted,
      directory_version: local.directory_version + 1
    }
  end

  defp merge_node_entries(node_id, local_entry, remote_entry, my_node_id) do
    local_ts = Map.get(local_entry, :updated_at)
    remote_ts = Map.get(remote_entry, :updated_at)

    merged_status = cond do
      Map.get(remote_entry, :status) == :revoked -> :revoked
      Map.get(local_entry, :status) == :revoked -> :revoked
      true ->
        if compare_timestamps(local_ts, remote_ts) == :gt do
          Map.get(local_entry, :status, :active)
        else
          Map.get(remote_entry, :status, :active)
        end
    end

    merged_sentants = if node_id == my_node_id do
      Map.get(local_entry, :sentants, [])
    else
      if compare_timestamps(local_ts, remote_ts) == :gt do
        Map.get(local_entry, :sentants, [])
      else
        Map.get(remote_entry, :sentants, [])
      end
    end

    local_reach = Map.get(local_entry, :reachability, TestNodeFactory.default_reachability())
    remote_reach = Map.get(remote_entry, :reachability, TestNodeFactory.default_reachability())
    merged_reach = merge_reachability(local_reach, remote_reach)

    if compare_timestamps(local_ts, remote_ts) == :gt do
      %{local_entry | status: merged_status, sentants: merged_sentants, reachability: merged_reach}
    else
      %{remote_entry | status: merged_status, sentants: merged_sentants, reachability: merged_reach}
    end
  end

  defp merge_reachability(local_reach, remote_reach) do
    Enum.reduce([:ble, :wifi, :lora, :internet], local_reach, fn transport, acc ->
      local_t = Map.get(acc, transport, %{})
      remote_t = Map.get(remote_reach, transport, %{})
      local_conf = Map.get(local_t, :confidence, 0)
      remote_conf = Map.get(remote_t, :confidence, 0)
      remote_hint_conf = div(remote_conf, 2)

      if local_conf >= remote_hint_conf do
        Map.put(acc, transport, local_t)
      else
        Map.put(acc, transport, %{remote_t | confidence: remote_hint_conf})
      end
    end)
  end

  # -- Queries ----------------------------------------------------------------

  defp do_find_sentant_by_name(directory, sentant_name) do
    directory.nodes
    |> Enum.filter(fn {_node_id, entry} ->
      entry.status == :active and
      Enum.any?(Map.get(entry, :sentants, []), fn s ->
        Map.get(s, :name) == sentant_name or Map.get(s, "name") == sentant_name
      end)
    end)
    |> Enum.map(fn {node_id, entry} ->
      {node_id, entry, best_confidence(entry)}
    end)
    |> Enum.sort_by(fn {_, _, conf} -> conf end, :desc)
  end

  defp do_best_transport_for(directory, node_id) do
    case Map.get(directory.nodes, node_id) do
      nil -> {:error, :unreachable}
      entry ->
        reach = Map.get(entry, :reachability, TestNodeFactory.default_reachability())

        transports = [
          {:wifi, Map.get(reach, :wifi, %{})},
          {:internet, Map.get(reach, :internet, %{})},
          {:ble, Map.get(reach, :ble, %{})},
          {:lora, Map.get(reach, :lora, %{})}
        ]
        |> Enum.map(fn {t, info} -> {t, info, Map.get(info, :confidence, 0)} end)
        |> Enum.filter(fn {_, _, conf} -> conf >= @confidence_minimum end)
        |> Enum.sort_by(fn {_, _, conf} -> conf end, :desc)

        case transports do
          [] -> {:error, :unreachable}
          [{transport, info, _conf} | _] -> {:ok, transport, info}
        end
    end
  end

  defp best_confidence(entry) do
    reach = Map.get(entry, :reachability, TestNodeFactory.default_reachability())
    Enum.max([
      get_in_safe(reach, [:wifi, :confidence], 0),
      get_in_safe(reach, [:internet, :confidence], 0),
      get_in_safe(reach, [:ble, :confidence], 0),
      get_in_safe(reach, [:lora, :confidence], 0)
    ])
  end

  # -- Confidence Decay -------------------------------------------------------

  defp decay_all_confidence(directory) do
    new_nodes = Map.new(directory.nodes, fn {node_id, entry} ->
      reach = Map.get(entry, :reachability, TestNodeFactory.default_reachability())
      new_reach = Map.new(reach, fn {transport, info} ->
        conf = Map.get(info, :confidence, 0)
        new_conf = trunc(conf * @confidence_decay_rate)
        {transport, %{info | confidence: new_conf}}
      end)
      {node_id, %{entry | reachability: new_reach}}
    end)
    %{directory | nodes: new_nodes}
  end

  # -- Pruning ----------------------------------------------------------------

  defp prune_absent_nodes(directory) do
    cutoff = DateTime.utc_now()
    |> DateTime.add(-@prune_absent_days * 24 * 60 * 60, :second)
    |> DateTime.to_iso8601()

    new_nodes = Enum.reject(directory.nodes, fn {node_id, entry} ->
      node_id != directory.my_node_id and
      entry.status == :absent and
      best_confidence(entry) == 0 and
      compare_timestamps(Map.get(entry, :updated_at, ""), cutoff) == :lt
    end)
    |> Map.new()

    %{directory | nodes: new_nodes}
  end

  # -- Persistence (export / import roundtrip) --------------------------------

  defp export_directory(directory) do
    nodes = Map.new(directory.nodes, fn {node_id, entry} ->
      exported_entry = entry
      |> Map.update(:compressed_id, nil, fn
        cid when is_binary(cid) and byte_size(cid) == 4 -> compressed_id_to_hex(cid)
        other -> other
      end)
      |> Map.update(:status, :active, &to_string/1)

      {node_id, exported_entry}
    end)

    %{
      hive_id: directory.hive_id,
      hive_name: directory.hive_name,
      my_node_id: directory.my_node_id,
      directory_version: directory.directory_version,
      nodes: nodes,
      trusted_hives: directory.trusted_hives,
      persisted_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp import_directory(data) do
    nodes = Map.get(data, :nodes, %{})
    |> ensure_string_keys()
    |> Map.new(fn {node_id, entry} ->
      imported_entry = entry
      |> Map.put(:compressed_id, import_compressed_id(Map.get(entry, :compressed_id), node_id))
      |> Map.put(:status, import_status(Map.get(entry, :status, "active")))
      |> Map.put_new(:sentants, [])
      |> Map.put_new(:hive_id, nil)

      {node_id, imported_entry}
    end)

    %{
      hive_id: Map.get(data, :hive_id),
      hive_name: Map.get(data, :hive_name, "DefaultHive"),
      my_node_id: Map.get(data, :my_node_id),
      directory_version: Map.get(data, :directory_version, 1),
      nodes: nodes,
      trusted_hives: Map.get(data, :trusted_hives, %{}) |> ensure_string_keys(),
      foreign_nodes: Map.get(data, :foreign_nodes, %{}) |> ensure_string_keys()
    }
  end

  defp compressed_id_to_hex(<<value::32>>) do
    "0x" <> String.upcase(Integer.to_string(value, 16) |> String.pad_leading(8, "0"))
  end
  defp compressed_id_to_hex(other), do: other

  defp import_compressed_id(nil, node_id), do: :crypto.hash(:sha256, node_id) |> binary_part(0, 4)
  defp import_compressed_id("0x" <> hex, node_id) do
    case Integer.parse(hex, 16) do
      {value, ""} -> <<value::32>>
      _ -> :crypto.hash(:sha256, node_id) |> binary_part(0, 4)
    end
  end
  defp import_compressed_id(cid, _node_id) when is_binary(cid) and byte_size(cid) == 4, do: cid
  defp import_compressed_id(_, node_id), do: :crypto.hash(:sha256, node_id) |> binary_part(0, 4)

  defp import_status("active"), do: :active
  defp import_status("absent"), do: :absent
  defp import_status("revoked"), do: :revoked
  defp import_status(atom) when is_atom(atom), do: atom
  defp import_status(_), do: :active

  defp ensure_string_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
  defp ensure_string_keys(other), do: other

  defp get_in_safe(map, keys, default) do
    Enum.reduce_while(keys, map, fn key, acc ->
      case acc do
        %{} -> {:cont, Map.get(acc, key)}
        _ -> {:halt, default}
      end
    end) || default
  end

  # -- Convenience helpers ----------------------------------------------------

  defp ts_offset(seconds) do
    DateTime.utc_now()
    |> DateTime.add(seconds, :second)
    |> DateTime.to_iso8601()
  end

  defp build_reach(overrides) do
    Map.merge(TestNodeFactory.default_reachability(), overrides)
  end

  # ===========================================================================
  # Tests
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # 1. Merge Semantics
  # ---------------------------------------------------------------------------

  describe "merge semantics — LWW timestamp" do
    test "newer remote timestamp wins over older local" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      old_ts = ts_offset(-120)
      new_ts = ts_offset(-10)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{node_id: peer_id, name: "OldName", updated_at: old_ts}))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{node_id: peer_id, name: "NewName", updated_at: new_ts})
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].name == "NewName"
    end

    test "older remote timestamp loses to newer local" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      old_ts = ts_offset(-120)
      new_ts = ts_offset(-10)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{node_id: peer_id, name: "LocalNew", updated_at: new_ts}))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{node_id: peer_id, name: "RemoteOld", updated_at: old_ts})
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].name == "LocalNew"
    end
  end

  describe "merge semantics — tombstone" do
    test "revoked status always wins regardless of timestamp" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      old_ts = ts_offset(-300)
      new_ts = ts_offset(-5)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      # Local has revoked with an OLD timestamp
      local = put_in(local, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{node_id: peer_id, status: :revoked, updated_at: old_ts}))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{node_id: peer_id, status: :active, updated_at: new_ts})
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].status == :revoked
    end

    test "remote revoked wins even when local is active and newer" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      old_ts = ts_offset(-300)
      new_ts = ts_offset(-5)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{node_id: peer_id, status: :active, updated_at: new_ts}))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{node_id: peer_id, status: :revoked, updated_at: old_ts})
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].status == :revoked
    end
  end

  describe "merge semantics — owning node authority" do
    test "local always wins for own node_id sentants" do
      my_id = TestNodeFactory.generate_uuid()

      local_sentants = [TestNodeFactory.build_sentant(%{name: "LocalSentant"})]
      remote_sentants = [TestNodeFactory.build_sentant(%{name: "RemoteSentant"})]

      old_ts = ts_offset(-300)
      new_ts = ts_offset(-5)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      # Local has OLD timestamp but it's our own node
      local = put_in(local, [:nodes, my_id],
        TestNodeFactory.build_node_entry(%{
          node_id: my_id,
          sentants: local_sentants,
          updated_at: old_ts
        }))

      remote = %{
        nodes: %{
          my_id => TestNodeFactory.build_node_entry(%{
            node_id: my_id,
            sentants: remote_sentants,
            updated_at: new_ts
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      sentant_names = Enum.map(merged.nodes[my_id].sentants, & &1.name)
      assert "LocalSentant" in sentant_names
      refute "RemoteSentant" in sentant_names
    end
  end

  describe "merge semantics — reachability" do
    test "remote reachability is halved as hint confidence" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      ts = ts_offset(-10)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          updated_at: ts,
          reachability: build_reach(%{wifi: %{last_seen: ts, confidence: 50, ip: "10.0.0.1"}})
        }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id,
            updated_at: ts,
            reachability: build_reach(%{wifi: %{last_seen: ts, confidence: 200, ip: "10.0.0.2"}})
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      wifi_conf = merged.nodes[peer_id].reachability.wifi.confidence

      # Remote 200 halved = 100, which is > local 50, so remote hint (100) should win
      assert wifi_conf == 100
    end

    test "local reachability kept when >= halved remote" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      ts = ts_offset(-10)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          updated_at: ts,
          reachability: build_reach(%{wifi: %{last_seen: ts, confidence: 120, ip: "10.0.0.1"}})
        }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id,
            updated_at: ts,
            reachability: build_reach(%{wifi: %{last_seen: ts, confidence: 200, ip: "10.0.0.2"}})
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      wifi_conf = merged.nodes[peer_id].reachability.wifi.confidence

      # Remote 200 halved = 100, local 120 >= 100, so local kept
      assert wifi_conf == 120
    end
  end

  describe "merge semantics — new remote nodes" do
    test "new remote nodes get added to merged result" do
      my_id = TestNodeFactory.generate_uuid()
      new_peer_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      refute Map.has_key?(local.nodes, new_peer_id)

      remote = %{
        nodes: %{
          new_peer_id => TestNodeFactory.build_node_entry(%{
            node_id: new_peer_id,
            name: "BrandNewPeer"
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert Map.has_key?(merged.nodes, new_peer_id)
      assert merged.nodes[new_peer_id].name == "BrandNewPeer"
    end
  end

  describe "merge semantics — trusted hives" do
    test "trusted hives get merged using LWW by established_at" do
      my_id = TestNodeFactory.generate_uuid()
      hive_a_id = TestNodeFactory.generate_uuid()

      old_ts = ts_offset(-600)
      new_ts = ts_offset(-30)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:trusted_hives, hive_a_id],
        %{name: "OldTrust", established_at: old_ts, trust_ring: 1, permissions: ["read"]})

      remote = %{
        nodes: %{},
        trusted_hives: %{
          hive_a_id => %{name: "NewTrust", established_at: new_ts, trust_ring: 2, permissions: ["read", "write"]}
        }
      }

      merged = merge_directories(local, remote)
      assert merged.trusted_hives[hive_a_id].name == "NewTrust"
      assert merged.trusted_hives[hive_a_id].trust_ring == 2
    end

    test "local trusted hive kept when established_at is newer" do
      my_id = TestNodeFactory.generate_uuid()
      hive_a_id = TestNodeFactory.generate_uuid()

      old_ts = ts_offset(-600)
      new_ts = ts_offset(-30)

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:trusted_hives, hive_a_id],
        %{name: "LocalTrust", established_at: new_ts, trust_ring: 1, permissions: ["read"]})

      remote = %{
        nodes: %{},
        trusted_hives: %{
          hive_a_id => %{name: "RemoteTrust", established_at: old_ts, trust_ring: 2, permissions: ["read", "write"]}
        }
      }

      merged = merge_directories(local, remote)
      assert merged.trusted_hives[hive_a_id].name == "LocalTrust"
    end

    test "new remote trusted hive gets added" do
      my_id = TestNodeFactory.generate_uuid()
      hive_b_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      refute Map.has_key?(local.trusted_hives, hive_b_id)

      remote = %{
        nodes: %{},
        trusted_hives: %{
          hive_b_id => %{name: "NewHive", established_at: ts_offset(-10), trust_ring: 1, permissions: ["read"]}
        }
      }

      merged = merge_directories(local, remote)
      assert Map.has_key?(merged.trusted_hives, hive_b_id)
      assert merged.trusted_hives[hive_b_id].name == "NewHive"
    end
  end

  describe "merge semantics — directory version" do
    test "directory version increments on merge" do
      my_id = TestNodeFactory.generate_uuid()
      local = TestNodeFactory.build_directory(%{my_node_id: my_id, directory_version: 5})

      remote = %{nodes: %{}, trusted_hives: %{}}
      merged = merge_directories(local, remote)
      assert merged.directory_version == 6
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Query Logic
  # ---------------------------------------------------------------------------

  describe "find_sentant_by_name" do
    test "returns nodes sorted by confidence descending" do
      my_id = TestNodeFactory.generate_uuid()
      peer_a = TestNodeFactory.generate_uuid()
      peer_b = TestNodeFactory.generate_uuid()

      sentant = TestNodeFactory.build_sentant(%{name: "SharedSentant"})

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_a],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_a,
          sentants: [sentant],
          reachability: build_reach(%{wifi: %{last_seen: ts_offset(-5), confidence: 100, ip: "10.0.0.1"}})
        }))
      dir = put_in(dir, [:nodes, peer_b],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_b,
          sentants: [sentant],
          reachability: build_reach(%{wifi: %{last_seen: ts_offset(-5), confidence: 255, ip: "10.0.0.2"}})
        }))

      results = do_find_sentant_by_name(dir, "SharedSentant")
      assert length(results) == 2

      [{first_id, _, first_conf}, {second_id, _, second_conf}] = results
      assert first_id == peer_b
      assert second_id == peer_a
      assert first_conf >= second_conf
    end

    test "excludes revoked nodes" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      sentant = TestNodeFactory.build_sentant(%{name: "MySentant"})

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          status: :revoked,
          sentants: [sentant],
          reachability: build_reach(%{wifi: %{last_seen: ts_offset(-5), confidence: 200, ip: "10.0.0.1"}})
        }))

      results = do_find_sentant_by_name(dir, "MySentant")
      assert results == []
    end

    test "returns empty list when no matching sentants" do
      my_id = TestNodeFactory.generate_uuid()
      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})

      results = do_find_sentant_by_name(dir, "NonExistentSentant")
      assert results == []
    end

    test "matches sentants with string keys as well as atom keys" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      # Sentant with string key "name" (as could come from JSON)
      sentant = %{"name" => "StringKeySentant", "id" => TestNodeFactory.generate_uuid()}

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          sentants: [sentant],
          reachability: build_reach(%{wifi: %{last_seen: ts_offset(-5), confidence: 100, ip: "10.0.0.1"}})
        }))

      results = do_find_sentant_by_name(dir, "StringKeySentant")
      assert length(results) == 1
    end
  end

  describe "best_transport_for" do
    test "returns highest confidence transport" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{
            ble: %{last_seen: ts_offset(-5), confidence: 200, rssi: -55},
            wifi: %{last_seen: ts_offset(-5), confidence: 100, ip: "10.0.0.1"},
            lora: %{last_seen: ts_offset(-5), confidence: 50, via: nil}
          })
        }))

      assert {:ok, :ble, info} = do_best_transport_for(dir, peer_id)
      assert info.confidence == 200
    end

    test "includes :internet transport in ranking" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{
            ble: %{last_seen: nil, confidence: 0, rssi: nil},
            wifi: %{last_seen: nil, confidence: 0, ip: nil},
            lora: %{last_seen: nil, confidence: 0, via: nil},
            internet: %{last_seen: ts_offset(-5), confidence: 180}
          })
        }))

      assert {:ok, :internet, info} = do_best_transport_for(dir, peer_id)
      assert info.confidence == 180
    end

    test "returns :unreachable when all confidence below threshold" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{
            ble: %{last_seen: ts_offset(-5), confidence: 3, rssi: -90},
            wifi: %{last_seen: ts_offset(-5), confidence: 4, ip: "10.0.0.1"},
            lora: %{last_seen: ts_offset(-5), confidence: 2, via: nil},
            internet: %{last_seen: nil, confidence: 0}
          })
        }))

      assert {:error, :unreachable} = do_best_transport_for(dir, peer_id)
    end

    test "returns :unreachable for unknown node_id" do
      my_id = TestNodeFactory.generate_uuid()
      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      unknown_id = TestNodeFactory.generate_uuid()

      assert {:error, :unreachable} = do_best_transport_for(dir, unknown_id)
    end

    test "confidence exactly at threshold (5) is reachable" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{
            lora: %{last_seen: ts_offset(-5), confidence: 5, via: nil}
          })
        }))

      assert {:ok, :lora, _info} = do_best_transport_for(dir, peer_id)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Confidence Decay
  # ---------------------------------------------------------------------------

  describe "confidence decay" do
    test "multiply by 0.95 reduces confidence each round" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{wifi: %{last_seen: ts_offset(-5), confidence: 200, ip: "10.0.0.1"}})
        }))

      decayed = decay_all_confidence(dir)
      conf_after_1 = decayed.nodes[peer_id].reachability.wifi.confidence
      assert conf_after_1 == trunc(200 * 0.95)
      assert conf_after_1 == 190
    end

    test "repeated decay converges toward zero" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{wifi: %{last_seen: ts_offset(-5), confidence: 255, ip: "10.0.0.1"}})
        }))

      # Apply decay 100 times
      final = Enum.reduce(1..100, dir, fn _, acc -> decay_all_confidence(acc) end)
      conf = final.nodes[peer_id].reachability.wifi.confidence

      assert conf == 0
    end

    test "decay of zero stays zero" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{wifi: %{last_seen: nil, confidence: 0, ip: nil}})
        }))

      decayed = decay_all_confidence(dir)
      assert decayed.nodes[peer_id].reachability.wifi.confidence == 0
    end

    test "all transports are decayed independently" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          reachability: build_reach(%{
            wifi: %{last_seen: ts_offset(-5), confidence: 100, ip: "10.0.0.1"},
            ble: %{last_seen: ts_offset(-5), confidence: 200, rssi: -60},
            lora: %{last_seen: ts_offset(-5), confidence: 50, via: nil},
            internet: %{last_seen: ts_offset(-5), confidence: 150}
          })
        }))

      decayed = decay_all_confidence(dir)
      reach = decayed.nodes[peer_id].reachability

      assert reach.wifi.confidence == trunc(100 * 0.95)
      assert reach.ble.confidence == trunc(200 * 0.95)
      assert reach.lora.confidence == trunc(50 * 0.95)
      assert reach.internet.confidence == trunc(150 * 0.95)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Persistence — JSON roundtrip
  # ---------------------------------------------------------------------------

  describe "persistence roundtrip" do
    test "export then import preserves node entries" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          name: "PersistPeer",
          status: :active,
          reachability: build_reach(%{wifi: %{last_seen: ts_offset(-5), confidence: 180, ip: "10.0.0.5"}})
        }))

      exported = export_directory(dir)

      # Simulate JSON roundtrip
      {:ok, json} = Jason.encode(exported)
      {:ok, decoded} = Jason.decode(json, keys: :atoms)

      imported = import_directory(decoded)

      assert imported.my_node_id == my_id
      assert Map.has_key?(imported.nodes, peer_id)
      assert imported.nodes[peer_id].name == "PersistPeer"
      assert imported.nodes[peer_id].status == :active
    end

    test "compressed IDs survive hex encoding roundtrip" do
      my_id = TestNodeFactory.generate_uuid()
      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})

      original_cid = dir.nodes[my_id].compressed_id
      assert is_binary(original_cid) and byte_size(original_cid) == 4

      exported = export_directory(dir)
      hex_cid = exported.nodes[my_id].compressed_id
      assert is_binary(hex_cid)
      assert String.starts_with?(hex_cid, "0x")

      # Roundtrip through JSON
      {:ok, json} = Jason.encode(exported)
      {:ok, decoded} = Jason.decode(json, keys: :atoms)
      imported = import_directory(decoded)

      restored_cid = imported.nodes[my_id].compressed_id
      assert is_binary(restored_cid) and byte_size(restored_cid) == 4
      assert restored_cid == original_cid
    end

    test "status survives string encoding roundtrip" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{node_id: peer_id, status: :absent}))

      exported = export_directory(dir)
      assert exported.nodes[peer_id].status == "absent"

      {:ok, json} = Jason.encode(exported)
      {:ok, decoded} = Jason.decode(json, keys: :atoms)
      imported = import_directory(decoded)

      assert imported.nodes[peer_id].status == :absent
    end

    test "revoked status survives roundtrip" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{node_id: peer_id, status: :revoked}))

      exported = export_directory(dir)
      {:ok, json} = Jason.encode(exported)
      {:ok, decoded} = Jason.decode(json, keys: :atoms)
      imported = import_directory(decoded)

      assert imported.nodes[peer_id].status == :revoked
    end

    test "trusted_hives survive roundtrip" do
      my_id = TestNodeFactory.generate_uuid()
      hive_id = TestNodeFactory.generate_uuid()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:trusted_hives, hive_id],
        %{name: "TrustedHive", established_at: ts_offset(-100), trust_ring: 1, permissions: ["read"]})

      exported = export_directory(dir)
      {:ok, json} = Jason.encode(exported)
      {:ok, decoded} = Jason.decode(json, keys: :atoms)
      imported = import_directory(decoded)

      assert Map.has_key?(imported.trusted_hives, hive_id)
      assert imported.trusted_hives[hive_id].name == "TrustedHive"
    end

    test "directory_version is preserved" do
      my_id = TestNodeFactory.generate_uuid()
      dir = TestNodeFactory.build_directory(%{my_node_id: my_id, directory_version: 42})

      exported = export_directory(dir)
      {:ok, json} = Jason.encode(exported)
      {:ok, decoded} = Jason.decode(json, keys: :atoms)
      imported = import_directory(decoded)

      assert imported.directory_version == 42
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Pruning
  # ---------------------------------------------------------------------------

  describe "pruning" do
    test "absent + zero confidence + 7 days old = removed" do
      my_id = TestNodeFactory.generate_uuid()
      stale_id = TestNodeFactory.generate_uuid()

      # updated_at 8 days ago
      stale_ts = DateTime.utc_now()
      |> DateTime.add(-8 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, stale_id],
        TestNodeFactory.build_node_entry(%{
          node_id: stale_id,
          status: :absent,
          updated_at: stale_ts,
          reachability: TestNodeFactory.default_reachability()  # all confidence = 0
        }))

      assert Map.has_key?(dir.nodes, stale_id)

      pruned = prune_absent_nodes(dir)
      refute Map.has_key?(pruned.nodes, stale_id)
    end

    test "absent node with non-zero confidence is NOT pruned" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      stale_ts = DateTime.utc_now()
      |> DateTime.add(-8 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          status: :absent,
          updated_at: stale_ts,
          reachability: build_reach(%{lora: %{last_seen: stale_ts, confidence: 10, via: nil}})
        }))

      pruned = prune_absent_nodes(dir)
      assert Map.has_key?(pruned.nodes, peer_id)
    end

    test "absent node updated recently (< 7 days) is NOT pruned" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      recent_ts = DateTime.utc_now()
      |> DateTime.add(-3 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          status: :absent,
          updated_at: recent_ts,
          reachability: TestNodeFactory.default_reachability()
        }))

      pruned = prune_absent_nodes(dir)
      assert Map.has_key?(pruned.nodes, peer_id)
    end

    test "active node is never pruned even if old and zero confidence" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      stale_ts = DateTime.utc_now()
      |> DateTime.add(-30 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          status: :active,
          updated_at: stale_ts,
          reachability: TestNodeFactory.default_reachability()
        }))

      pruned = prune_absent_nodes(dir)
      assert Map.has_key?(pruned.nodes, peer_id)
    end

    test "self is never pruned regardless of conditions" do
      my_id = TestNodeFactory.generate_uuid()

      stale_ts = DateTime.utc_now()
      |> DateTime.add(-30 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      # Make self look like it should be pruned (absent, old, zero confidence)
      dir = put_in(dir, [:nodes, my_id],
        TestNodeFactory.build_node_entry(%{
          node_id: my_id,
          status: :absent,
          updated_at: stale_ts,
          reachability: TestNodeFactory.default_reachability()
        }))

      pruned = prune_absent_nodes(dir)
      assert Map.has_key?(pruned.nodes, my_id)
    end

    test "revoked node with zero confidence and old timestamp is NOT pruned (only :absent triggers prune)" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      stale_ts = DateTime.utc_now()
      |> DateTime.add(-30 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      dir = TestNodeFactory.build_directory(%{my_node_id: my_id})
      dir = put_in(dir, [:nodes, peer_id],
        TestNodeFactory.build_node_entry(%{
          node_id: peer_id,
          status: :revoked,
          updated_at: stale_ts,
          reachability: TestNodeFactory.default_reachability()
        }))

      pruned = prune_absent_nodes(dir)
      # Revoked is NOT :absent, so it should NOT be pruned by absent-node pruning
      assert Map.has_key?(pruned.nodes, peer_id)
    end
  end
end
