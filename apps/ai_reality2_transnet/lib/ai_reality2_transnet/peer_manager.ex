defmodule AiReality2Transnet.PeerManager do
  @moduledoc """
  Manages discovered peers in the Reality2 Transient Network.

  Tracks peer nodes discovered via BLE beacons, maintains their state,
  manages transport upgrades (BLE → WiFi mesh), and coordinates with
  the PNS Router for Sentant routing.

  ## State Management

  For each peer, tracks:
  - Node ID (UUID)
  - Transport method (:ble_gatt | :wifi_mesh)
  - Available Sentants
  - Connection info (address, RSSI, etc.)
  - Capabilities (WiFi mesh support, etc.)
  - Last seen timestamp

  ## Lifecycle

  1. **Discovery** - BLE beacon detected → peer added
  2. **Connection** - GATT connection established
  3. **Exchange** - Sentant directory retrieved
  4. **Upgrade** - (Optional) Upgrade to WiFi mesh
  5. **Monitor** - Track connection health
  6. **Removal** - Peer lost or timeout

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  # Suppress warnings for optional PNS integration (runtime checks used)
  # PNS is a higher-level module that depends on transnet, not vice versa
  # We use Code.ensure_loaded?/1 to avoid circular dependency
  @compile {:no_warn_undefined, AiReality2Pns.Router}

  @peer_timeout_ms 60_000  # Remove peers not seen for 60 seconds
  @cleanup_interval_ms 30_000  # Check for stale peers every 30 seconds

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Registers a peer discovered via BLE beacon.

  ## Parameters
  - `node_id` - UUID of the peer node
  - `info` - Map containing beacon info (address, rssi, etc.)

  ## Returns
  `:ok`
  """
  @spec register_peer(String.t(), map()) :: :ok
  def register_peer(node_id, info) do
    GenServer.cast(__MODULE__, {:register_peer, node_id, info})
  end

  @doc """
  Updates a peer's Sentant directory after GATT exchange.

  ## Parameters
  - `node_id` - UUID of the peer node
  - `sentants` - List of Sentant maps from GATT protocol

  ## Returns
  `:ok`
  """
  @spec update_peer_sentants(String.t(), list()) :: :ok
  def update_peer_sentants(node_id, sentants) do
    GenServer.cast(__MODULE__, {:update_sentants, node_id, sentants})
  end

  @doc """
  Updates a peer's capabilities (e.g., WiFi mesh support).

  ## Parameters
  - `node_id` - UUID of the peer node
  - `capabilities` - Map of capabilities

  ## Returns
  `:ok`
  """
  @spec update_peer_capabilities(String.t(), map()) :: :ok
  def update_peer_capabilities(node_id, capabilities) do
    GenServer.cast(__MODULE__, {:update_capabilities, node_id, capabilities})
  end

  @doc """
  Upgrades a peer's transport to WiFi mesh.

  ## Parameters
  - `node_id` - UUID of the peer node

  ## Returns
  `:ok`
  """
  @spec upgrade_to_wifi_mesh(String.t()) :: :ok
  def upgrade_to_wifi_mesh(node_id) do
    GenServer.cast(__MODULE__, {:upgrade_transport, node_id, :wifi_mesh})
  end

  @doc """
  Removes a peer (e.g., when lost or timed out).

  ## Parameters
  - `node_id` - UUID of the peer node

  ## Returns
  `:ok`
  """
  @spec remove_peer(String.t()) :: :ok
  def remove_peer(node_id) do
    GenServer.cast(__MODULE__, {:remove_peer, node_id})
  end

  @doc """
  Gets information about a specific peer.

  ## Parameters
  - `node_id` - UUID of the peer node

  ## Returns
  - `{:ok, peer_info}` - Peer found
  - `{:error, :not_found}` - Peer not tracked
  """
  @spec get_peer(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_peer(node_id) do
    GenServer.call(__MODULE__, {:get_peer, node_id})
  end

  @doc """
  Gets all tracked peers.

  ## Returns
  Map of node_id => peer_info
  """
  @spec get_all_peers() :: map()
  def get_all_peers do
    GenServer.call(__MODULE__, :get_all_peers)
  end

  @doc """
  Gets the current transport method for a peer.

  ## Parameters
  - `node_id` - UUID of the peer node

  ## Returns
  - `:ble_gatt` | `:wifi_mesh` - Current transport
  - `nil` - Peer not found
  """
  @spec get_transport(String.t()) :: atom() | nil
  def get_transport(node_id) do
    case get_peer(node_id) do
      {:ok, peer} -> peer.transport
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets statistics about peer connections.

  ## Returns
  Map with peer statistics
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
    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      # Map of node_id => peer_info
      peers: %{},
      # Statistics
      stats: %{
        total_discovered: 0,
        total_removed: 0,
        ble_connections: 0,
        wifi_upgrades: 0
      }
    }

    Logger.info("[PeerManager] Started - tracking transient network peers")
    {:ok, state}
  end

  @impl true
  def handle_cast({:register_peer, node_id, info}, state) do
    existing = Map.get(state.peers, node_id)

    peer = %{
      node_id: node_id,
      transport: :ble_gatt,
      address: Map.get(info, :address),
      rssi: Map.get(info, :rssi),
      sentants: [],
      capabilities: %{},
      discovered_at: System.system_time(:millisecond),
      last_seen: System.system_time(:millisecond),
      connection_state: :discovered
    }

    # Merge with existing peer if already known
    peer = if existing, do: Map.merge(existing, peer), else: peer

    new_peers = Map.put(state.peers, node_id, peer)
    new_stats = if existing, do: state.stats, else: Map.update!(state.stats, :total_discovered, &(&1 + 1))

    unless existing do
      Logger.info("[PeerManager] New peer discovered: #{String.slice(node_id, 0..7)}... (RSSI: #{peer.rssi})")
    end

    {:noreply, %{state | peers: new_peers, stats: new_stats}}
  end

  @impl true
  def handle_cast({:update_sentants, node_id, sentants}, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        Logger.warning("[PeerManager] Cannot update sentants for unknown peer: #{node_id}")
        {:noreply, state}

      peer ->
        updated_peer = %{peer |
          sentants: sentants,
          last_seen: System.system_time(:millisecond),
          connection_state: :sentants_exchanged
        }

        new_peers = Map.put(state.peers, node_id, updated_peer)

        Logger.info("[PeerManager] Updated sentants for #{String.slice(node_id, 0..7)}...: #{length(sentants)} sentants")

        # Notify PNS Router to refresh topology
        if Code.ensure_loaded?(AiReality2Pns.Router) do
          AiReality2Pns.Router.refresh_topology()
        end

        {:noreply, %{state | peers: new_peers}}
    end
  end

  @impl true
  def handle_cast({:update_capabilities, node_id, capabilities}, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        {:noreply, state}

      peer ->
        updated_peer = %{peer |
          capabilities: capabilities,
          last_seen: System.system_time(:millisecond)
        }

        new_peers = Map.put(state.peers, node_id, updated_peer)

        Logger.debug("[PeerManager] Updated capabilities for #{String.slice(node_id, 0..7)}...: #{inspect(capabilities)}")

        {:noreply, %{state | peers: new_peers}}
    end
  end

  @impl true
  def handle_cast({:upgrade_transport, node_id, new_transport}, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        {:noreply, state}

      peer ->
        updated_peer = %{peer |
          transport: new_transport,
          last_seen: System.system_time(:millisecond)
        }

        new_peers = Map.put(state.peers, node_id, updated_peer)
        new_stats = if new_transport == :wifi_mesh,
          do: Map.update!(state.stats, :wifi_upgrades, &(&1 + 1)),
          else: state.stats

        Logger.info("[PeerManager] Transport upgraded to #{new_transport} for #{String.slice(node_id, 0..7)}...")

        {:noreply, %{state | peers: new_peers, stats: new_stats}}
    end
  end

  @impl true
  def handle_cast({:remove_peer, node_id}, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        {:noreply, state}

      _peer ->
        new_peers = Map.delete(state.peers, node_id)
        new_stats = Map.update!(state.stats, :total_removed, &(&1 + 1))

        Logger.info("[PeerManager] Peer removed: #{String.slice(node_id, 0..7)}...")

        # Notify PNS Router to refresh topology
        if Code.ensure_loaded?(AiReality2Pns.Router) do
          AiReality2Pns.Router.refresh_topology()
        end

        {:noreply, %{state | peers: new_peers, stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:get_peer, node_id}, _from, state) do
    case Map.get(state.peers, node_id) do
      nil -> {:reply, {:error, :not_found}, state}
      peer -> {:reply, {:ok, peer}, state}
    end
  end

  @impl true
  def handle_call(:get_all_peers, _from, state) do
    {:reply, state.peers, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      current_peers: map_size(state.peers),
      ble_peers: count_by_transport(state.peers, :ble_gatt),
      wifi_peers: count_by_transport(state.peers, :wifi_mesh)
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup_stale_peers, state) do
    now = System.system_time(:millisecond)
    cutoff = now - @peer_timeout_ms

    {stale_peers, fresh_peers} =
      Enum.split_with(state.peers, fn {_id, peer} ->
        peer.last_seen < cutoff
      end)

    # Remove stale peers
    Enum.each(stale_peers, fn {node_id, _peer} ->
      Logger.info("[PeerManager] Removing stale peer: #{String.slice(node_id, 0..7)}... (timeout)")
    end)

    new_peers = Map.new(fresh_peers)
    new_stats = Map.update!(state.stats, :total_removed, &(&1 + length(stale_peers)))

    # Notify PNS Router if peers were removed
    if length(stale_peers) > 0 and Code.ensure_loaded?(AiReality2Pns.Router) do
      AiReality2Pns.Router.refresh_topology()
    end

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, %{state | peers: new_peers, stats: new_stats}}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale_peers, @cleanup_interval_ms)
  end

  defp count_by_transport(peers, transport) do
    peers
    |> Enum.count(fn {_id, peer} -> peer.transport == transport end)
  end
end
