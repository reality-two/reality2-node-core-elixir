defmodule AiReality2Transnet.BluetoothTest do
  @moduledoc """
  Test module for verifying GATT server functionality.

  ## Usage

      # Start the test
      AiReality2Transnet.BluetoothTest.start()

      # Check server state
      AiReality2Transnet.BluetoothTest.check_state()

      # Test broadcasting a signal
      AiReality2Transnet.BluetoothTest.test_broadcast()

      # Simulate a mutation from a client
      AiReality2Transnet.BluetoothTest.test_mutation()

      # Run full test suite
      AiReality2Transnet.BluetoothTest.run_all_tests()
  """

  require Logger

  @doc """
  Starts monitoring the Bluetooth module.
  """
  def start do
    case Process.whereis(AiReality2Transnet.Bluetooth) do
      nil ->
        {:error, "Bluetooth module not running"}

      pid ->
        Logger.info("Bluetooth module running at: #{inspect(pid)}")
        {:ok, pid}
    end
  end

  @doc """
  Checks the current state of the Bluetooth/GATT server.
  """
  def check_state do
    case AiReality2Transnet.Bluetooth.get_state() do
      state when is_map(state) ->
        Logger.info("""
        Bluetooth Server State:
        ----------------------
        Adapter: #{inspect(state[:adapter_name])}
        GATT Handle: #{inspect(state[:gatt_handle])}
        Beacon Handle: #{inspect(state[:r2_beacon])}
        Watch Handle: #{inspect(state[:r2_watch])}

        Statistics:
        - Events Sent: #{state[:events_sent] || 0}
        - Signals Broadcast: #{state[:signals_broadcast] || 0}
        - Queries Processed: #{state[:queries_processed] || 0}
        """)

        {:ok, state}

      error ->
        Logger.error("Failed to get state: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Tests broadcasting a signal to connected GATT clients.
  """
  def test_broadcast do
    Logger.info("Testing signal broadcast...")

    AiReality2Transnet.Bluetooth.broadcast_signal(
      "test_sentant_123",
      "test_signal",
      "test_event",
      %{data: "test_data", timestamp: DateTime.utc_now()},
      %{test: true}
    )

    Logger.info("Broadcast sent. Check nRF Connect or bluetoothctl for notifications.")
    :ok
  end

  @doc """
  Simulates a GATT mutation write from a client.
  """
  def test_mutation do
    Logger.info("Testing mutation handling...")

    # Simulate what a client would send
    mutation = %{
      "id" => "test_sentant_456",
      "event" => "test_command",
      "parameters" => %{"action" => "test", "value" => 42},
      "passthrough" => %{"client_id" => "test_client"}
    }

    case Jason.encode(mutation) do
      {:ok, json} ->
        # Send directly to the Bluetooth process as if from GATT
        data = :binary.bin_to_list(json)
        send(Process.whereis(AiReality2Transnet.Bluetooth), {:gatt_write, "data", data})
        Logger.info("Mutation test sent: #{json}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to encode test mutation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Tests the query characteristic by triggering a refresh.
  """
  def test_query do
    Logger.info("Testing query characteristic refresh...")

    # Simulate a write to the command characteristic
    send(Process.whereis(AiReality2Transnet.Bluetooth), {:gatt_write, "command", []})
    Logger.info("Query refresh triggered. Check logs for Sentant list update.")
    :ok
  end

  @doc """
  Tests node discovery functionality.
  """
  def test_node_discovery do
    Logger.info("Testing node discovery...")

    # Trigger a scan
    GenServer.cast(AiReality2Transnet.Bluetooth, %{
      command: "scan_nodes",
      parameters: %{timeout: 5000}
    })

    Logger.info("Node scan started (5 seconds). Watch for :r2nodes message.")
    :ok
  end

  @doc """
  Lists available Bluetooth adapters.
  """
  def list_adapters do
    Logger.info("Listing Bluetooth adapters...")

    GenServer.cast(AiReality2Transnet.Bluetooth, %{command: "list_adapters"})
    Logger.info("Adapter list requested. Watch for :adapters message.")
    :ok
  end

  @doc """
  Runs a comprehensive test suite.
  """
  def run_all_tests do
    Logger.info("=== Running Bluetooth/GATT Test Suite ===\n")

    with {:ok, _pid} <- start(),
         {:ok, state} <- check_state(),
         :ok <- verify_services(state),
         :ok <- test_query(),
         :ok <- wait(1000),
         :ok <- test_broadcast(),
         :ok <- wait(1000),
         :ok <- test_mutation(),
         :ok <- wait(1000),
         :ok <- list_adapters(),
         :ok <- wait(1000),
         :ok <- test_node_discovery() do
      Logger.info("\n=== All Tests Completed ===")
      Logger.info("Check nRF Connect or bluetoothctl to verify GATT operations.")
      :ok
    else
      {:error, reason} ->
        Logger.error("Test suite failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp verify_services(state) do
    cond do
      is_nil(state[:gatt_handle]) ->
        Logger.error("GATT server not started!")
        {:error, :gatt_not_running}

      is_nil(state[:r2_beacon]) ->
        Logger.warn("Beacon not running (may be expected)")
        :ok

      is_nil(state[:r2_watch]) ->
        Logger.warn("Node watch not running (may be expected)")
        :ok

      true ->
        Logger.info("✓ All services appear to be running")
        :ok
    end
  end

  defp wait(ms) do
    Process.sleep(ms)
    :ok
  end

  @doc """
  Monitor Bluetooth messages for debugging.
  Call this in IEx to see all messages flowing through.
  """
  def monitor_messages(duration_ms \\ 10_000) do
    pid = Process.whereis(AiReality2Transnet.Bluetooth)

    if pid do
      Logger.info("Monitoring Bluetooth messages for #{duration_ms}ms...")
      :erlang.trace(pid, true, [:receive])

      spawn(fn ->
        monitor_loop(duration_ms)
      end)

      :ok
    else
      {:error, "Bluetooth process not running"}
    end
  end

  defp monitor_loop(0), do: :erlang.trace(:all, false, [:receive])

  defp monitor_loop(remaining) do
    receive do
      {:trace, _pid, :receive, msg} ->
        Logger.debug("Bluetooth received: #{inspect(msg)}")
        Process.sleep(100)
        monitor_loop(remaining - 100)
    after
      100 ->
        monitor_loop(remaining - 100)
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Peer Connection Tests
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Lists all connected peer nodes and their sentants.
  """
  def list_connected_peers do
    peers = AiReality2Transnet.Bluetooth.get_connected_peers()

    Logger.info("""
    Connected Peers:
    ================
    Total peers: #{map_size(peers)}
    """)

    Enum.each(peers, fn {node_id, peer_info} ->
      Logger.info("""

      Peer Node: #{node_id}
      Address: #{peer_info.address}
      Connected: #{peer_info.connected_at}
      Sentants: #{peer_info.sentant_count}
      """)

      # List peer's sentants
      Enum.each(peer_info.sentants, fn sentant ->
        name = Map.get(sentant, "name", "unnamed")
        id = Map.get(sentant, "id", "no-id")
        Logger.info("  - #{name} (#{id})")
      end)
    end)

    {:ok, peers}
  end

  @doc """
  Send a test mutation to a peer's sentant.

  ## Parameters
  - `peer_node_id` - The peer node UUID
  - `sentant_id` - The sentant UUID on the peer node
  - `event` - Event name (default: "ping")
  - `parameters` - Optional parameters map
  """
  def send_to_peer(peer_node_id, sentant_id, event \\ "ping", parameters \\ %{test: "value"}) do
    Logger.info("Sending '#{event}' to peer #{peer_node_id}, sentant #{sentant_id}...")

    case AiReality2Transnet.Bluetooth.send_to_peer_sentant(peer_node_id, sentant_id, event, parameters) do
      :ok ->
        Logger.info("✓ Mutation sent successfully")
        {:ok, :sent}

      {:error, reason} ->
        Logger.error("✗ Failed to send mutation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get detailed info about a specific connected peer.
  """
  def get_peer_info(peer_node_id) do
    case AiReality2Transnet.Bluetooth.get_peer(peer_node_id) do
      {:ok, peer_info} ->
        Logger.info("""
        Peer Information:
        =================
        Node ID: #{peer_node_id}
        BLE Address: #{peer_info.address}
        Connected At: #{peer_info.connected_at}
        Sentant Count: #{peer_info.sentant_count}

        Sentants:
        """)

        Enum.each(peer_info.sentants, fn sentant ->
          name = Map.get(sentant, "name", "unnamed")
          id = Map.get(sentant, "id", "no-id")
          events = Map.get(sentant, "events", [])
          event_names = Enum.map(events, fn e -> Map.get(e, "name", "") end)

          Logger.info("""
            Name: #{name}
            ID: #{id}
            Events: #{inspect(event_names)}
          """)
        end)

        {:ok, peer_info}

      {:error, :not_found} ->
        Logger.warning("Peer #{peer_node_id} not connected")
        {:error, :not_found}
    end
  end

  @doc """
  Full peer-to-peer test:
  1. Discover nodes
  2. Wait for auto-connection
  3. List connected peers
  4. Send a test mutation to first peer's first sentant (if available)
  """
  def test_peer_to_peer do
    Logger.info("=== Starting Peer-to-Peer Test ===")

    # Step 1: Discover nodes
    Logger.info("\n1. Discovering nearby R2 nodes...")
    test_node_discovery()

    # Step 2: Wait for auto-connection
    Logger.info("\n2. Waiting 5 seconds for auto-connection...")
    wait(5000)

    # Step 3: List connected peers
    Logger.info("\n3. Checking connected peers...")
    {:ok, peers} = list_connected_peers()

    # Step 4: Try to send a mutation to first peer
    case Enum.at(Map.to_list(peers), 0) do
      {peer_id, peer_info} ->
        Logger.info("\n4. Attempting to send mutation to first peer...")

        case Enum.at(peer_info.sentants, 0) do
          nil ->
            Logger.warning("Peer has no sentants")
            {:ok, :no_sentants}

          sentant ->
            sentant_id = Map.get(sentant, "id")
            events = Map.get(sentant, "events", [])

            case Enum.at(events, 0) do
              nil ->
                Logger.warning("Sentant has no events")
                {:ok, :no_events}

              event ->
                event_name = Map.get(event, "name")
                Logger.info("Sending '#{event_name}' event...")
                send_to_peer(peer_id, sentant_id, event_name)
            end
        end

      nil ->
        Logger.warning("No peers connected")
        {:error, :no_peers}
    end
  end
end
