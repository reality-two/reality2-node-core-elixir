defmodule AiReality2Transnet.TransportManager do
  @moduledoc """
  Manages transport layer decisions for Reality2 Transient Networks.

  Determines when to upgrade from BLE GATT to WiFi mesh based on:
  - Data volume and throughput requirements
  - Number of connected peers
  - Battery level considerations
  - Signal quality (BLE RSSI vs WiFi capability)
  - Peer capabilities (does peer support WiFi mesh?)

  ## Upgrade Strategy

  ### BLE GATT (Default)
  - **Pros**: Low power, ubiquitous, good for discovery
  - **Cons**: Low bandwidth (~1 Mbps), limited range
  - **Use for**: Small messages, sensor data, control commands

  ### WiFi Mesh (Upgrade)
  - **Pros**: High bandwidth (~50+ Mbps), better range, scales with peers
  - **Cons**: Higher power consumption, requires WiFi hardware
  - **Use for**: Large data transfers, streaming, multiple peers

  ## Decision Criteria

  Upgrade to WiFi mesh when ANY of:
  1. Data volume exceeds BLE threshold (e.g., >10KB/sec)
  2. Number of peers exceeds threshold (e.g., >3 peers)
  3. Explicit user/application request
  4. Peer signals high-bandwidth capability

  Stay on BLE when:
  1. Low battery mode enabled
  2. WiFi not available on either peer
  3. Data volume is minimal
  4. Single peer connection

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  alias AiReality2Transnet.{PeerManager, Wifi}

  # Configuration thresholds
  @data_volume_threshold_bytes_per_sec 10_000  # 10 KB/s
  @peer_count_threshold 3
  @rssi_quality_threshold -70  # dBm
  @upgrade_check_interval_ms 10_000  # Check every 10 seconds

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Checks if a peer should be upgraded to WiFi mesh.

  ## Parameters
  - `peer_id` - UUID of the peer node

  ## Returns
  - `{:yes, reason}` - Should upgrade
  - `{:no, reason}` - Should stay on BLE
  """
  @spec should_upgrade_to_wifi?(String.t()) :: {:yes, String.t()} | {:no, String.t()}
  def should_upgrade_to_wifi?(peer_id) do
    GenServer.call(__MODULE__, {:check_upgrade, peer_id})
  end

  @doc """
  Initiates WiFi mesh upgrade for a peer.

  This coordinates both sides to:
  1. Create mesh interface
  2. Join common mesh network
  3. Establish connection
  4. Update PeerManager transport

  ## Parameters
  - `peer_id` - UUID of the peer node
  - `mesh_id` - Mesh network identifier (optional, generates one if nil)

  ## Returns
  - `:ok` - Upgrade initiated
  - `{:error, reason}` - Failed to upgrade
  """
  @spec initiate_wifi_upgrade(String.t(), String.t() | nil) :: :ok | {:error, String.t()}
  def initiate_wifi_upgrade(peer_id, mesh_id \\ nil) do
    GenServer.call(__MODULE__, {:initiate_upgrade, peer_id, mesh_id})
  end

  @doc """
  Records data transfer for throughput tracking.

  ## Parameters
  - `peer_id` - UUID of the peer
  - `bytes` - Number of bytes transferred

  ## Returns
  `:ok`
  """
  @spec record_data_transfer(String.t(), integer()) :: :ok
  def record_data_transfer(peer_id, bytes) do
    GenServer.cast(__MODULE__, {:record_transfer, peer_id, bytes})
  end

  @doc """
  Gets transport statistics.

  ## Returns
  Map with transport statistics
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Schedule periodic upgrade checks
    schedule_upgrade_check()

    state = %{
      # Track data transfer per peer: %{peer_id => %{bytes: X, timestamp: Y}}
      data_transfers: %{},
      # Statistics
      stats: %{
        upgrade_checks: 0,
        upgrades_initiated: 0,
        upgrades_succeeded: 0,
        upgrades_failed: 0
      },
      # Active mesh info
      mesh_info: %{
        interface: nil,
        mesh_id: nil,
        active: false
      }
    }

    Logger.info("[TransportManager] Started - managing BLE/WiFi transport decisions")
    {:ok, state}
  end

  @impl true
  def handle_call({:check_upgrade, peer_id}, _from, state) do
    result = evaluate_upgrade_decision(peer_id, state)
    new_stats = Map.update!(state.stats, :upgrade_checks, &(&1 + 1))
    {:reply, result, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call({:initiate_upgrade, peer_id, mesh_id}, _from, state) do
    case perform_wifi_upgrade(peer_id, mesh_id, state) do
      {:ok, new_state} ->
        new_stats = Map.update!(new_state.stats, :upgrades_succeeded, &(&1 + 1))
        {:reply, :ok, %{new_state | stats: new_stats}}

      {:error, _reason} = error ->
        new_stats = Map.update!(state.stats, :upgrades_failed, &(&1 + 1))
        {:reply, error, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      mesh_active: state.mesh_info.active,
      tracked_transfers: map_size(state.data_transfers)
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record_transfer, peer_id, bytes}, state) do
    now = System.system_time(:millisecond)

    transfer = %{
      bytes: bytes,
      timestamp: now
    }

    new_transfers = Map.update(state.data_transfers, peer_id, transfer, fn existing ->
      %{
        bytes: existing.bytes + bytes,
        timestamp: now
      }
    end)

    {:noreply, %{state | data_transfers: new_transfers}}
  end

  @impl true
  def handle_info(:check_upgrades, state) do
    # Periodically check if any peers should be upgraded
    peers = PeerManager.get_all_peers()

    Enum.each(peers, fn {peer_id, peer} ->
      if peer.transport == :ble_gatt do
        case evaluate_upgrade_decision(peer_id, state) do
          {:yes, reason} ->
            Logger.info("[TransportManager] Auto-upgrade recommended for #{String.slice(peer_id, 0..7)}...: #{reason}")
            # Could auto-upgrade here, or just log recommendation
            # initiate_wifi_upgrade(peer_id, nil)

          {:no, _reason} ->
            :ok
        end
      end
    end)

    schedule_upgrade_check()
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Evaluate whether a peer should be upgraded to WiFi mesh
  defp evaluate_upgrade_decision(peer_id, state) do
    with {:ok, peer} <- PeerManager.get_peer(peer_id),
         {:ok, wifi_adapters} <- Wifi.list_adapters() do

      cond do
        # Already on WiFi
        peer.transport == :wifi_mesh ->
          {:no, "already_on_wifi"}

        # No WiFi hardware
        Enum.empty?(wifi_adapters) ->
          {:no, "no_wifi_hardware"}

        # Peer doesn't support WiFi
        not peer_supports_wifi?(peer) ->
          {:no, "peer_no_wifi_support"}

        # High data volume
        exceeds_data_threshold?(peer_id, state) ->
          {:yes, "high_data_volume"}

        # Many peers
        exceeds_peer_threshold?() ->
          {:yes, "many_peers"}

        # Poor BLE signal quality
        poor_ble_signal?(peer) ->
          {:yes, "poor_ble_signal"}

        true ->
          {:no, "criteria_not_met"}
      end
    else
      {:error, :not_found} ->
        {:no, "peer_not_found"}

      {:error, reason} ->
        {:no, "error: #{inspect(reason)}"}
    end
  end

  # Perform the actual WiFi mesh upgrade
  defp perform_wifi_upgrade(peer_id, mesh_id, state) do
    with {:ok, _peer} <- PeerManager.get_peer(peer_id),
         {:ok, adapters} <- Wifi.list_adapters(),
         adapter when adapter != nil <- List.first(adapters) do

      # Generate mesh ID if not provided
      mesh_id = mesh_id || generate_mesh_id(peer_id)

      Logger.info("[TransportManager] Initiating WiFi upgrade for #{String.slice(peer_id, 0..7)}...")

      # Create mesh interface
      case Wifi.create_mesh_interface(adapter.interface, "mesh0") do
        :ok ->
          # Start mesh network
          case Wifi.start_mesh("mesh0", mesh_id) do
            :ok ->
              # Update peer transport
              PeerManager.upgrade_to_wifi_mesh(peer_id)

              # Update state
              new_mesh_info = %{
                interface: "mesh0",
                mesh_id: mesh_id,
                active: true
              }

              Logger.info("[TransportManager] WiFi upgrade successful: mesh_id=#{mesh_id}")
              {:ok, %{state | mesh_info: new_mesh_info}}

            {:error, reason} ->
              Logger.error("[TransportManager] Failed to start mesh: #{inspect(reason)}")
              {:error, "mesh_start_failed: #{reason}"}
          end

        {:error, reason} ->
          Logger.error("[TransportManager] Failed to create mesh interface: #{inspect(reason)}")
          {:error, "mesh_create_failed: #{reason}"}
      end
    else
      [] ->
        {:error, "no_wifi_adapters"}

      nil ->
        {:error, "no_wifi_adapters"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Check if peer supports WiFi mesh
  defp peer_supports_wifi?(peer) do
    get_in(peer, [:capabilities, :wifi_mesh]) == true
  end

  # Check if data volume exceeds threshold
  defp exceeds_data_threshold?(peer_id, state) do
    case Map.get(state.data_transfers, peer_id) do
      nil ->
        false

      transfer ->
        now = System.system_time(:millisecond)
        age_seconds = (now - transfer.timestamp) / 1000
        bytes_per_second = if age_seconds > 0, do: transfer.bytes / age_seconds, else: 0

        bytes_per_second > @data_volume_threshold_bytes_per_sec
    end
  end

  # Check if peer count exceeds threshold
  defp exceeds_peer_threshold? do
    peers = PeerManager.get_all_peers()
    map_size(peers) >= @peer_count_threshold
  end

  # Check if BLE signal is poor
  defp poor_ble_signal?(peer) do
    case peer.rssi do
      nil -> false
      rssi when rssi < @rssi_quality_threshold -> true
      _ -> false
    end
  end

  # Generate a mesh ID based on peer pair
  defp generate_mesh_id(peer_id) do
    # Use first 8 chars of peer ID to create unique mesh ID
    "R2MESH_" <> String.slice(peer_id, 0..7)
  end

  defp schedule_upgrade_check do
    Process.send_after(self(), :check_upgrades, @upgrade_check_interval_ms)
  end
end
