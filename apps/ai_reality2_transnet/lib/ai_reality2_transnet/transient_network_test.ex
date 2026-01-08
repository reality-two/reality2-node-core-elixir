defmodule AiReality2Transnet.TransientNetworkTest do
  @moduledoc """
  Integration tests and demonstration scenarios for Reality2 Transient Networking.

  This module provides test functions to demonstrate the complete flow:
  1. BLE beacon discovery
  2. GATT connection and Sentant exchange
  3. PNS routing to remote Sentants
  4. WiFi mesh upgrade (when criteria met)

  **Usage:**

      # In IEx:
      alias AiReality2Transnet.TransientNetworkTest, as: TNT

      # Show system status
      TNT.status()

      # Simulate peer discovery
      TNT.simulate_peer_discovery()

      # Test GATT protocol
      TNT.test_gatt_protocol()

      # Test PNS routing
      TNT.test_pns_routing()

      # Full integration test
      TNT.run_integration_test()

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  require Logger
  alias AiReality2Transnet.{PeerManager, TransportManager, GattProtocol, Wifi}

  # Suppress warnings for optional PNS integration (runtime checks used)
  # PNS is a higher-level module that depends on transnet, not vice versa
  # We use Code.ensure_loaded?/1 to avoid circular dependency
  @compile {:no_warn_undefined, [AiReality2Pns.Router, AiReality2Pns]}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # System Status and Info
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Shows the current status of all Transient Network components.
  """
  def status do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("Reality2 Transient Network - System Status")
    IO.puts(String.duplicate("=", 70) <> "\n")

    # PeerManager status
    IO.puts("📡 PeerManager:")
    peers = PeerManager.get_all_peers()
    stats = PeerManager.get_stats()
    IO.puts("   Tracked peers: #{map_size(peers)}")
    IO.puts("   Total discovered: #{stats.total_discovered}")
    IO.puts("   Total removed: #{stats.total_removed}")
    IO.puts("   BLE peers: #{stats.ble_peers}")
    IO.puts("   WiFi peers: #{stats.wifi_peers}")

    # TransportManager status
    IO.puts("\n🚀 TransportManager:")
    transport_stats = TransportManager.get_stats()
    IO.puts("   Upgrade checks: #{transport_stats.upgrade_checks}")
    IO.puts("   Upgrades succeeded: #{transport_stats.upgrades_succeeded}")
    IO.puts("   Upgrades failed: #{transport_stats.upgrades_failed}")
    IO.puts("   Mesh active: #{transport_stats.mesh_active}")

    # PNS Router status
    IO.puts("\n🔀 PNS Router:")
    if Code.ensure_loaded?(AiReality2Pns.Router) do
      pns_table = AiReality2Pns.Router.get_routing_table()
      IO.puts("   Local Sentants: #{pns_table.local_sentant_count}")
      IO.puts("   Remote Sentants: #{pns_table.remote_sentant_count}")
      IO.puts("   Local sends: #{pns_table.stats.local_sends}")
      IO.puts("   Remote sends: #{pns_table.stats.remote_sends}")
    else
      IO.puts("   Status: Not available")
    end

    # WiFi adapters
    IO.puts("\n📶 WiFi Adapters:")
    case Wifi.list_adapters() do
      {:ok, adapters} ->
        Enum.each(adapters, fn adapter ->
          IO.puts("   - #{adapter.interface} (#{adapter.address})")
        end)
      {:error, reason} ->
        IO.puts("   Error: #{reason}")
    end

    IO.puts("\n" <> String.duplicate("=", 70) <> "\n")
    :ok
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Simulated Tests
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Simulates discovering a peer device via BLE beacon.

  Creates a fake peer and adds it to PeerManager to demonstrate the flow.
  """
  def simulate_peer_discovery do
    IO.puts("\n=== Simulating Peer Discovery ===\n")

    # Generate a fake peer
    peer_id = UUID.uuid4()
    peer_info = %{
      address: "AA:BB:CC:DD:EE:FF",
      rssi: -55,
      name: "TestDevice"
    }

    IO.puts("Discovering peer: #{String.slice(peer_id, 0..15)}...")
    PeerManager.register_peer(peer_id, peer_info)

    Process.sleep(100)

    # Simulate receiving Sentant directory
    fake_sentants = [
      %{
        id: UUID.uuid4(),
        name: "remote_sensor",
        events: ["read_temperature", "calibrate"],
        type: "sensor"
      },
      %{
        id: UUID.uuid4(),
        name: "remote_display",
        events: ["show_message", "clear"],
        type: "display"
      }
    ]

    IO.puts("Exchanging Sentant directory (#{length(fake_sentants)} Sentants)...")
    PeerManager.update_peer_sentants(peer_id, fake_sentants)

    # Simulate capabilities
    capabilities = %{
      wifi_mesh: true,
      bluetooth: true,
      sentants: length(fake_sentants)
    }

    PeerManager.update_peer_capabilities(peer_id, capabilities)

    Process.sleep(100)

    IO.puts("✓ Peer registered successfully")
    IO.puts("\nPeer details:")
    case PeerManager.get_peer(peer_id) do
      {:ok, peer} ->
        IO.puts("  Node ID: #{peer.node_id}")
        IO.puts("  Transport: #{peer.transport}")
        IO.puts("  Sentants: #{length(peer.sentants)}")
        IO.puts("  Capabilities: #{inspect(peer.capabilities)}")

      {:error, reason} ->
        IO.puts("  Error: #{reason}")
    end

    IO.puts("\n=== Peer Discovery Complete ===\n")
    {:ok, peer_id}
  end

  @doc """
  Tests the GATT protocol encoding and decoding.
  """
  def test_gatt_protocol do
    IO.puts("\n=== Testing GATT Protocol (Minimal - Discovery Only) ===\n")

    node_id = UUID.uuid4()

    # Test 1: Encode/decode minimal node info
    IO.puts("Test 1: Node Info Encoding (Minimal)")
    node_info_json = GattProtocol.encode_node_info(node_id)
    IO.puts("  Encoded: #{byte_size(node_info_json)} bytes")

    case GattProtocol.decode_node_info(node_info_json) do
      {:ok, decoded} ->
        IO.puts("  ✓ Decoded successfully")
        IO.puts("    Node ID: #{decoded.node_id}")
        IO.puts("    Version: #{decoded.version}")
        IO.puts("    Sentant count: #{get_in(decoded, [:capabilities, :sentant_count])}")
        IO.puts("    Message: #{decoded.message}")

      {:error, reason} ->
        IO.puts("  ✗ Decode failed: #{reason}")
    end

    # Test 2: Encode/decode WiFi mesh details
    IO.puts("\nTest 2: WiFi Mesh Details Encoding")
    mesh_details_json = GattProtocol.encode_mesh_details()
    IO.puts("  Encoded: #{byte_size(mesh_details_json)} bytes")

    case GattProtocol.decode_mesh_details(mesh_details_json) do
      {:ok, decoded} ->
        IO.puts("  ✓ Decoded successfully")
        IO.puts("    Mesh active: #{decoded.mesh_active}")
        IO.puts("    Mesh ID: #{decoded.mesh_id}")
        IO.puts("    IPv6: #{decoded.ipv6_link_local}")
        IO.puts("    HTTP port: #{decoded.http_port}")
        IO.puts("    Instructions: #{decoded.instructions}")

      {:error, reason} ->
        IO.puts("  ✗ Decode failed: #{reason}")
    end

    # Test 3: Encode/decode mesh command
    IO.puts("\nTest 3: Mesh Command Encoding")
    command_json = GattProtocol.encode_mesh_command(
      :join_mesh,
      %{mesh_id: "R2MESH_test"}
    )
    IO.puts("  Encoded: #{byte_size(command_json)} bytes")

    case GattProtocol.decode_mesh_command(command_json) do
      {:ok, decoded} ->
        IO.puts("  ✓ Decoded successfully")
        IO.puts("    Command: #{decoded.command}")
        IO.puts("    Parameters: #{inspect(decoded.parameters)}")

      {:error, reason} ->
        IO.puts("  ✗ Decode failed: #{reason}")
    end

    IO.puts("\n=== GATT Protocol Tests Complete ===\n")
    IO.puts("NOTE: For Sentant queries, use WiFi mesh HTTP: GET http://[ipv6]:8080/sentants")
    :ok
  end

  @doc """
  Tests PNS routing to a simulated remote Sentant.
  """
  def test_pns_routing do
    IO.puts("\n=== Testing PNS Routing ===\n")

    # First, simulate a peer
    IO.puts("Setting up simulated peer...")
    {:ok, peer_id} = simulate_peer_discovery()

    Process.sleep(500)

    # Get peer Sentants
    case PeerManager.get_peer(peer_id) do
      {:ok, peer} ->
        case peer.sentants do
          [] ->
            IO.puts("No Sentants available on peer for testing")

          [sentant | _] ->
            sentant_id = Map.get(sentant, :id) || Map.get(sentant, "id")
            IO.puts("Attempting to send event to remote Sentant...")
            IO.puts("  Target: #{Map.get(sentant, :name) || Map.get(sentant, "name")}")
            IO.puts("  Sentant ID: #{sentant_id}")

            # Try to send via PNS
            if Code.ensure_loaded?(AiReality2Pns) do
              result = AiReality2Pns.send_to(sentant_id, "test_event", %{test: true})
              IO.puts("  Result: #{inspect(result)}")
            else
              IO.puts("  PNS not available")
            end
        end

      {:error, reason} ->
        IO.puts("Failed to get peer: #{reason}")
    end

    IO.puts("\n=== PNS Routing Test Complete ===\n")
    :ok
  end

  @doc """
  Tests WiFi mesh upgrade decision logic.
  """
  def test_wifi_upgrade do
    IO.puts("\n=== Testing WiFi Mesh Upgrade ===\n")

    # Simulate a peer
    {:ok, peer_id} = simulate_peer_discovery()
    Process.sleep(500)

    # Check if upgrade is recommended
    IO.puts("Checking upgrade decision...")
    case TransportManager.should_upgrade_to_wifi?(peer_id) do
      {:yes, reason} ->
        IO.puts("  ✓ Upgrade recommended: #{reason}")

        IO.puts("\nInitiating WiFi upgrade...")
        case TransportManager.initiate_wifi_upgrade(peer_id) do
          :ok ->
            IO.puts("  ✓ WiFi upgrade successful")
            Process.sleep(500)

            case PeerManager.get_peer(peer_id) do
              {:ok, peer} ->
                IO.puts("  New transport: #{peer.transport}")

              _ ->
                :ok
            end

          {:error, reason} ->
            IO.puts("  ✗ WiFi upgrade failed: #{reason}")
        end

      {:no, reason} ->
        IO.puts("  ✗ Upgrade not recommended: #{reason}")
    end

    IO.puts("\n=== WiFi Mesh Upgrade Test Complete ===\n")
    :ok
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Full Integration Test
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Runs a complete integration test of the Transient Network system.

  This simulates the full flow:
  1. Peer discovery via BLE
  2. Sentant directory exchange
  3. PNS routing to remote Sentants
  4. WiFi mesh upgrade evaluation
  """
  def run_integration_test do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("Reality2 Transient Network - Integration Test")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("Step 1: System Status")
    IO.puts(String.duplicate("-", 70))
    status()

    IO.puts("\nStep 2: Peer Discovery")
    IO.puts(String.duplicate("-", 70))
    {:ok, peer_id} = simulate_peer_discovery()

    IO.puts("\nStep 3: GATT Protocol Testing")
    IO.puts(String.duplicate("-", 70))
    test_gatt_protocol()

    IO.puts("\nStep 4: PNS Routing")
    IO.puts(String.duplicate("-", 70))
    test_pns_routing()

    IO.puts("\nStep 5: WiFi Mesh Upgrade")
    IO.puts(String.duplicate("-", 70))
    test_wifi_upgrade()

    IO.puts("\nStep 6: Final Status")
    IO.puts(String.duplicate("-", 70))
    status()

    IO.puts(String.duplicate("=", 70))
    IO.puts("Integration Test Complete!")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("""

    Next Steps:
    -----------
    1. Test on real hardware with actual BLE beacons
    2. Deploy to multiple Arduino Uno-Q devices
    3. Monitor peer discovery and Sentant exchange
    4. Test WiFi mesh upgrade with real network conditions
    5. Benchmark throughput and latency

    For manual testing:
    - AiReality2Transnet.TransientNetworkTest.status()
    - AiReality2Transnet.PeerManager.get_all_peers()
    - AiReality2Pns.Router.get_routing_table()
    """)

    {:ok, peer_id}
  end
end
