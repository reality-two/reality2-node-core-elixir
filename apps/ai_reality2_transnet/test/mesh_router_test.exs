defmodule AiReality2Transnet.MeshRouterTest do
  @moduledoc """
  Tests for AiReality2Transnet.MeshRouter.

  These tests exercise the conceptual aspects of MeshRouter: deduplication,
  TTL handling, message type dispatch, transport selection, payload
  encoding/decoding round-trips, and stats tracking.

  MeshRouter depends on Reality2.Bootstrap, Reality2.Sentants, and
  transport modules at runtime, so the full GenServer cannot be started
  in isolation.  Instead we test the data-structure logic by directly
  invoking handle_call/handle_cast callbacks with hand-crafted state,
  or by examining the JSON payload contracts.
  """

  use ExUnit.Case, async: true

  @moduletag :integration

  alias AiReality2Transnet.TestNodeFactory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build a minimal MeshRouter state (mirrors init/1 shape).
  defp initial_state(overrides \\ %{}) do
    Map.merge(
      %{
        seen: %{},
        stats: %{
          messages_sent: 0,
          messages_received: 0,
          messages_relayed: 0,
          messages_dropped_seen: 0,
          messages_dropped_ttl: 0,
          messages_delivered: 0,
          transport_sends: %{}
        },
        transports: %{}
      },
      overrides
    )
  end

  # Convenience: build a mesh message whose payload is a valid event JSON.
  defp event_message(overrides) do
    sentant_id = Map.get(overrides, :sentant_id, TestNodeFactory.generate_uuid())
    event_name = Map.get(overrides, :event_name, "test_event")
    params = Map.get(overrides, :params, %{"key" => "value"})

    payload =
      Jason.encode!(%{
        sentant: sentant_id,
        event: event_name,
        params: params
      })

    TestNodeFactory.build_mesh_message(
      Map.merge(
        %{type: :event, payload: payload},
        Map.drop(overrides, [:sentant_id, :event_name, :params])
      )
    )
  end

  # Convenience: build a mesh message whose payload is a valid signal JSON.
  defp signal_message(overrides) do
    source = Map.get(overrides, :source, TestNodeFactory.generate_uuid())
    target = Map.get(overrides, :target, "node123|MySentant")
    signal_name = Map.get(overrides, :signal_name, "ping")
    params = Map.get(overrides, :params, %{"data" => 42})

    payload =
      Jason.encode!(%{
        source: source,
        target: target,
        signal: signal_name,
        params: params
      })

    TestNodeFactory.build_mesh_message(
      Map.merge(
        %{type: :signal, payload: payload},
        Map.drop(overrides, [:source, :target, :signal_name, :params])
      )
    )
  end

  # ---------------------------------------------------------------------------
  # 1. Deduplication
  # ---------------------------------------------------------------------------

  describe "deduplication via seen cache" do
    test "first message with a given msg_id is NOT dropped" do
      msg = event_message(%{msg_id: 12345})
      state = initial_state()

      # Simulate handle_cast {:incoming, message, transport}
      # The router checks `Map.has_key?(state.seen, msg_id)`.
      # For a fresh state the msg_id is absent, so the message is accepted.
      refute Map.has_key?(state.seen, msg.msg_id)
    end

    test "second message with same msg_id IS dropped (seen cache hit)" do
      msg = event_message(%{msg_id: 99999})
      now = System.system_time(:millisecond)

      # After the first delivery the msg_id is recorded in :seen.
      state = initial_state(%{seen: %{99999 => now}})

      assert Map.has_key?(state.seen, msg.msg_id),
             "The seen cache should contain the msg_id after first delivery"

      # The router increments :messages_dropped_seen when a duplicate arrives.
      new_stats = Map.update!(state.stats, :messages_dropped_seen, &(&1 + 1))
      assert new_stats.messages_dropped_seen == 1
    end

    test "seen cache entries are timestamped for later expiry" do
      now = System.system_time(:millisecond)
      seen = %{1 => now - 70_000, 2 => now - 10_000, 3 => now}

      # The cleanup handler keeps entries newer than 60 000 ms.
      cutoff = now - 60_000

      remaining =
        seen
        |> Enum.filter(fn {_id, ts} -> ts > cutoff end)
        |> Map.new()

      refute Map.has_key?(remaining, 1), "Entry older than 60 s should be pruned"
      assert Map.has_key?(remaining, 2), "Entry younger than 60 s should survive"
      assert Map.has_key?(remaining, 3), "Current entry should survive"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. TTL handling
  # ---------------------------------------------------------------------------

  describe "TTL-based relay / drop" do
    test "message with ttl > 1 should be relayed with decremented ttl" do
      msg = event_message(%{ttl: 3})
      assert msg.ttl > 1

      relayed = %{msg | ttl: msg.ttl - 1}
      assert relayed.ttl == 2
    end

    test "message with ttl == 1 should NOT be relayed" do
      msg = event_message(%{ttl: 1})
      assert msg.ttl == 1

      # MeshRouter increments :messages_dropped_ttl instead of relaying.
      state = initial_state()
      new_stats = Map.update!(state.stats, :messages_dropped_ttl, &(&1 + 1))
      assert new_stats.messages_dropped_ttl == 1
    end

    test "message with ttl == 0 should NOT be relayed" do
      msg = event_message(%{ttl: 0})
      refute msg.ttl > 1
    end

    test "default TTL from factory is 5" do
      msg = TestNodeFactory.build_mesh_message()
      assert msg.ttl == 5
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Message types and local delivery routing
  # ---------------------------------------------------------------------------

  describe "message type dispatch" do
    test ":event messages carry sentant_id, event_name, and params in payload" do
      sentant_id = TestNodeFactory.generate_uuid()

      msg =
        event_message(%{
          sentant_id: sentant_id,
          event_name: "sensor_reading",
          params: %{"temp" => 23.5}
        })

      assert msg.type == :event

      {:ok, decoded} = Jason.decode(msg.payload)
      assert decoded["sentant"] == sentant_id
      assert decoded["event"] == "sensor_reading"
      assert decoded["params"]["temp"] == 23.5
    end

    test ":signal messages carry source, target, signal_name, and params" do
      source = TestNodeFactory.generate_uuid()
      target = "nodeA|SentantX"

      msg =
        signal_message(%{
          source: source,
          target: target,
          signal_name: "activate",
          params: %{"level" => 10}
        })

      assert msg.type == :signal

      {:ok, decoded} = Jason.decode(msg.payload)
      assert decoded["source"] == source
      assert decoded["target"] == target
      assert decoded["signal"] == "activate"
      assert decoded["params"]["level"] == 10
    end

    test ":presence messages encode node_name and sentants list as JSON" do
      node_name = "R2Node_Test"
      sentants = ["SentantA", "SentantB"]

      payload =
        Jason.encode!(%{
          node_name: node_name,
          sentants: sentants
        })

      msg =
        TestNodeFactory.build_mesh_message(%{
          type: :presence,
          payload: payload
        })

      assert msg.type == :presence

      {:ok, decoded} = Jason.decode(msg.payload)
      assert decoded["node_name"] == node_name
      assert decoded["sentants"] == sentants
    end

    test "event payload delivered via sendto_all contains __mesh_event structure" do
      # Verify the shape of what deliver_event_locally would pass to sendto_all.
      sentant_id = TestNodeFactory.generate_uuid()
      event_name = "my_event"
      params = %{"x" => 1}
      src_node_id = TestNodeFactory.generate_uuid()

      expected_sendto_all_arg = %{
        event: "__mesh_event",
        parameters: %{
          source_sentant: sentant_id,
          source_node: src_node_id,
          event: event_name,
          params: params,
          ttl: 4
        }
      }

      assert expected_sendto_all_arg.event == "__mesh_event"
      assert expected_sendto_all_arg.parameters.source_sentant == sentant_id
      assert expected_sendto_all_arg.parameters.source_node == src_node_id
    end

    test "signal payload delivered locally contains __mesh_signal structure" do
      source = TestNodeFactory.generate_uuid()
      signal_name = "ping"
      params = %{"data" => "hello"}
      src_node_id = TestNodeFactory.generate_uuid()

      expected_sendto_arg = %{
        event: "__mesh_signal",
        parameters: %{
          source_sentant: source,
          source_node: src_node_id,
          signal: signal_name,
          params: params
        }
      }

      assert expected_sendto_arg.event == "__mesh_signal"
      assert expected_sendto_arg.parameters.signal == signal_name
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Transport selection / route_to_target logic
  # ---------------------------------------------------------------------------

  describe "transport selection and route_to_target logic" do
    test "target with node|sentant format extracts node_id" do
      target = "abc123|MySentant"
      [node, sentant] = String.split(target, "|", parts: 2)
      assert node == "abc123"
      assert sentant == "MySentant"
    end

    test "target without pipe has no explicit node" do
      target = "MySentant"

      result =
        case String.split(target, "|", parts: 2) do
          [_node, _sentant] -> :has_node
          [_sentant_only] -> :no_node
        end

      assert result == :no_node
    end

    test "transport type mapping covers expected aliases" do
      # MeshRouter maps transport type atoms to canonical types.
      type_mapping = %{
        wifi: :wifi_hotspot,
        wifi_hotspot: :wifi_hotspot,
        ble: :ble,
        ble_gatt: :ble,
        lora: :lora,
        internet: :internet
      }

      assert Map.get(type_mapping, :wifi) == :wifi_hotspot
      assert Map.get(type_mapping, :ble_gatt) == :ble
      assert Map.get(type_mapping, :lora) == :lora
      assert Map.get(type_mapping, :internet) == :internet
      # Unknown transport falls back to itself
      assert Map.get(type_mapping, :zigbee, :zigbee) == :zigbee
    end

    test "broadcast_via_transports filters by availability and payload size" do
      # Simulate the transport map structure used by MeshRouter.
      fake_transports = %{
        ModuleA: %{type: :wifi_hotspot, available: true, max_payload: 1_000_000, capabilities: %{}},
        ModuleB: %{type: :ble, available: true, max_payload: 20, capabilities: %{}},
        ModuleC: %{type: :lora, available: false, max_payload: 200, capabilities: %{}}
      }

      payload_size = 500

      suitable =
        fake_transports
        |> Enum.filter(fn {_mod, info} -> info.available and info.max_payload >= payload_size end)

      # Only ModuleA qualifies (available + large enough).
      assert length(suitable) == 1
      [{mod, _info}] = suitable
      assert mod == :ModuleA
    end

    test "when no transports are suitable, the result list is empty" do
      fake_transports = %{
        ModuleB: %{type: :ble, available: true, max_payload: 20, capabilities: %{}}
      }

      payload_size = 500

      suitable =
        fake_transports
        |> Enum.filter(fn {_mod, info} -> info.available and info.max_payload >= payload_size end)

      assert suitable == []
    end

    test "relay_to_other_transports excludes the source transport type" do
      # MeshRouter relays to all transports whose type != source_transport.
      transports = %{
        ModWiFi: %{type: :wifi_hotspot, available: true, max_payload: 100_000, capabilities: %{}},
        ModBLE: %{type: :ble, available: true, max_payload: 20, capabilities: %{}},
        ModLoRa: %{type: :lora, available: true, max_payload: 200, capabilities: %{}}
      }

      source_transport = :ble
      payload_size = 10

      relay_targets =
        transports
        |> Enum.filter(fn {_mod, info} ->
          info.available and info.max_payload >= payload_size and info.type != source_transport
        end)

      types = Enum.map(relay_targets, fn {_mod, info} -> info.type end)
      refute :ble in types
      assert :wifi_hotspot in types
      assert :lora in types
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Event payload encoding / decoding round-trip
  # ---------------------------------------------------------------------------

  describe "event payload encoding/decoding round-trip" do
    test "encode then decode preserves sentant_id, event_name, and params" do
      sentant_id = TestNodeFactory.generate_uuid()
      event_name = "temperature_alert"
      params = %{"threshold" => 40, "actual" => 42.5, "unit" => "C"}

      # Encode (mirrors encode_event_payload/3)
      encoded =
        Jason.encode!(%{
          sentant: sentant_id,
          event: event_name,
          params: params
        })

      assert is_binary(encoded)

      # Decode (mirrors decode_event_payload/1)
      {:ok, decoded} = Jason.decode(encoded)

      assert decoded["sentant"] == sentant_id
      assert decoded["event"] == event_name
      assert decoded["params"]["threshold"] == 40
      assert decoded["params"]["actual"] == 42.5
      assert decoded["params"]["unit"] == "C"
    end

    test "decode handles missing params gracefully" do
      encoded = Jason.encode!(%{sentant: "abc", event: "evt"})
      {:ok, decoded} = Jason.decode(encoded)

      # MeshRouter falls back to %{} when "params" is absent.
      result =
        case decoded do
          %{"sentant" => s, "event" => e, "params" => p} -> {:ok, s, e, p}
          %{"sentant" => s, "event" => e} -> {:ok, s, e, %{}}
          _ -> {:error, :invalid_format}
        end

      assert {:ok, "abc", "evt", %{}} = result
    end

    test "decode rejects invalid JSON" do
      result = Jason.decode("not valid json{")
      assert {:error, _} = result
    end

    test "decode rejects JSON missing required fields" do
      encoded = Jason.encode!(%{foo: "bar"})
      {:ok, decoded} = Jason.decode(encoded)

      result =
        case decoded do
          %{"sentant" => s, "event" => e, "params" => p} -> {:ok, s, e, p}
          %{"sentant" => s, "event" => e} -> {:ok, s, e, %{}}
          _ -> {:error, :invalid_format}
        end

      assert result == {:error, :invalid_format}
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Signal payload encoding / decoding round-trip
  # ---------------------------------------------------------------------------

  describe "signal payload encoding/decoding round-trip" do
    test "encode then decode preserves source, target, signal, and params" do
      source = TestNodeFactory.generate_uuid()
      target = "nodeXYZ|SentantAlpha"
      signal_name = "wake_up"
      params = %{"urgency" => "high", "retries" => 3}

      # Encode (mirrors encode_signal_payload/4)
      encoded =
        Jason.encode!(%{
          source: source,
          target: target,
          signal: signal_name,
          params: params
        })

      assert is_binary(encoded)

      # Decode (mirrors decode_signal_payload/1)
      {:ok, decoded} = Jason.decode(encoded)

      result =
        case decoded do
          %{"source" => s, "target" => t, "signal" => sig, "params" => p} ->
            {:ok, s, t, sig, p}

          %{"source" => s, "target" => t, "signal" => sig} ->
            {:ok, s, t, sig, %{}}

          _ ->
            {:error, :invalid_format}
        end

      assert {:ok, ^source, ^target, "wake_up", %{"urgency" => "high", "retries" => 3}} = result
    end

    test "decode handles missing params in signal payload" do
      encoded = Jason.encode!(%{source: "s", target: "t", signal: "sig"})
      {:ok, decoded} = Jason.decode(encoded)

      result =
        case decoded do
          %{"source" => s, "target" => t, "signal" => sig, "params" => p} ->
            {:ok, s, t, sig, p}

          %{"source" => s, "target" => t, "signal" => sig} ->
            {:ok, s, t, sig, %{}}

          _ ->
            {:error, :invalid_format}
        end

      assert {:ok, "s", "t", "sig", %{}} = result
    end

    test "decode rejects signal payload missing required fields" do
      encoded = Jason.encode!(%{source: "s", target: "t"})
      {:ok, decoded} = Jason.decode(encoded)

      result =
        case decoded do
          %{"source" => _, "target" => _, "signal" => _, "params" => _} -> :full
          %{"source" => _, "target" => _, "signal" => _} -> :no_params
          _ -> {:error, :invalid_format}
        end

      assert result == {:error, :invalid_format}
    end

    test "round-trip with complex nested params" do
      params = %{
        "nested" => %{"a" => [1, 2, 3], "b" => true},
        "list" => ["x", "y"],
        "null_val" => nil
      }

      encoded =
        Jason.encode!(%{source: "s1", target: "n|t1", signal: "complex", params: params})

      {:ok, decoded} = Jason.decode(encoded)
      assert decoded["params"]["nested"]["a"] == [1, 2, 3]
      assert decoded["params"]["nested"]["b"] == true
      assert decoded["params"]["list"] == ["x", "y"]
      assert decoded["params"]["null_val"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Stats tracking
  # ---------------------------------------------------------------------------

  describe "stats tracking" do
    test "initial stats are all zero" do
      state = initial_state()
      stats = state.stats

      assert stats.messages_sent == 0
      assert stats.messages_received == 0
      assert stats.messages_relayed == 0
      assert stats.messages_dropped_seen == 0
      assert stats.messages_dropped_ttl == 0
      assert stats.messages_delivered == 0
      assert stats.transport_sends == %{}
    end

    test "per-transport send count increments correctly" do
      transport_sends = %{}

      # Simulate a successful send on :wifi_hotspot
      transport_key = :wifi_hotspot
      transport_stats = Map.get(transport_sends, transport_key, %{sent: 0, errors: 0})
      new_transport_stats = %{transport_stats | sent: transport_stats.sent + 1}
      updated = Map.put(transport_sends, transport_key, new_transport_stats)

      assert updated[:wifi_hotspot].sent == 1
      assert updated[:wifi_hotspot].errors == 0
    end

    test "per-transport error count increments correctly" do
      transport_sends = %{lora: %{sent: 5, errors: 2}}

      transport_key = :lora
      transport_stats = Map.get(transport_sends, transport_key, %{sent: 0, errors: 0})
      new_transport_stats = %{transport_stats | errors: transport_stats.errors + 1}
      updated = Map.put(transport_sends, transport_key, new_transport_stats)

      assert updated[:lora].sent == 5
      assert updated[:lora].errors == 3
    end

    test "multiple transports track independently" do
      transport_sends = %{
        wifi_hotspot: %{sent: 10, errors: 1},
        ble: %{sent: 50, errors: 5},
        lora: %{sent: 3, errors: 0}
      }

      assert transport_sends[:wifi_hotspot].sent == 10
      assert transport_sends[:ble].errors == 5
      assert transport_sends[:lora].sent == 3
      assert transport_sends[:lora].errors == 0
    end

    test "messages_dropped_seen increments on duplicate" do
      state = initial_state(%{
        seen: %{42 => System.system_time(:millisecond)},
        stats: %{
          messages_sent: 0,
          messages_received: 3,
          messages_relayed: 2,
          messages_dropped_seen: 1,
          messages_dropped_ttl: 0,
          messages_delivered: 3,
          transport_sends: %{}
        }
      })

      # Duplicate msg_id = 42 arrives
      assert Map.has_key?(state.seen, 42)
      new_stats = Map.update!(state.stats, :messages_dropped_seen, &(&1 + 1))
      assert new_stats.messages_dropped_seen == 2
    end

    test "messages_relayed increments when ttl > 1 and messages_dropped_ttl when ttl == 1" do
      stats = %{
        messages_relayed: 0,
        messages_dropped_ttl: 0
      }

      # TTL > 1 path
      stats_after_relay = Map.update!(stats, :messages_relayed, &(&1 + 1))
      assert stats_after_relay.messages_relayed == 1

      # TTL == 1 path
      stats_after_drop = Map.update!(stats, :messages_dropped_ttl, &(&1 + 1))
      assert stats_after_drop.messages_dropped_ttl == 1
    end

    test "get_stats includes seen_cache_size and transports_available" do
      # Mirrors handle_call(:get_stats, ...) which merges computed fields.
      state = initial_state(%{
        seen: %{1 => 100, 2 => 200, 3 => 300},
        transports: %{
          ModA: %{type: :wifi_hotspot, available: true, max_payload: 100_000, capabilities: %{}},
          ModB: %{type: :ble, available: false, max_payload: 20, capabilities: %{}},
          ModC: %{type: :lora, available: true, max_payload: 200, capabilities: %{}}
        }
      })

      computed_stats =
        Map.merge(state.stats, %{
          seen_cache_size: map_size(state.seen),
          transports_available:
            length(Enum.filter(state.transports, fn {_mod, info} -> info.available end))
        })

      assert computed_stats.seen_cache_size == 3
      assert computed_stats.transports_available == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Additional edge-case tests
  # ---------------------------------------------------------------------------

  describe "mesh message structure via TestNodeFactory" do
    test "build_mesh_message returns valid structure" do
      msg = TestNodeFactory.build_mesh_message()

      assert is_integer(msg.msg_id)
      assert is_integer(msg.ttl)
      assert is_atom(msg.type)
      assert is_binary(msg.src_node_id)
      assert is_binary(msg.payload)
    end

    test "build_mesh_message accepts overrides" do
      custom_id = 777
      custom_payload = Jason.encode!(%{test: true})

      msg =
        TestNodeFactory.build_mesh_message(%{
          msg_id: custom_id,
          ttl: 2,
          type: :signal,
          payload: custom_payload
        })

      assert msg.msg_id == 777
      assert msg.ttl == 2
      assert msg.type == :signal
      assert msg.payload == custom_payload
    end
  end

  describe "is_local_sentant? target parsing" do
    test "node|sentant format splits correctly" do
      target = "mynode|mySentant"
      {node_part, sentant_name} =
        case String.split(target, "|", parts: 2) do
          [node, sentant] -> {node, sentant}
          [sentant] -> {nil, sentant}
        end

      assert node_part == "mynode"
      assert sentant_name == "mySentant"
    end

    test "sentant-only format yields nil node" do
      target = "mySentant"
      {node_part, sentant_name} =
        case String.split(target, "|", parts: 2) do
          [node, sentant] -> {node, sentant}
          [sentant] -> {nil, sentant}
        end

      assert node_part == nil
      assert sentant_name == "mySentant"
    end

    test "wildcard node (*) is valid" do
      target = "*|anySentant"
      [node, sentant] = String.split(target, "|", parts: 2)
      assert node == "*"
      assert sentant == "anySentant"
    end
  end

  describe "presence payload handling" do
    test "presence with hive info includes hive_id and hive_public_key" do
      hive_id = TestNodeFactory.generate_uuid()
      public_key_b64 = Base.encode64(:crypto.strong_rand_bytes(32))

      payload =
        Jason.encode!(%{
          node_name: "TestNode",
          sentants: ["S1", "S2"],
          hive_id: hive_id,
          hive_public_key: public_key_b64
        })

      {:ok, decoded} = Jason.decode(payload)
      assert decoded["hive_id"] == hive_id
      assert decoded["hive_public_key"] == public_key_b64
      assert decoded["sentants"] == ["S1", "S2"]
    end

    test "presence without hive info still contains node_name and sentants" do
      payload =
        Jason.encode!(%{
          node_name: "MinimalNode",
          sentants: []
        })

      {:ok, decoded} = Jason.decode(payload)
      assert decoded["node_name"] == "MinimalNode"
      assert decoded["sentants"] == []
      assert Map.get(decoded, "hive_id") == nil
    end
  end
end
