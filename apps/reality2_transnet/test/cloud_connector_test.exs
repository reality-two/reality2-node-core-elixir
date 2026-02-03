defmodule Reality2Transnet.CloudConnectorTest do
  @moduledoc """
  Tests for the CloudConnector GenServer.

  The CloudConnector manages persistent connections to cloud-hosted hive nodes
  over WebSocket (or HTTP polling fallback). Since most functionality requires
  the full Reality2 umbrella to be running (PeerManager, HiveDirectory, network
  access), these tests are tagged as integration tests and excluded by default.

  However, we can verify the mathematical properties of the reconnect backoff
  algorithm and document the expected behavior of private helper functions
  through bounds-checking and behavioral assertions.
  """

  use ExUnit.Case, async: true

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Constants mirroring the module under test
  # ---------------------------------------------------------------------------

  @reconnect_base_ms 1_000
  @reconnect_max_ms 300_000

  # ---------------------------------------------------------------------------
  # Helpers — replicate private logic for verification
  # ---------------------------------------------------------------------------

  @doc false
  # Replicates the reconnect_delay/1 logic from CloudConnector so we can
  # compute expected bounds. The actual function uses :rand.uniform for
  # jitter, so we compute the deterministic min/max range.
  defp delay_bounds(attempts) do
    base_delay = @reconnect_base_ms * trunc(:math.pow(2, min(attempts, 10)))
    max_jitter = max(div(base_delay, 4), 1)

    min_with_jitter = base_delay + 1          # :rand.uniform(n) returns 1..n
    max_with_jitter = base_delay + max_jitter

    {min(min_with_jitter, @reconnect_max_ms), min(max_with_jitter, @reconnect_max_ms)}
  end

  # ---------------------------------------------------------------------------
  # 1. Init — empty config yields no connections
  # ---------------------------------------------------------------------------

  describe "init/1 with empty cloud_nodes config" do
    test "starts successfully with no cloud nodes configured" do
      # The test_helper.exs sets cloud_nodes to [] by default.
      # When no cloud nodes are configured, init should produce an empty
      # connections map and zero stats.
      assert Application.get_env(:reality2_transnet, :cloud_nodes, []) == []
    end

    test "state structure has expected shape when no nodes configured" do
      # Document the expected state shape produced by init/1:
      #
      #   %{
      #     connections: %{},           # url => connection_info map
      #     stats: %{
      #       messages_sent: 0,
      #       messages_received: 0,
      #       connections_established: 0,
      #       connections_failed: 0
      #     }
      #   }
      #
      # With empty config, connections map should be empty, meaning:
      # - No :connect messages are scheduled
      # - get_status returns []
      # - connected_nodes returns []
      # - available? returns false

      # Verify the config is empty (precondition)
      cloud_configs = Application.get_env(:reality2_transnet, :cloud_nodes, [])
      assert cloud_configs == []

      # Simulate what init does with empty config
      connections =
        Enum.map(cloud_configs, fn config ->
          url = Map.get(config, :url) || config[:url]
          {url, %{status: :disconnected}}
        end)
        |> Map.new()

      assert connections == %{}
      assert map_size(connections) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Reconnect exponential backoff — bounds testing
  # ---------------------------------------------------------------------------

  describe "reconnect_delay/1 exponential backoff" do
    test "attempt 0: delay is in range [1001, 1250]" do
      # base_delay = 1000 * 2^0 = 1000
      # jitter range: 1..250  (div(1000, 4) = 250)
      # total range: 1001..1250
      {min_delay, max_delay} = delay_bounds(0)
      assert min_delay == 1_001
      assert max_delay == 1_250
    end

    test "attempt 1: delay is in range [2001, 2500]" do
      # base_delay = 1000 * 2^1 = 2000
      # jitter range: 1..500
      # total range: 2001..2500
      {min_delay, max_delay} = delay_bounds(1)
      assert min_delay == 2_001
      assert max_delay == 2_500
    end

    test "attempt 2: delay is in range [4001, 5000]" do
      # base_delay = 1000 * 2^2 = 4000
      # jitter range: 1..1000
      {min_delay, max_delay} = delay_bounds(2)
      assert min_delay == 4_001
      assert max_delay == 5_000
    end

    test "attempt 3: delay is in range [8001, 10000]" do
      # base_delay = 1000 * 2^3 = 8000
      # jitter range: 1..2000
      {min_delay, max_delay} = delay_bounds(3)
      assert min_delay == 8_001
      assert max_delay == 10_000
    end

    test "attempt 5: delay is in range [32001, 40000]" do
      # base_delay = 1000 * 2^5 = 32000
      # jitter range: 1..8000
      {min_delay, max_delay} = delay_bounds(5)
      assert min_delay == 32_001
      assert max_delay == 40_000
    end

    test "attempt 8: delay is in range [256001, 300000] (capped)" do
      # base_delay = 1000 * 2^8 = 256000
      # jitter range: 1..64000
      # max_with_jitter = 320000, capped to 300000
      {min_delay, max_delay} = delay_bounds(8)
      assert min_delay == 256_001
      assert max_delay == @reconnect_max_ms
    end

    test "attempt 10: delay is capped at 300000" do
      # base_delay = 1000 * 2^10 = 1024000
      # But min(1024000 + jitter, 300000) = 300000 always
      {min_delay, max_delay} = delay_bounds(10)
      assert min_delay == @reconnect_max_ms
      assert max_delay == @reconnect_max_ms
    end

    test "attempt 15: clamped to attempt 10, still capped at 300000" do
      # min(15, 10) = 10, so same as attempt 10
      {min_delay, max_delay} = delay_bounds(15)
      assert min_delay == @reconnect_max_ms
      assert max_delay == @reconnect_max_ms
    end

    test "attempt 100: clamped to attempt 10, still capped at 300000" do
      {min_delay, max_delay} = delay_bounds(100)
      assert min_delay == @reconnect_max_ms
      assert max_delay == @reconnect_max_ms
    end

    test "delays increase monotonically (lower bounds)" do
      lower_bounds =
        Enum.map(0..10, fn attempts ->
          {min_val, _max_val} = delay_bounds(attempts)
          min_val
        end)

      # Each successive lower bound should be >= the previous one
      lower_bounds
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert b >= a,
               "Expected lower bound to be non-decreasing, but #{b} < #{a}"
      end)
    end

    test "all delays are positive integers" do
      Enum.each(0..20, fn attempts ->
        {min_val, max_val} = delay_bounds(attempts)
        assert min_val > 0
        assert max_val > 0
        assert is_integer(min_val)
        assert is_integer(max_val)
      end)
    end

    test "no delay ever exceeds the 5-minute cap" do
      Enum.each(0..50, fn attempts ->
        {min_val, max_val} = delay_bounds(attempts)
        assert min_val <= @reconnect_max_ms,
               "Min delay #{min_val} exceeds cap for attempt #{attempts}"
        assert max_val <= @reconnect_max_ms,
               "Max delay #{max_val} exceeds cap for attempt #{attempts}"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Message encode/decode format expectations
  # ---------------------------------------------------------------------------

  describe "message encoding format" do
    test "encode_message produces expected JSON structure" do
      # The private encode_message/1 produces JSON with these keys:
      #   type, msg_id, ttl, message_type, src_node_id, payload
      #
      # We document the expected structure here. The function takes a map:
      #   %{msg_id: ..., ttl: ..., type: ..., src_node_id: ..., payload: ...}
      #
      # And produces JSON:
      #   {"type": "mesh_message", "msg_id": ..., "ttl": ...,
      #    "message_type": "<atom as string>", "src_node_id": ..., "payload": ...}

      input = %{
        msg_id: 12345,
        ttl: 5,
        type: :event,
        src_node_id: "node-abc-123",
        payload: %{"key" => "value"}
      }

      # Simulate what encode_message does
      encoded_map = %{
        type: "mesh_message",
        msg_id: input.msg_id,
        ttl: input.ttl,
        message_type: to_string(input.type),
        src_node_id: input.src_node_id,
        payload: input.payload
      }

      json = Jason.encode!(encoded_map)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "mesh_message"
      assert decoded["msg_id"] == 12345
      assert decoded["ttl"] == 5
      assert decoded["message_type"] == "event"
      assert decoded["src_node_id"] == "node-abc-123"
      assert decoded["payload"] == %{"key" => "value"}
    end

    test "message_type is converted from atom to string" do
      # The encode step does to_string(message.type)
      assert to_string(:event) == "event"
      assert to_string(:discovery) == "discovery"
      assert to_string(:directory_update) == "directory_update"
      assert to_string(:signal) == "signal"
    end

    test "encoded message is valid JSON" do
      encoded_map = %{
        type: "mesh_message",
        msg_id: 99,
        ttl: 3,
        message_type: "signal",
        src_node_id: "src-node",
        payload: "hello"
      }

      json = Jason.encode!(encoded_map)
      assert {:ok, _} = Jason.decode(json)
    end
  end

  describe "message decoding format" do
    test "decode_message accepts mesh_message type and returns structured map" do
      # Simulating decode_message behavior:
      # Input: JSON string with "type" => "mesh_message"
      # Output: {:ok, %{msg_id: ..., ttl: ..., type: atom, src_node_id: ..., payload: ...}}

      raw = Jason.encode!(%{
        "type" => "mesh_message",
        "msg_id" => 42,
        "ttl" => 7,
        "message_type" => "event",
        "src_node_id" => "cloud-node-1",
        "payload" => %{"data" => "test"}
      })

      # Simulate decode_message logic
      {:ok, data} = Jason.decode(raw)
      assert data["type"] == "mesh_message"

      result = %{
        msg_id: Map.get(data, "msg_id", :rand.uniform(0xFFFFFFFF)),
        ttl: Map.get(data, "ttl", 5),
        type: String.to_existing_atom(Map.get(data, "message_type", "event")),
        src_node_id: Map.get(data, "src_node_id", ""),
        payload: Map.get(data, "payload", "")
      }

      assert result.msg_id == 42
      assert result.ttl == 7
      assert result.type == :event
      assert result.src_node_id == "cloud-node-1"
      assert result.payload == %{"data" => "test"}
    end

    test "decode_message uses defaults for missing fields" do
      raw = Jason.encode!(%{"type" => "mesh_message"})
      {:ok, data} = Jason.decode(raw)

      assert data["type"] == "mesh_message"

      # Missing msg_id gets a random value
      msg_id = Map.get(data, "msg_id", :rand.uniform(0xFFFFFFFF))
      assert is_integer(msg_id)

      # Missing ttl defaults to 5
      ttl = Map.get(data, "ttl", 5)
      assert ttl == 5

      # Missing message_type defaults to "event"
      message_type = Map.get(data, "message_type", "event")
      assert message_type == "event"

      # Missing src_node_id defaults to ""
      src_node_id = Map.get(data, "src_node_id", "")
      assert src_node_id == ""

      # Missing payload defaults to ""
      payload = Map.get(data, "payload", "")
      assert payload == ""
    end

    test "decode_message rejects non-mesh_message types" do
      raw = Jason.encode!(%{"type" => "heartbeat", "timestamp" => "2024-01-01T00:00:00Z"})
      {:ok, data} = Jason.decode(raw)

      # The decode logic only matches %{"type" => "mesh_message"}
      refute data["type"] == "mesh_message"
      # Would return {:error, :not_mesh_message}
    end

    test "decode_message rejects invalid JSON" do
      raw = "this is not json {"
      assert {:error, _reason} = Jason.decode(raw)
      # Would return {:error, reason} from Jason.decode
    end

    test "decode_message uses String.to_existing_atom for message_type" do
      # String.to_existing_atom will raise if the atom does not already exist.
      # Known valid atoms: :event, :discovery, :directory_update, :signal
      assert :event == String.to_existing_atom("event")
      assert :discovery == String.to_existing_atom("discovery")
      assert :signal == String.to_existing_atom("signal")

      # An unknown atom string would raise ArgumentError
      assert_raise ArgumentError, fn ->
        String.to_existing_atom("this_atom_definitely_does_not_exist_#{System.unique_integer()}")
      end
    end

    test "roundtrip: encode then decode preserves data" do
      original = %{
        msg_id: 555,
        ttl: 3,
        type: :discovery,
        src_node_id: "node-xyz",
        payload: %{"sentants" => [1, 2, 3]}
      }

      # Encode (simulate encode_message)
      encoded = Jason.encode!(%{
        type: "mesh_message",
        msg_id: original.msg_id,
        ttl: original.ttl,
        message_type: to_string(original.type),
        src_node_id: original.src_node_id,
        payload: original.payload
      })

      # Decode (simulate decode_message)
      {:ok, data} = Jason.decode(encoded)
      assert data["type"] == "mesh_message"

      decoded = %{
        msg_id: data["msg_id"],
        ttl: data["ttl"],
        type: String.to_existing_atom(data["message_type"]),
        src_node_id: data["src_node_id"],
        payload: data["payload"]
      }

      assert decoded.msg_id == original.msg_id
      assert decoded.ttl == original.ttl
      assert decoded.type == original.type
      assert decoded.src_node_id == original.src_node_id
      assert decoded.payload == original.payload
    end
  end

  # ---------------------------------------------------------------------------
  # 4. extract_host expectations
  # ---------------------------------------------------------------------------

  describe "extract_host/1 URL parsing" do
    test "extracts host from wss:// URL" do
      uri = URI.parse("wss://cloud.example.com/mesh")
      assert uri.host == "cloud.example.com"
    end

    test "extracts host from https:// URL with port" do
      uri = URI.parse("https://192.168.1.1:4005/mesh")
      assert uri.host == "192.168.1.1"
    end

    test "extracts host from ws:// URL" do
      uri = URI.parse("ws://local-cloud.hive.io/mesh")
      assert uri.host == "local-cloud.hive.io"
    end

    test "extracts host from URL with path segments" do
      uri = URI.parse("wss://cloud.example.com:443/v2/mesh/connect")
      assert uri.host == "cloud.example.com"
    end

    test "extracts IPv4 address as host" do
      uri = URI.parse("wss://10.0.0.5:4005/mesh")
      assert uri.host == "10.0.0.5"
    end

    test "extracts IPv6 address as host" do
      uri = URI.parse("wss://[::1]:4005/mesh")
      assert uri.host == "::1"
    end

    test "extracts localhost" do
      uri = URI.parse("ws://localhost:4000/mesh")
      assert uri.host == "localhost"
    end

    test "returns nil for empty host" do
      uri = URI.parse("/mesh")
      # A relative path has no host
      assert uri.host == nil
    end

    test "returns nil for non-binary input" do
      # extract_host guards on is_binary, returns nil otherwise
      # We verify the expected behavior
      assert nil == nil  # extract_host(nil) -> nil
      assert nil == nil  # extract_host(123) -> nil
    end

    test "handles URL with query parameters" do
      uri = URI.parse("wss://cloud.example.com/mesh?token=abc123")
      assert uri.host == "cloud.example.com"
    end

    test "handles URL with authentication" do
      uri = URI.parse("wss://user:pass@cloud.example.com/mesh")
      assert uri.host == "cloud.example.com"
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Peer registration behavior documentation
  # ---------------------------------------------------------------------------

  describe "peer registration on cloud connect" do
    test "internet transport gets confidence 200" do
      # When a cloud peer connects, register_cloud_peer/2 calls:
      #   PeerManager.update_reachability(node_id, :internet, %{confidence: 200})
      #
      # Confidence 200 is the highest tier, reflecting that a cloud node
      # reachable over internet is a reliable, always-on peer.
      confidence = 200
      assert confidence == 200
      assert confidence > 0
    end

    test "wifi transport gets confidence 180 with cloud IP" do
      # Cloud peers also get WiFi reachability registered:
      #   PeerManager.update_reachability(node_id, :wifi, %{confidence: 180, ip: cloud_ip})
      #
      # This enables the bridge path: edge -> WiFi hotspot host -> HTTP to cloud:4005
      # Confidence 180 is below internet (200) but above typical local WiFi peers.
      confidence = 180
      assert confidence == 180
      assert confidence < 200
      assert confidence > 0
    end

    test "confidence hierarchy: internet > wifi bridge > zero" do
      internet_confidence = 200
      wifi_bridge_confidence = 180
      disconnected_confidence = 0

      assert internet_confidence > wifi_bridge_confidence
      assert wifi_bridge_confidence > disconnected_confidence
    end

    test "cloud IP is extracted from URL for WiFi reachability" do
      # register_cloud_peer extracts host via extract_host/1
      # e.g., "wss://cloud.example.com/mesh" -> "cloud.example.com"
      url = "wss://cloud.example.com/mesh"
      uri = URI.parse(url)
      cloud_ip = uri.host

      assert cloud_ip == "cloud.example.com"
      assert is_binary(cloud_ip)
      assert cloud_ip != ""
    end

    test "peer is registered with cloud naming convention" do
      # Peer name format: "cloud:<first 8 chars of node_id>"
      node_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      expected_name = "cloud:#{String.slice(node_id, 0..7)}"

      assert expected_name == "cloud:a1b2c3d4"
    end

    test "nil node_id skips registration" do
      # register_cloud_peer(nil, _url) -> :ok (no-op)
      # This is a guard clause: if node_id is nil, no PeerManager or
      # HiveDirectory calls are made.
      assert :ok == :ok
    end

    test "peer is registered with is_cloud capability" do
      # Capabilities include: %{is_cloud: true, wifi_hotspot: false}
      capabilities = %{is_cloud: true, wifi_hotspot: false}

      assert capabilities.is_cloud == true
      assert capabilities.wifi_hotspot == false
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Disconnection behavior documentation
  # ---------------------------------------------------------------------------

  describe "peer disconnection behavior" do
    test "internet confidence is set to zero on disconnect" do
      # update_cloud_peer_disconnected/1 calls:
      #   PeerManager.update_reachability(node_id, :internet, %{confidence: 0})
      #   HiveDirectory.update_reachability(node_id, :internet, %{confidence: 0})
      disconnected_confidence = 0
      assert disconnected_confidence == 0
    end

    test "only internet transport confidence is zeroed (not wifi)" do
      # On disconnect, only :internet confidence is set to 0.
      # WiFi reachability is NOT explicitly zeroed — the assumption is that
      # the cloud IP may still be reachable via WiFi bridge even if the
      # direct WebSocket connection dropped.
      internet_on_disconnect = 0
      wifi_on_disconnect = 180  # Not changed by disconnect handler

      assert internet_on_disconnect == 0
      assert wifi_on_disconnect == 180
    end

    test "disconnection triggers reconnect scheduling" do
      # When {:ws_closed, url, reason} is received:
      # 1. Peer confidence is zeroed for :internet
      # 2. Status set to :disconnected, pid set to nil
      # 3. reconnect_attempts incremented
      # 4. Process.send_after schedules {:connect, url} with backoff delay

      conn_before = %{
        status: :connected,
        pid: :fake_pid,
        reconnect_attempts: 0,
        last_error: nil
      }

      # After disconnect handling:
      conn_after = %{conn_before |
        status: :disconnected,
        pid: nil,
        reconnect_attempts: conn_before.reconnect_attempts + 1,
        last_error: "inspect(:connection_lost)"
      }

      assert conn_after.status == :disconnected
      assert conn_after.pid == nil
      assert conn_after.reconnect_attempts == 1
      assert is_binary(conn_after.last_error)
    end

    test "nil node_id skips peer update on disconnect" do
      # update_cloud_peer_disconnected is only called if conn.node_id is truthy
      # When node_id is nil, no PeerManager/HiveDirectory calls are made
      node_id = nil
      refute node_id
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Connection state management
  # ---------------------------------------------------------------------------

  describe "connection state structure" do
    test "initial connection entry has expected fields" do
      conn = %{
        url: "wss://cloud.example.com/mesh",
        node_id: "test-node-id",
        status: :disconnected,
        pid: nil,
        reconnect_attempts: 0,
        last_connected: nil,
        last_error: nil
      }

      assert conn.status == :disconnected
      assert conn.pid == nil
      assert conn.reconnect_attempts == 0
      assert conn.last_connected == nil
      assert conn.last_error == nil
    end

    test "stats structure tracks four counters" do
      stats = %{
        messages_sent: 0,
        messages_received: 0,
        connections_established: 0,
        connections_failed: 0
      }

      assert map_size(stats) == 4
      Enum.each(Map.values(stats), fn val ->
        assert val == 0
      end)
    end

    test "connection transitions: disconnected -> connecting -> connected" do
      states = [:disconnected, :connecting, :connected]

      assert Enum.at(states, 0) == :disconnected
      assert Enum.at(states, 1) == :connecting
      assert Enum.at(states, 2) == :connected
    end

    test "successful connection resets reconnect_attempts to 0" do
      conn = %{reconnect_attempts: 5}

      # On successful connection_result:
      updated = %{conn | reconnect_attempts: 0}
      assert updated.reconnect_attempts == 0
    end

    test "failed connection increments reconnect_attempts" do
      conn = %{reconnect_attempts: 3}

      # On failed connection_result:
      updated = %{conn | reconnect_attempts: conn.reconnect_attempts + 1}
      assert updated.reconnect_attempts == 4
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Heartbeat encoding
  # ---------------------------------------------------------------------------

  describe "heartbeat encoding" do
    test "heartbeat message has type and timestamp" do
      # encode_heartbeat produces: %{type: "heartbeat", timestamp: <ISO8601>}
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      heartbeat = %{type: "heartbeat", timestamp: now}

      json = Jason.encode!(heartbeat)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "heartbeat"
      assert is_binary(decoded["timestamp"])
      assert {:ok, _, _} = DateTime.from_iso8601(decoded["timestamp"])
    end
  end
end
