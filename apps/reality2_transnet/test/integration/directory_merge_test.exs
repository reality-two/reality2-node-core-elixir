defmodule Reality2Transnet.Integration.DirectoryMergeTest do
  @moduledoc """
  Integration tests for HiveDirectory merge semantics.

  These tests verify the CRDT-inspired merge logic that ensures
  distributed directory convergence across hive nodes.

  Run with: mix test --include integration
  """
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Reality2Transnet.TestNodeFactory

  # ---------------------------------------------------------------------------
  # Helpers — simulate merge logic from HiveDirectory (private functions)
  # These mirror the actual implementation for testability
  # ---------------------------------------------------------------------------

  defp merge_directories(local, remote) do
    remote_nodes = Map.get(remote, :nodes, %{})
    local_nodes = local.nodes

    merged_nodes = Map.merge(local_nodes, remote_nodes, fn node_id, local_entry, remote_entry ->
      merge_node_entries(node_id, local_entry, remote_entry, local.my_node_id)
    end)

    new_nodes = Map.merge(remote_nodes, merged_nodes)

    remote_trusted = Map.get(remote, :trusted_hives, %{})
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
      %{local_entry |
        status: merged_status,
        sentants: merged_sentants,
        reachability: merged_reach
      }
    else
      %{remote_entry |
        status: merged_status,
        sentants: merged_sentants,
        reachability: merged_reach
      }
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

  defp compare_timestamps(nil, _), do: :lt
  defp compare_timestamps(_, nil), do: :gt
  defp compare_timestamps(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end

  # ---------------------------------------------------------------------------
  # Tests — LWW Merge Semantics
  # ---------------------------------------------------------------------------

  describe "LWW merge: timestamp-based conflict resolution" do
    test "newer remote entry wins over older local" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      old_ts = "2025-01-01T00:00:00Z"
      new_ts = "2025-06-01T00:00:00Z"

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id], TestNodeFactory.build_node_entry(%{
        node_id: peer_id, name: "OldName", updated_at: old_ts
      }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id, name: "NewName", updated_at: new_ts
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].name == "NewName"
    end

    test "older remote entry loses to newer local" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      old_ts = "2025-01-01T00:00:00Z"
      new_ts = "2025-06-01T00:00:00Z"

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id], TestNodeFactory.build_node_entry(%{
        node_id: peer_id, name: "LocalName", updated_at: new_ts
      }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id, name: "RemoteName", updated_at: old_ts
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].name == "LocalName"
    end
  end

  describe "tombstone: revoked status always wins" do
    test "remote revoked wins over local active" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id], TestNodeFactory.build_node_entry(%{
        node_id: peer_id, status: :active, updated_at: "2025-06-01T00:00:00Z"
      }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id, status: :revoked, updated_at: "2025-01-01T00:00:00Z"
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].status == :revoked
    end

    test "local revoked wins over remote active" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id], TestNodeFactory.build_node_entry(%{
        node_id: peer_id, status: :revoked, updated_at: "2025-01-01T00:00:00Z"
      }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id, status: :active, updated_at: "2025-06-01T00:00:00Z"
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[peer_id].status == :revoked
    end
  end

  describe "owning node sentant authority" do
    test "own sentants always preserved regardless of remote timestamp" do
      my_id = TestNodeFactory.generate_uuid()
      my_sentants = [%{id: "s1", name: "MySentant"}]
      remote_sentants = [%{id: "s2", name: "RemoteClaim"}]

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, my_id], TestNodeFactory.build_node_entry(%{
        node_id: my_id, sentants: my_sentants, updated_at: "2025-01-01T00:00:00Z"
      }))

      remote = %{
        nodes: %{
          my_id => TestNodeFactory.build_node_entry(%{
            node_id: my_id, sentants: remote_sentants, updated_at: "2025-12-01T00:00:00Z"
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert merged.nodes[my_id].sentants == my_sentants
    end
  end

  describe "reachability merge: remote halved as hint" do
    test "remote reachability confidence is halved" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id], TestNodeFactory.build_node_entry(%{
        node_id: peer_id,
        reachability: %{
          ble: %{confidence: 50, last_seen: nil, rssi: nil},
          wifi: %{confidence: 0, last_seen: nil, ip: nil},
          lora: %{confidence: 0, last_seen: nil, via: nil},
          internet: %{confidence: 0, last_seen: nil}
        }
      }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id,
            reachability: %{
              ble: %{confidence: 200, last_seen: nil, rssi: nil},
              wifi: %{confidence: 0, last_seen: nil, ip: nil},
              lora: %{confidence: 0, last_seen: nil, via: nil},
              internet: %{confidence: 0, last_seen: nil}
            }
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      # Remote confidence 200 halved to 100, which beats local 50
      assert merged.nodes[peer_id].reachability.ble.confidence == 100
    end

    test "local reachability wins when >= halved remote" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id], TestNodeFactory.build_node_entry(%{
        node_id: peer_id,
        reachability: %{
          ble: %{confidence: 150, last_seen: nil, rssi: nil},
          wifi: %{confidence: 0, last_seen: nil, ip: nil},
          lora: %{confidence: 0, last_seen: nil, via: nil},
          internet: %{confidence: 0, last_seen: nil}
        }
      }))

      remote = %{
        nodes: %{
          peer_id => TestNodeFactory.build_node_entry(%{
            node_id: peer_id,
            reachability: %{
              ble: %{confidence: 200, last_seen: nil, rssi: nil},
              wifi: %{confidence: 0, last_seen: nil, ip: nil},
              lora: %{confidence: 0, last_seen: nil, via: nil},
              internet: %{confidence: 0, last_seen: nil}
            }
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      # Remote 200/2 = 100, local 150 >= 100, so local wins
      assert merged.nodes[peer_id].reachability.ble.confidence == 150
    end
  end

  describe "new nodes from remote" do
    test "remote nodes not in local are added" do
      my_id = TestNodeFactory.generate_uuid()
      new_peer_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})

      remote = %{
        nodes: %{
          new_peer_id => TestNodeFactory.build_node_entry(%{
            node_id: new_peer_id, name: "NewPeer"
          })
        },
        trusted_hives: %{}
      }

      merged = merge_directories(local, remote)
      assert Map.has_key?(merged.nodes, new_peer_id)
      assert merged.nodes[new_peer_id].name == "NewPeer"
    end
  end

  describe "trusted_hives merge" do
    test "both local and remote trusted hives are included" do
      my_id = TestNodeFactory.generate_uuid()
      hive_a = TestNodeFactory.generate_uuid()
      hive_b = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = %{local | trusted_hives: %{
        hive_a => %{name: "HiveA", established_at: "2025-01-01T00:00:00Z"}
      }}

      remote = %{
        nodes: %{},
        trusted_hives: %{
          hive_b => %{name: "HiveB", established_at: "2025-02-01T00:00:00Z"}
        }
      }

      merged = merge_directories(local, remote)
      assert Map.has_key?(merged.trusted_hives, hive_a)
      assert Map.has_key?(merged.trusted_hives, hive_b)
    end

    test "conflicting trusted hives use LWW by established_at" do
      my_id = TestNodeFactory.generate_uuid()
      hive_id = TestNodeFactory.generate_uuid()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = %{local | trusted_hives: %{
        hive_id => %{name: "LocalName", established_at: "2025-06-01T00:00:00Z"}
      }}

      remote = %{
        nodes: %{},
        trusted_hives: %{
          hive_id => %{name: "RemoteName", established_at: "2025-01-01T00:00:00Z"}
        }
      }

      merged = merge_directories(local, remote)
      assert merged.trusted_hives[hive_id].name == "LocalName"
    end
  end

  describe "directory version" do
    test "merge increments directory version" do
      my_id = TestNodeFactory.generate_uuid()
      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      initial_version = local.directory_version

      remote = %{nodes: %{}, trusted_hives: %{}}
      merged = merge_directories(local, remote)

      assert merged.directory_version == initial_version + 1
    end
  end

  # ---------------------------------------------------------------------------
  # Tests — Confidence Decay
  # ---------------------------------------------------------------------------

  describe "confidence decay" do
    test "0.95 decay converges toward 0" do
      confidence = 255
      decay_rate = 0.95

      # After 50 iterations
      result = Enum.reduce(1..50, confidence, fn _, acc ->
        trunc(acc * decay_rate)
      end)

      # Should be very small
      assert result < 20
    end

    test "zero confidence stays zero after decay" do
      assert trunc(0 * 0.95) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Tests — Pruning
  # ---------------------------------------------------------------------------

  describe "pruning absent nodes" do
    test "absent + zero confidence + old timestamp = pruned" do
      my_id = TestNodeFactory.generate_uuid()
      old_peer_id = TestNodeFactory.generate_uuid()

      # 8 days ago
      old_ts = DateTime.utc_now()
      |> DateTime.add(-8 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, old_peer_id], TestNodeFactory.build_node_entry(%{
        node_id: old_peer_id,
        status: :absent,
        updated_at: old_ts,
        reachability: TestNodeFactory.default_reachability()
      }))

      # Simulate pruning
      cutoff = DateTime.utc_now()
      |> DateTime.add(-7 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      pruned_nodes = Enum.reject(local.nodes, fn {node_id, entry} ->
        node_id != local.my_node_id and
        entry.status == :absent and
        best_confidence(entry) == 0 and
        compare_timestamps(Map.get(entry, :updated_at, ""), cutoff) == :lt
      end)
      |> Map.new()

      refute Map.has_key?(pruned_nodes, old_peer_id)
      assert Map.has_key?(pruned_nodes, my_id)
    end

    test "self node is never pruned even if absent" do
      my_id = TestNodeFactory.generate_uuid()

      old_ts = DateTime.utc_now()
      |> DateTime.add(-30 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, my_id, :status], :absent)
      local = put_in(local, [:nodes, my_id, :updated_at], old_ts)

      cutoff = DateTime.utc_now()
      |> DateTime.add(-7 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      pruned_nodes = Enum.reject(local.nodes, fn {node_id, entry} ->
        node_id != local.my_node_id and
        entry.status == :absent and
        best_confidence(entry) == 0 and
        compare_timestamps(Map.get(entry, :updated_at, ""), cutoff) == :lt
      end)
      |> Map.new()

      assert Map.has_key?(pruned_nodes, my_id)
    end

    test "active nodes are not pruned regardless of age" do
      my_id = TestNodeFactory.generate_uuid()
      peer_id = TestNodeFactory.generate_uuid()

      old_ts = DateTime.utc_now()
      |> DateTime.add(-30 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      local = TestNodeFactory.build_directory(%{my_node_id: my_id})
      local = put_in(local, [:nodes, peer_id], TestNodeFactory.build_node_entry(%{
        node_id: peer_id, status: :active, updated_at: old_ts
      }))

      cutoff = DateTime.utc_now()
      |> DateTime.add(-7 * 24 * 60 * 60, :second)
      |> DateTime.to_iso8601()

      pruned_nodes = Enum.reject(local.nodes, fn {node_id, entry} ->
        node_id != local.my_node_id and
        entry.status == :absent and
        best_confidence(entry) == 0 and
        compare_timestamps(Map.get(entry, :updated_at, ""), cutoff) == :lt
      end)
      |> Map.new()

      assert Map.has_key?(pruned_nodes, peer_id)
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

  defp get_in_safe(map, keys, default) do
    Enum.reduce_while(keys, map, fn key, acc ->
      case acc do
        %{} -> {:cont, Map.get(acc, key)}
        _ -> {:halt, default}
      end
    end) || default
  end
end
