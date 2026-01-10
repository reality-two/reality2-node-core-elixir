defmodule AiReality2Transnet.PeerManager do
  @moduledoc """
  Manages discovered peers in the Reality2 Transient Network.

  Tracks peer nodes discovered via BLE beacons, maintains their state,
  manages transport upgrades (BLE → WiFi hotspot), and coordinates with
  the PNS Router for Sentant routing.

  ## State Management

  For each peer, tracks:
  - Node ID (UUID)
  - Transport method (:ble_gatt | :wifi_hotspot)
  - Available Sentants
  - Connection info (address, RSSI, etc.)
  - Capabilities (WiFi hotspot support, etc.)
  - Last seen timestamp

  ## Lifecycle

  1. **Discovery** - BLE beacon detected → peer added
  2. **Connection** - Optional GATT bootstrap exchange (minimal metadata)
  3. **Upgrade** - Connect to WiFi hotspot (host) or accept connection (client)
  4. **Exchange** - Sentant directory retrieved over WiFi (HTTP/GraphQL)
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
  # Type Definitions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc """
  Represents a peer node in the Reality2 Transient Network.

  ## Fields
  - `node_id` - UUID of the peer node
  - `node_name` - Human-readable node name (e.g., "R2Node_A3F7")
  - `transport` - Current transport method (`:ble_gatt` or `:wifi_hotspot`)
  - `address` - BLE MAC address (may be nil for WiFi-only peers)
  - `rssi` - Signal strength in dBm (may be nil)
  - `sentants` - List of Sentant maps available on this peer (includes id and name)
  - `capabilities` - Map of peer capabilities (e.g., `%{wifi_hotspot: true}`)
  - `discovered_at` - Unix timestamp (milliseconds) when peer was first discovered
  - `last_seen` - Unix timestamp (milliseconds) of last beacon or interaction
  - `connection_state` - Connection lifecycle state (`:discovered`, `:sentants_exchanged`, etc.)
  """
  @type peer :: %{
    node_id: String.t(),
    node_name: String.t() | nil,
    transport: :ble_gatt | :wifi_hotspot,
    address: binary() | nil,
    rssi: integer() | nil,
    sentants: [map()],
    capabilities: map(),
    discovered_at: integer(),
    last_seen: integer(),
    connection_state: atom()
  }

  @typedoc """
  Internal GenServer state for PeerManager.

  ## Fields
  - `peers` - Map of node_id to peer structs
  """
  @type state :: %{
    peers: %{String.t() => peer()}
  }

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
  Updates a peer's Sentant directory after WiFi hotspot query.

  ## Parameters
  - `node_id` - UUID of the peer node
  - `sentants` - List of Sentant maps from GraphQL query

  ## Returns
  `:ok`
  """
  @spec update_peer_sentants(String.t(), list()) :: :ok
  def update_peer_sentants(node_id, sentants) do
    GenServer.cast(__MODULE__, {:update_sentants, node_id, sentants})
  end

  @doc """
  Updates a peer's capabilities (e.g., WiFi hotspot support).

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
  Updates a peer's transport type.

  ## Parameters
  - `node_id` - UUID of the peer node
  - `transport` - New transport type (`:ble_gatt`, `:wifi_mesh`, `:wifi_hotspot`)

  ## Returns
  `:ok`
  """
  @spec update_peer_transport(String.t(), atom()) :: :ok
  def update_peer_transport(node_id, transport) do
    GenServer.cast(__MODULE__, {:upgrade_transport, node_id, transport})
  end

  @doc """
  Upgrades a peer's transport to WiFi hotspot.

  ## Parameters
  - `node_id` - UUID of the peer node

  ## Returns
  `:ok`
  """
  @spec upgrade_to_wifi_hotspot(String.t()) :: :ok
  def upgrade_to_wifi_hotspot(node_id) do
    update_peer_transport(node_id, :wifi_hotspot)
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
  Gets information about a specific peer by node ID.

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
  Gets information about a specific peer by node name.

  ## Parameters
  - `node_name` - Human-readable node name (e.g., "R2Node_A3F7")

  ## Returns
  - `{:ok, peer_info}` - Peer found
  - `{:error, :not_found}` - Peer not tracked
  """
  @spec get_peer_by_name(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_peer_by_name(node_name) do
    GenServer.call(__MODULE__, {:get_peer_by_name, node_name})
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
  - `:ble_gatt` | `:wifi_hotspot` - Current transport
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
    # Check if we've seen this peer before
    existing = Map.get(state.peers, node_id)

    # Extract node_name from info (may come from GATT decode or other sources)
    node_name = Map.get(info, :node_name) || Map.get(info, "node_name")

    # Extract capabilities from info (may come from beacon decode or GATT)
    capabilities = Map.get(info, :capabilities) || Map.get(info, "capabilities") || %{}

    # Build new peer record with defaults
    # Start with BLE transport (will be upgraded to WiFi later if available)
    peer = %{
      node_id: node_id,
      node_name: node_name,              # Human-readable node name
      transport: :ble_gatt,              # Initially discovered via BLE beacon
      address: Map.get(info, :address),  # BLE MAC address
      rssi: Map.get(info, :rssi),        # Signal strength from beacon
      sentants: [],                      # Will be populated after exchange
      capabilities: capabilities,        # From beacon flags or GATT
      discovered_at: System.system_time(:millisecond),
      last_seen: System.system_time(:millisecond),
      connection_state: :discovered      # Initial state in lifecycle
    }

    # If peer already exists, merge new data with existing record
    # This preserves sentants list, capabilities, etc. while updating RSSI and last_seen
    peer = if existing, do: Map.merge(existing, peer), else: peer

    # Store updated peer in state
    new_peers = Map.put(state.peers, node_id, peer)

    # Register node_name -> node_id mapping for PNS lookup
    if peer.node_name do
      Reality2.Metadata.set(:PNS_NodeNames, peer.node_name, node_id)
    end

    # Only increment discovery counter for brand new peers
    new_stats = if existing, do: state.stats, else: Map.update!(state.stats, :total_discovered, &(&1 + 1))

    # Log new peer discovery (but not re-discoveries from beacons)
    unless existing do
      name_info = if peer.node_name, do: " (#{peer.node_name})", else: ""
      Logger.info("[PeerManager] New peer discovered: #{String.slice(node_id, 0..7)}...#{name_info} (RSSI: #{peer.rssi})")
    end

    {:noreply, %{state | peers: new_peers, stats: new_stats}}
  end

  @impl true
  def handle_cast({:update_sentants, node_id, sentants}, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        # Peer not found - may have been removed or never registered
        Logger.warning("[PeerManager] Cannot update sentants for unknown peer: #{node_id}")
        {:noreply, state}

      peer ->
        # Update peer with the Sentant directory received from WiFi hotspot exchange
        # This happens after successful GraphQL sentantAll query
        updated_peer = %{peer |
          sentants: sentants,                           # List of Sentant maps from peer
          last_seen: System.system_time(:millisecond),  # Update activity timestamp
          connection_state: :sentants_exchanged         # Mark exchange as complete
        }

        new_peers = Map.put(state.peers, node_id, updated_peer)

        Logger.info("[PeerManager] Updated sentants for #{String.slice(node_id, 0..7)}...: #{length(sentants)} sentants")

        # Notify PNS Router that new remote Sentants are available
        # This triggers routing table refresh so messages can be routed to this peer
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
        # Peer not found - silently ignore (may have been removed)
        {:noreply, state}

      peer ->
        # Update peer capabilities (e.g., %{wifi_hotspot: true, battery_level: 85})
        # Capabilities are typically extracted from BLE beacon flags
        updated_peer = %{peer |
          capabilities: capabilities,                   # Store capability map
          last_seen: System.system_time(:millisecond)   # Update activity timestamp
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
        # Peer not found - silently ignore
        {:noreply, state}

      peer ->
        # Upgrade peer's transport layer (e.g., :ble_gatt → :wifi_hotspot)
        # This happens after successful WiFi hotspot connection
        updated_peer = %{peer |
          transport: new_transport,                     # Set new transport type
          last_seen: System.system_time(:millisecond)   # Update activity timestamp
        }

        new_peers = Map.put(state.peers, node_id, updated_peer)

        # Track WiFi upgrades in statistics (for monitoring/debugging)
        new_stats = if new_transport == :wifi_hotspot,
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
        # Peer not found - already removed or never existed
        {:noreply, state}

      peer ->
        # Remove peer from tracking (e.g., user request or connection lost)
        new_peers = Map.delete(state.peers, node_id)
        new_stats = Map.update!(state.stats, :total_removed, &(&1 + 1))

        # Clean up PNS_NodeNames mapping
        if peer.node_name do
          Reality2.Metadata.delete(:PNS_NodeNames, peer.node_name)
        end

        Logger.info("[PeerManager] Peer removed: #{String.slice(node_id, 0..7)}...")

        # Notify PNS Router that peer is gone
        # This removes routes to Sentants on this peer
        if Code.ensure_loaded?(AiReality2Pns.Router) do
          AiReality2Pns.Router.refresh_topology()
        end

        {:noreply, %{state | peers: new_peers, stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:get_peer, node_id}, _from, state) do
    # Synchronous lookup of peer info by node ID
    case Map.get(state.peers, node_id) do
      nil -> {:reply, {:error, :not_found}, state}
      peer -> {:reply, {:ok, peer}, state}
    end
  end

  @impl true
  def handle_call({:get_peer_by_name, node_name}, _from, state) do
    # Synchronous lookup of peer info by node name
    peer = state.peers
    |> Map.values()
    |> Enum.find(fn p -> p.node_name == node_name end)

    case peer do
      nil -> {:reply, {:error, :not_found}, state}
      p -> {:reply, {:ok, p}, state}
    end
  end

  @impl true
  def handle_call(:get_all_peers, _from, state) do
    # Return entire peer map (used by PNS Router for routing table)
    {:reply, state.peers, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Calculate current statistics (totals + breakdown by transport)
    stats = Map.merge(state.stats, %{
      current_peers: map_size(state.peers),
      ble_peers: count_by_transport(state.peers, :ble_gatt),
      wifi_peers: count_by_transport(state.peers, :wifi_hotspot)
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup_stale_peers, state) do
    # Periodic cleanup task (runs every @cleanup_interval_ms)
    # Removes peers that haven't been seen for @peer_timeout_ms
    # EXCEPT peers with active WiFi connections (to prevent cleanup during exchange)
    now = System.system_time(:millisecond)
    cutoff = now - @peer_timeout_ms

    # Split peers into stale (timeout) and fresh (active)
    # Protected peers: those with active WiFi connection or recent sentant exchange
    {stale_peers, fresh_peers} =
      Enum.split_with(state.peers, fn {_id, peer} ->
        is_stale = peer.last_seen < cutoff
        is_protected = peer.transport == :wifi_hotspot ||
                       peer.connection_state == :sentants_exchanged

        # Only consider stale if both timeout has passed AND peer is not protected
        is_stale && !is_protected
      end)

    # Log each removal and clean up PNS_NodeNames mapping
    Enum.each(stale_peers, fn {node_id, peer} ->
      Logger.info("[PeerManager] Removing stale peer: #{String.slice(node_id, 0..7)}... (timeout)")
      if peer.node_name do
        Reality2.Metadata.delete(:PNS_NodeNames, peer.node_name)
      end
    end)

    new_peers = Map.new(fresh_peers)
    new_stats = Map.update!(state.stats, :total_removed, &(&1 + length(stale_peers)))

    # Notify PNS Router if any peers were removed
    # This removes routes to Sentants on timed-out peers
    if length(stale_peers) > 0 and Code.ensure_loaded?(AiReality2Pns.Router) do
      AiReality2Pns.Router.refresh_topology()
    end

    # Schedule next cleanup cycle
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
