defmodule AiReality2Pns.Test do
  @moduledoc """
  Test helpers for the Pathing Name System (PNS) router.

  ## Usage

      # Show routing table
      AiReality2Pns.Test.show_routing_table()

      # Test sending to local Sentant
      AiReality2Pns.Test.test_local_send()

      # Test sending to remote Sentant
      AiReality2Pns.Test.test_remote_send(peer_node_id, sentant_id)

      # Test broadcast
      AiReality2Pns.Test.test_broadcast("*")

      # Full integration test
      AiReality2Pns.Test.test_integration()
  """

  require Logger
  alias AiReality2Pns.Router

  @doc """
  Display the current routing table.
  """
  def show_routing_table do
    case Router.get_routing_table() do
      table ->
        Logger.info("""

        ===========================================
        PNS Routing Table
        ===========================================
        Local Sentants: #{table.local_sentant_count}
        Remote Sentants: #{table.remote_sentant_count}

        Statistics:
        - Local sends: #{table.stats.local_sends}
        - Remote sends: #{table.stats.remote_sends}
        - Broadcasts: #{table.stats.broadcasts}

        Sentant Locations:
        """)

        # Show first 10 sentant locations
        table.sentant_locations
        |> Enum.take(10)
        |> Enum.each(fn {sentant_id, location} ->
          loc_str = case location do
            :local -> "LOCAL"
            {:remote, node_id} -> "REMOTE (#{String.slice(node_id, 0..7)}...)"
          end
          Logger.info("  #{String.slice(sentant_id, 0..7)}... => #{loc_str}")
        end)

        if map_size(table.sentant_locations) > 10 do
          Logger.info("  ... and #{map_size(table.sentant_locations) - 10} more")
        end

        Logger.info("""

        Peer Sentants by Node:
        """)

        table.peer_sentants
        |> Enum.each(fn {node_id, sentant_ids} ->
          Logger.info("  Node #{String.slice(node_id, 0..7)}...: #{length(sentant_ids)} sentants")
        end)

        Logger.info("===========================================\n")
        {:ok, table}
    end
  end

  @doc """
  Test sending to a local Sentant.
  Creates a test Sentant if needed.
  """
  def test_local_send do
    Logger.info("=== Testing Local Send ===\n")

    # Create a test Sentant
    sentant_yaml = """
    name: pns_test_local
    events:
      - name: ping
    automations:
      - name: respond_to_ping
        on: ping
        do:
          - signal:
              event: pong
              parameters:
                message: "Local pong!"
    """

    Logger.info("Creating test Sentant 'pns_test_local'...")
    {:ok, sentant_id} = Reality2.Sentants.create(sentant_yaml)
    Logger.info("✓ Created: #{sentant_id}\n")

    # Wait a moment for it to register
    Process.sleep(500)

    # Locate the Sentant
    Logger.info("Locating Sentant...")
    case Router.locate(sentant_id) do
      {:ok, :local} ->
        Logger.info("✓ Found locally\n")

      other ->
        Logger.warning("✗ Unexpected location: #{inspect(other)}\n")
    end

    # Send via PNS
    Logger.info("Sending 'ping' event via PNS...")
    case Router.send_to_sentant(sentant_id, "ping", %{test: "local"}) do
      {:ok, :local, _result} ->
        Logger.info("✓ Successfully sent to local Sentant\n")

      {:error, reason} ->
        Logger.error("✗ Failed: #{inspect(reason)}\n")
    end

    # Check routing table
    show_routing_table()

    {:ok, sentant_id}
  end

  @doc """
  Test sending to a remote Sentant on a peer node.

  ## Parameters
  - `peer_node_id` - UUID of the peer node
  - `sentant_id` - UUID of a Sentant on that peer
  """
  def test_remote_send(peer_node_id, sentant_id) do
    Logger.info("=== Testing Remote Send ===\n")

    Logger.info("Peer Node: #{peer_node_id}")
    Logger.info("Sentant: #{sentant_id}\n")

    # Locate the Sentant
    Logger.info("Locating Sentant...")
    case Router.locate(sentant_id) do
      {:ok, {:remote, node_id}} ->
        Logger.info("✓ Found on remote node: #{String.slice(node_id, 0..7)}...\n")

      {:ok, :local} ->
        Logger.warning("⚠ Sentant is local, not remote!\n")

      {:error, :not_found} ->
        Logger.warning("✗ Sentant not found. Refreshing topology...\n")
        Router.refresh_topology()
        Process.sleep(1000)
    end

    # Get peer info to find an event
    Logger.info("Getting peer Sentant info...")
    case AiReality2Transnet.Bluetooth.get_peer(peer_node_id) do
      {:ok, peer_info} ->
        peer_sentant = Enum.find(peer_info.sentants, fn s ->
          Map.get(s, "id") == sentant_id
        end)

        case peer_sentant do
          nil ->
            Logger.error("✗ Sentant not found on peer\n")
            {:error, :sentant_not_found}

          sentant ->
            events = Map.get(sentant, "events", [])
            case Enum.at(events, 0) do
              nil ->
                Logger.error("✗ No events available\n")
                {:error, :no_events}

              event ->
                event_name = Map.get(event, "name")
                Logger.info("Found event: '#{event_name}'\n")

                # Send via PNS
                Logger.info("Sending '#{event_name}' event via PNS...")
                case Router.send_to_sentant(sentant_id, event_name, %{test: "remote"}) do
                  {:ok, {:remote, node_id}, _result} ->
                    Logger.info("✓ Successfully sent to remote Sentant on node #{String.slice(node_id, 0..7)}...\n")
                    {:ok, :sent}

                  {:error, reason} ->
                    Logger.error("✗ Failed: #{inspect(reason)}\n")
                    {:error, reason}
                end
            end
        end

      {:error, :not_found} ->
        Logger.error("✗ Peer node not connected\n")
        {:error, :peer_not_connected}
    end
  end

  @doc """
  Test broadcasting to all Sentants (local and remote).

  ## Parameters
  - `pattern` - "*" for all, "name*" for wildcard, or list of IDs
  """
  def test_broadcast(pattern \\ "*") do
    Logger.info("=== Testing Broadcast ===\n")
    Logger.info("Pattern: #{inspect(pattern)}\n")

    # Note: Broadcasting to all Sentants with a generic event may not work
    # if not all Sentants have that event defined.
    # This is more of a routing test than a functional test.

    Logger.info("Broadcasting 'test_event' to pattern '#{pattern}'...")
    case Router.broadcast(pattern, "test_event", %{broadcast: true}) do
      {:ok, %{local: local_count, remote: remote_count}} ->
        Logger.info("""
        ✓ Broadcast complete:
          - Local: #{local_count} Sentants
          - Remote: #{remote_count} Sentants
        """)
        {:ok, %{local: local_count, remote: remote_count}}

      {:error, reason} ->
        Logger.error("✗ Broadcast failed: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Full integration test: local send, remote send, and broadcast.
  Requires at least one connected peer with sentants.
  """
  def test_integration do
    Logger.info("""

    ============================================
    PNS Integration Test Suite
    ============================================
    """)

    # Step 1: Show initial state
    Logger.info("\n1. Current Routing Table:")
    show_routing_table()

    # Step 2: Test local send
    Logger.info("\n2. Testing Local Send:")
    {:ok, _local_sentant_id} = test_local_send()

    # Step 3: Refresh topology
    Logger.info("\n3. Refreshing Topology:")
    Router.refresh_topology()
    Process.sleep(1000)
    show_routing_table()

    # Step 4: Test remote send if peers available
    Logger.info("\n4. Testing Remote Send:")
    peers = AiReality2Transnet.Bluetooth.get_connected_peers()

    if map_size(peers) > 0 do
      {peer_id, peer_info} = Enum.at(Map.to_list(peers), 0)

      case Enum.at(peer_info.sentants, 0) do
        nil ->
          Logger.warning("⚠ Peer has no Sentants, skipping remote test\n")

        sentant ->
          remote_sentant_id = Map.get(sentant, "id")
          test_remote_send(peer_id, remote_sentant_id)
      end
    else
      Logger.warning("⚠ No peers connected, skipping remote test\n")
    end

    # Step 5: Test broadcast
    Logger.info("\n5. Testing Broadcast:")
    test_broadcast("pns_test*")

    # Step 6: Final statistics
    Logger.info("\n6. Final Statistics:")
    show_routing_table()

    Logger.info("""
    ============================================
    Integration Test Complete
    ============================================
    """)

    {:ok, :complete}
  end

  @doc """
  Helper to list all local Sentants.
  """
  def list_local_sentants do
    sentants = Reality2.Metadata.all(:SentantIDs)
    |> Map.to_list()

    Logger.info("""

    Local Sentants (#{length(sentants)}):
    ==================
    """)

    Enum.each(sentants, fn {name, id} ->
      Logger.info("  #{name} => #{String.slice(id, 0..7)}...")
    end)

    Logger.info("==================\n")
    {:ok, sentants}
  end

  @doc """
  Helper to list all remote Sentants from connected peers.
  """
  def list_remote_sentants do
    peers = AiReality2Transnet.Bluetooth.get_connected_peers()

    Logger.info("""

    Remote Sentants from #{map_size(peers)} peers:
    ==========================================
    """)

    Enum.each(peers, fn {node_id, peer_info} ->
      Logger.info("\nPeer: #{String.slice(node_id, 0..7)}...")
      Logger.info("Sentants: #{peer_info.sentant_count}")

      Enum.each(peer_info.sentants, fn sentant ->
        name = Map.get(sentant, "name", "unnamed")
        id = Map.get(sentant, "id", "no-id")
        Logger.info("  - #{name} (#{String.slice(id, 0..7)}...)")
      end)
    end)

    Logger.info("==========================================\n")
    {:ok, peers}
  end

  @doc """
  Quick test: Create 2 local Sentants and send between them.
  """
  def quick_test do
    Logger.info("=== PNS Quick Test ===\n")

    # Create sender
    sender_yaml = """
    name: pns_sender
    events:
      - name: start
    automations:
      - name: send_to_receiver
        on: start
        do:
          - send:
              to: pns_receiver
              event: hello
              parameters:
                message: "Hello from sender!"
    """

    # Create receiver
    receiver_yaml = """
    name: pns_receiver
    events:
      - name: hello
    automations:
      - name: respond
        on: hello
        do:
          - signal:
              event: received
              parameters:
                message: "Got it!"
    """

    Logger.info("Creating receiver...")
    Reality2.Sentants.create(receiver_yaml)

    Logger.info("Creating sender...")
    {:ok, sender_id} = Reality2.Sentants.create(sender_yaml)

    Process.sleep(500)

    Logger.info("Triggering send via PNS...")
    Router.send_to_sentant(sender_id, "start", %{})

    Logger.info("\n✓ Test complete! Check logs for routing.\n")
    show_routing_table()
  end
end
