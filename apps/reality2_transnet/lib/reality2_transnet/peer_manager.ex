defmodule Reality2Transnet.PeerManager do
  @moduledoc """
  Manages discovered peers in the Reality2 Transient Network.

  Tracks peer nodes discovered via BLE beacons, maintains their state,
  manages transport upgrades (BLE → WiFi hotspot), and coordinates with
  the WFS Router for Sentant routing.

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

  # Helper to get node name for log messages
  defp log_prefix, do: "[PeerManager:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  # Suppress warnings for optional WFS integration (runtime checks used)
  # WFS is a higher-level module that depends on transnet, not vice versa
  # We use Code.ensure_loaded?/1 to avoid circular dependency
  @compile {:no_warn_undefined, Reality2Wfs.Router}

  @peer_timeout_ms 60_000  # Remove peers not seen for 60 seconds
  @protected_peer_timeout_ms 300_000  # Remove protected peers not seen for 5 minutes
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
  - `hosting_priority` - WiFi hosting priority (0-100, from BLE beacon)
  - `sentants` - List of Sentant maps available on this peer (includes id and name)
  - `capabilities` - Map of peer capabilities (e.g., `%{wifi_hotspot: true}`)
  - `discovered_at` - Unix timestamp (milliseconds) when peer was first discovered
  - `last_seen` - Unix timestamp (milliseconds) of last beacon or interaction
  - `connection_state` - Connection lifecycle state (`:discovered`, `:sentants_exchanged`, etc.)

  ## Trust Group Fields (Phase 2)
  - `trust_group_id` - UUID of the Trust Group this peer belongs to (nil if unknown)
  - `trust_group_public_key` - Public key of the peer's Trust Group (for signature verification)
  - `node_cert` - Node certificate proving Trust Group membership (verified)
  - `is_same_trust_group` - true if peer is in the same Trust Group as us
  - `trust_group_verified` - true if we've verified the peer's Trust Group membership
  """
  @type peer :: %{
    node_id: String.t(),
    node_name: String.t() | nil,
    transport: :ble_gatt | :wifi_hotspot,
    address: binary() | nil,
    rssi: integer() | nil,
    hosting_priority: integer(),
    sentants: [map()],
    capabilities: map(),
    discovered_at: integer(),
    last_seen: integer(),
    connection_state: atom(),
    # Trust Group identity fields
    trust_group_id: String.t() | nil,
    trust_group_public_key: binary() | nil,
    node_cert: map() | nil,
    is_same_trust_group: boolean(),
    trust_group_verified: boolean()
  }

  @typedoc """
  Per-transport reachability tracking for a peer.

  ## Fields
  - `last_seen` - ISO8601 timestamp of last contact on this transport
  - `confidence` - 0-255 reachability confidence
  - `rssi` - Signal strength (BLE/LoRa)
  - `ip` - IP address (WiFi)
  - `via` - Relay node compressed ID (LoRa)
  """
  @type transport_reachability :: %{
    last_seen: String.t() | nil,
    confidence: non_neg_integer(),
    rssi: integer() | nil,
    ip: String.t() | nil,
    via: binary() | nil
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

  @doc """
  Gets the peer with the highest hosting priority.

  Used by ConnectionAssessor to determine which peer should become the WiFi host.

  ## Returns
  - `{:ok, peer}` - Peer with highest priority found
  - `{:error, :no_peers}` - No peers tracked
  """
  @spec get_highest_priority_peer() :: {:ok, map()} | {:error, :no_peers}
  def get_highest_priority_peer do
    GenServer.call(__MODULE__, :get_highest_priority_peer)
  end

  @doc """
  Gets the highest hosting priority among all tracked peers.

  ## Returns
  - `integer()` - Highest priority (0 if no peers)
  """
  @spec get_max_peer_priority() :: integer()
  def get_max_peer_priority do
    GenServer.call(__MODULE__, :get_max_peer_priority)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Trust Group-Aware Peer API (Phase 2)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Gets all peers that belong to the same Trust Group as this node.

  These are trusted peers with verified certificates.

  ## Returns
  Map of node_id => peer_info for same-Trust Group peers
  """
  @spec get_trust_group_peers() :: map()
  def get_trust_group_peers do
    GenServer.call(__MODULE__, :get_trust_group_peers)
  end

  @doc """
  Gets all peers from other Trust Groups (foreign peers).

  These may be trusted via federation or untrusted.

  ## Returns
  Map of node_id => peer_info for foreign peers
  """
  @spec get_foreign_peers() :: map()
  def get_foreign_peers do
    GenServer.call(__MODULE__, :get_foreign_peers)
  end

  @doc """
  Gets all peers belonging to a specific Trust Group.

  ## Parameters
  - `trust_group_id` - UUID of the Trust Group to filter by

  ## Returns
  Map of node_id => peer_info for peers in that Trust Group
  """
  @spec get_peers_by_trust_group(String.t()) :: map()
  def get_peers_by_trust_group(trust_group_id) do
    GenServer.call(__MODULE__, {:get_peers_by_trust_group, trust_group_id})
  end

  @doc """
  Updates a peer's Trust Group identity information.

  Called when we receive Trust Group info from a peer (e.g., via presence announcement
  or certificate exchange). Verifies the certificate if provided.

  ## Parameters
  - `node_id` - UUID of the peer node
  - `trust_group_info` - Map containing:
    - `:trust_group_id` - Trust Group UUID
    - `:trust_group_public_key` - Base64-encoded public key
    - `:node_cert` - (optional) Node certificate for verification

  ## Returns
  - `:ok` - Trust Group info updated
  - `{:error, :not_found}` - Peer not tracked
  - `{:error, :invalid_cert}` - Certificate verification failed
  """
  @spec update_peer_trust_group_info(String.t(), map()) :: :ok | {:error, term()}
  def update_peer_trust_group_info(node_id, trust_group_info) do
    GenServer.call(__MODULE__, {:update_trust_group_info, node_id, trust_group_info})
  end

  @doc """
  Checks if a peer has verified Trust Group membership.

  ## Parameters
  - `node_id` - UUID of the peer node

  ## Returns
  - `true` - Peer has valid, verified certificate
  - `false` - Peer not verified or not found
  """
  @spec peer_verified?(String.t()) :: boolean()
  def peer_verified?(node_id) do
    case get_peer(node_id) do
      {:ok, peer} -> peer.trust_group_verified
      _ -> false
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Reachability-Aware API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Updates transport-level reachability for a peer.

  Called on every interaction to track which transports can reach a peer
  and how reliably.

  ## Parameters
  - `node_id` - UUID of the peer node
  - `transport` - `:ble` | `:wifi` | `:lora`
  - `info` - Map with optional `:confidence`, `:rssi`, `:ip`, `:via`
  """
  @spec update_reachability(String.t(), atom(), map()) :: :ok
  def update_reachability(node_id, transport, info) do
    GenServer.cast(__MODULE__, {:update_reachability, node_id, transport, info})
  end

  @doc """
  Gets the best transport to reach a specific peer.

  Returns the transport with the highest confidence.

  ## Returns
  - `{:ok, transport_atom, reachability_info}` - Best transport
  - `{:error, :not_found}` - Peer not tracked
  - `{:error, :unreachable}` - No transport with sufficient confidence
  """
  @spec best_transport(String.t()) :: {:ok, atom(), transport_reachability()} | {:error, atom()}
  def best_transport(node_id) do
    GenServer.call(__MODULE__, {:best_transport, node_id})
  end

  @doc """
  Gets the reachability map for a peer (all transports).

  ## Returns
  - `{:ok, %{ble: ..., wifi: ..., lora: ...}}` - Reachability per transport
  - `{:error, :not_found}` - Peer not tracked
  """
  @spec get_reachability(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_reachability(node_id) do
    GenServer.call(__MODULE__, {:get_reachability, node_id})
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

    Logger.info("#{log_prefix()} Started - tracking transient network peers")
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

    # Extract hosting priority from beacon (0-100, default 0 if not broadcast)
    hosting_priority = Map.get(info, :hosting_priority) || Map.get(info, "hosting_priority") || 0

    # Build peer record - handle existing vs new peers differently
    peer = if existing do
      # EXISTING PEER: Only update fields that change on BLE beacon reception
      # PRESERVE: sentants, connection_state, transport, discovered_at, capabilities (unless new ones provided)
      existing
      |> Map.put(:rssi, Map.get(info, :rssi))
      |> Map.put(:last_seen, System.system_time(:millisecond))
      |> Map.put(:hosting_priority, hosting_priority)
      |> Map.put(:address, Map.get(info, :address) || existing.address)
      |> Map.put(:node_name, node_name || existing.node_name)
      |> then(fn p ->
        # Only update capabilities if new ones were provided
        if map_size(capabilities) > 0, do: Map.put(p, :capabilities, capabilities), else: p
      end)
      |> then(fn p ->
        # Update BLE reachability on every beacon
        reach = Map.get(p, :reachability, %{
          ble: %{last_seen: nil, confidence: 0, rssi: nil},
          wifi: %{last_seen: nil, confidence: 0, ip: nil},
          lora: %{last_seen: nil, confidence: 0, via: nil},
          internet: %{last_seen: nil, confidence: 0}
        })
        ble_reach = Map.merge(Map.get(reach, :ble, %{}), %{
          last_seen: DateTime.utc_now() |> DateTime.to_iso8601(),
          confidence: 200,
          rssi: Map.get(info, :rssi)
        })
        %{p | reachability: Map.put(reach, :ble, ble_reach)}
      end)
    else
      # NEW PEER: Create full record with defaults
      %{
        node_id: node_id,
        node_name: node_name,              # Human-readable node name
        transport: :ble_gatt,              # Initially discovered via BLE beacon
        address: Map.get(info, :address),  # BLE MAC address
        rssi: Map.get(info, :rssi),        # Signal strength from beacon
        hosting_priority: hosting_priority,# WiFi hosting priority (0-100)
        sentants: [],                      # Will be populated after exchange
        capabilities: capabilities,        # From beacon flags or GATT
        discovered_at: System.system_time(:millisecond),
        last_seen: System.system_time(:millisecond),
        connection_state: :discovered,     # Initial state in lifecycle
        # Trust Group identity fields (populated later via update_peer_trust_group_info)
        trust_group_id: nil,
        trust_group_public_key: nil,
        node_cert: nil,
        is_same_trust_group: false,
        trust_group_verified: false,
        # Per-transport reachability tracking
        reachability: %{
          ble: %{last_seen: DateTime.utc_now() |> DateTime.to_iso8601(), confidence: 200, rssi: Map.get(info, :rssi)},
          wifi: %{last_seen: nil, confidence: 0, ip: nil},
          lora: %{last_seen: nil, confidence: 0, via: nil}
        }
      }
    end

    # Store updated peer in state
    new_peers = Map.put(state.peers, node_id, peer)

    # Register node_name -> node_id mapping for WFS lookup
    if peer.node_name do
      Reality2.Metadata.set(:WFS_NodeNames, peer.node_name, node_id)
    end

    # Only increment discovery counter for brand new peers
    new_stats = if existing, do: state.stats, else: Map.update!(state.stats, :total_discovered, &(&1 + 1))

    # Log new peer discovery (but not re-discoveries from beacons)
    unless existing do
      name_info = if peer.node_name, do: " (#{peer.node_name})", else: ""
      Logger.info("#{log_prefix()} New peer discovered: #{String.slice(node_id, 0..7)}...#{name_info} (RSSI: #{peer.rssi})")

      # Check for proximity prompting - notify key holder of very close devices
      maybe_trigger_proximity_prompt(node_id, peer)
    end

    {:noreply, %{state | peers: new_peers, stats: new_stats}}
  end

  @impl true
  def handle_cast({:update_sentants, node_id, sentants}, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        # Peer not found - may have been removed or never registered
        Logger.warning("#{log_prefix()} Cannot update sentants for unknown peer: #{node_id}")
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

        Logger.info("#{log_prefix()} Updated sentants for #{String.slice(node_id, 0..7)}...: #{length(sentants)} sentants")

        # Notify WFS Router that new remote Sentants are available
        # This triggers routing table refresh so messages can be routed to this peer
        if Code.ensure_loaded?(Reality2Wfs.Router) do
          Reality2Wfs.Router.refresh_topology()
        end

        # Update TrustGroupDirectory with peer's sentants
        if Code.ensure_loaded?(Reality2Transnet.TrustGroupDirectory) and
           Process.whereis(Reality2Transnet.TrustGroupDirectory) != nil do
          sentant_entries = Enum.map(sentants, fn s ->
            %{
              id: Map.get(s, :id) || Map.get(s, "id"),
              name: Map.get(s, :name) || Map.get(s, "name", "")
            }
          end)
          Reality2Transnet.TrustGroupDirectory.register_node(node_id, %{
            sentants: sentant_entries
          })

          # Also update WiFi reachability since sentant exchange happens over WiFi
          Reality2Transnet.TrustGroupDirectory.update_reachability(node_id, :wifi, %{confidence: 255})
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

        Logger.debug("#{log_prefix()} Updated capabilities for #{String.slice(node_id, 0..7)}...: #{inspect(capabilities)}")

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

        Logger.info("#{log_prefix()} Transport upgraded to #{new_transport} for #{String.slice(node_id, 0..7)}...")

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
        # Protect peers with active WiFi hotspot connections from BLE lost events
        # They should only be removed via explicit unregistration or timeout
        if peer.transport == :wifi_hotspot do
          Logger.debug("#{log_prefix()} Ignoring remove request for WiFi-connected peer: #{String.slice(node_id, 0..7)}...")
          {:noreply, state}
        else
          # Emit __internal event for monitor sentant before removal
          if Code.ensure_loaded?(Reality2.Sentants) do
            Reality2.Sentants.sendto_all(%{
              event: "__internal",
              parameters: %{
                event: "mesh_peer_disconnected",
                peer_id: node_id,
                peer_name: peer.node_name || "Unknown"
              }
            })
          end

          # Remove peer from tracking (e.g., user request or connection lost)
          new_peers = Map.delete(state.peers, node_id)
          new_stats = Map.update!(state.stats, :total_removed, &(&1 + 1))

          # Clean up WFS_NodeNames mapping
          if peer.node_name do
            Reality2.Metadata.delete(:WFS_NodeNames, peer.node_name)
          end

          Logger.info("#{log_prefix()} Peer removed: #{String.slice(node_id, 0..7)}...")

          # Notify WFS Router that peer is gone
          # This removes routes to Sentants on this peer
          if Code.ensure_loaded?(Reality2Wfs.Router) do
            Reality2Wfs.Router.refresh_topology()
          end

          {:noreply, %{state | peers: new_peers, stats: new_stats}}
        end
    end
  end

  def handle_cast({:update_reachability, node_id, transport, info}, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        # Peer not tracked yet — also update TrustGroupDirectory directly
        notify_trust_group_directory_reachability(node_id, transport, info)
        {:noreply, state}

      peer ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        reach = Map.get(peer, :reachability, %{
          ble: %{last_seen: nil, confidence: 0, rssi: nil},
          wifi: %{last_seen: nil, confidence: 0, ip: nil},
          lora: %{last_seen: nil, confidence: 0, via: nil},
          internet: %{last_seen: nil, confidence: 0}
        })

        current_transport = Map.get(reach, transport, %{})
        updated_transport = Map.merge(current_transport, %{
          last_seen: now,
          confidence: Map.get(info, :confidence, Map.get(current_transport, :confidence, 0))
        })
        |> maybe_put_reach(:rssi, Map.get(info, :rssi))
        |> maybe_put_reach(:ip, Map.get(info, :ip))
        |> maybe_put_reach(:via, Map.get(info, :via))

        new_reach = Map.put(reach, transport, updated_transport)
        updated_peer = %{peer | reachability: new_reach, last_seen: System.system_time(:millisecond)}

        # Also update the primary transport field based on best reachability
        updated_peer = update_primary_transport(updated_peer)

        new_peers = Map.put(state.peers, node_id, updated_peer)

        # Propagate to TrustGroupDirectory
        notify_trust_group_directory_reachability(node_id, transport, info)

        {:noreply, %{state | peers: new_peers}}
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
    # Return entire peer map (used by WFS Router for routing table)
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
  def handle_call(:get_highest_priority_peer, _from, state) do
    # Find the peer with the highest hosting_priority
    case Map.values(state.peers) do
      [] ->
        {:reply, {:error, :no_peers}, state}

      peers ->
        highest = Enum.max_by(peers, fn p -> Map.get(p, :hosting_priority, 0) end)
        {:reply, {:ok, highest}, state}
    end
  end

  @impl true
  def handle_call(:get_max_peer_priority, _from, state) do
    # Get the maximum hosting_priority among all peers
    max_priority = state.peers
      |> Map.values()
      |> Enum.map(fn p -> Map.get(p, :hosting_priority, 0) end)
      |> Enum.max(fn -> 0 end)

    {:reply, max_priority, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Trust Group-Aware Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call(:get_trust_group_peers, _from, state) do
    # Filter to peers in the same Trust Group (verified)
    trust_group_peers = state.peers
      |> Enum.filter(fn {_id, peer} -> peer.is_same_trust_group and peer.trust_group_verified end)
      |> Map.new()

    {:reply, trust_group_peers, state}
  end

  @impl true
  def handle_call(:get_foreign_peers, _from, state) do
    # Filter to peers NOT in the same Trust Group
    foreign_peers = state.peers
      |> Enum.filter(fn {_id, peer} -> not peer.is_same_trust_group end)
      |> Map.new()

    {:reply, foreign_peers, state}
  end

  @impl true
  def handle_call({:get_peers_by_trust_group, trust_group_id}, _from, state) do
    # Filter to peers belonging to a specific Trust Group
    matching_peers = state.peers
      |> Enum.filter(fn {_id, peer} -> peer.trust_group_id == trust_group_id end)
      |> Map.new()

    {:reply, matching_peers, state}
  end

  @impl true
  def handle_call({:update_trust_group_info, node_id, trust_group_info}, _from, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      peer ->
        # Extract trust group info
        trust_group_id = Map.get(trust_group_info, :trust_group_id)
        trust_group_public_key_b64 = Map.get(trust_group_info, :trust_group_public_key)
        node_cert = Map.get(trust_group_info, :node_cert)

        # Decode public key if provided
        trust_group_public_key = case trust_group_public_key_b64 do
          nil -> nil
          b64 when is_binary(b64) ->
            case Base.decode64(b64) do
              {:ok, key} -> key
              _ -> nil
            end
          key when is_binary(key) -> key  # Already decoded
        end

        # Get our own Trust Group ID to check if same Trust Group
        our_trust_group_id = case Reality2Transnet.TrustGroup.get_trust_group_id() do
          {:ok, id} -> id
          _ -> nil
        end

        is_same_trust_group = trust_group_id != nil and trust_group_id == our_trust_group_id

        # Verify certificate if provided
        {trust_group_verified, verified_cert} = if node_cert && trust_group_public_key do
          case Reality2Transnet.TrustGroup.verify_node_cert(node_cert, trust_group_public_key) do
            {:ok, _cert_data} ->
              Logger.debug("#{log_prefix()} Verified Trust Group certificate for peer #{String.slice(node_id, 0..7)}...")
              {true, node_cert}
            {:error, reason} ->
              Logger.warning("#{log_prefix()} Invalid certificate for peer #{String.slice(node_id, 0..7)}...: #{inspect(reason)}")
              {false, nil}
          end
        else
          # No cert to verify - mark as unverified
          {false, nil}
        end

        # Update peer with Trust Group info
        updated_peer = %{peer |
          trust_group_id: trust_group_id,
          trust_group_public_key: trust_group_public_key,
          node_cert: verified_cert,
          is_same_trust_group: is_same_trust_group,
          trust_group_verified: trust_group_verified,
          last_seen: System.system_time(:millisecond)
        }

        new_peers = Map.put(state.peers, node_id, updated_peer)

        if is_same_trust_group and trust_group_verified do
          Logger.info("#{log_prefix()} Peer #{String.slice(node_id, 0..7)}... joined our Trust Group (verified)")
        end

        {:reply, :ok, %{state | peers: new_peers}}
    end
  end

  def handle_call({:best_transport, node_id}, _from, state) do
    case Map.get(state.peers, node_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      peer ->
        reach = Map.get(peer, :reachability, %{})
        best = [:wifi, :internet, :ble, :lora]
        |> Enum.map(fn t -> {t, Map.get(reach, t, %{})} end)
        |> Enum.map(fn {t, info} -> {t, info, Map.get(info, :confidence, 0)} end)
        |> Enum.filter(fn {_, _, conf} -> conf >= 5 end)
        |> Enum.sort_by(fn {_, _, conf} -> conf end, :desc)

        case best do
          [] -> {:reply, {:error, :unreachable}, state}
          [{transport, info, _} | _] -> {:reply, {:ok, transport, info}, state}
        end
    end
  end

  def handle_call({:get_reachability, node_id}, _from, state) do
    case Map.get(state.peers, node_id) do
      nil -> {:reply, {:error, :not_found}, state}
      peer -> {:reply, {:ok, Map.get(peer, :reachability, %{})}, state}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Cleanup Handler
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info(:cleanup_stale_peers, state) do
    # Periodic cleanup task (runs every @cleanup_interval_ms)
    # Removes peers that haven't been seen for @peer_timeout_ms
    # Protected peers (WiFi/exchanged) get a longer timeout before removal
    now = System.system_time(:millisecond)
    cutoff = now - @peer_timeout_ms
    protected_cutoff = now - @protected_peer_timeout_ms

    # Split peers into stale (timeout) and fresh (active)
    # Protected peers (WiFi or sentant-exchanged) use longer timeout
    {stale_peers, fresh_peers} =
      Enum.split_with(state.peers, fn {_id, peer} ->
        is_protected = peer.transport == :wifi_hotspot ||
                       peer.connection_state == :sentants_exchanged

        if is_protected do
          peer.last_seen < protected_cutoff
        else
          peer.last_seen < cutoff
        end
      end)

    # Log each removal, emit event, and clean up WFS_NodeNames mapping
    Enum.each(stale_peers, fn {node_id, peer} ->
      Logger.info("#{log_prefix()} Removing stale peer: #{String.slice(node_id, 0..7)}... (timeout)")

      # Emit __internal event for monitor sentant to trigger webapp refresh
      if Code.ensure_loaded?(Reality2.Sentants) do
        Reality2.Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            event: "mesh_peer_disconnected",
            peer_id: node_id,
            peer_name: peer.node_name || "Unknown"
          }
        })
      end

      if peer.node_name do
        Reality2.Metadata.delete(:WFS_NodeNames, peer.node_name)
      end
    end)

    new_peers = Map.new(fresh_peers)
    new_stats = Map.update!(state.stats, :total_removed, &(&1 + length(stale_peers)))

    # Notify WFS Router if any peers were removed
    # This removes routes to Sentants on timed-out peers
    if length(stale_peers) > 0 and Code.ensure_loaded?(Reality2Wfs.Router) do
      Reality2Wfs.Router.refresh_topology()
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

  defp maybe_put_reach(map, _key, nil), do: map
  defp maybe_put_reach(map, key, value), do: Map.put(map, key, value)

  defp update_primary_transport(peer) do
    reach = Map.get(peer, :reachability, %{})
    wifi_conf = get_in(reach, [:wifi, :confidence]) || 0
    ble_conf = get_in(reach, [:ble, :confidence]) || 0
    lora_conf = get_in(reach, [:lora, :confidence]) || 0

    best_transport = cond do
      wifi_conf >= 100 -> :wifi_hotspot
      ble_conf >= 50 -> :ble_gatt
      lora_conf >= 50 -> :lora
      true -> peer.transport  # Keep current
    end

    %{peer | transport: best_transport}
  end

  defp notify_trust_group_directory_reachability(node_id, transport, info) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroupDirectory) and
       Process.whereis(Reality2Transnet.TrustGroupDirectory) != nil do
      Reality2Transnet.TrustGroupDirectory.update_reachability(node_id, transport, info)
    end
  end

  # RSSI thresholds for proximity detection
  # Very close: RSSI > -50 (within ~1 meter)
  @proximity_rssi_threshold -50

  # Trigger proximity prompt for key holders when a very close device is detected
  defp maybe_trigger_proximity_prompt(node_id, peer) do
    rssi = peer.rssi

    # Only prompt if RSSI indicates very close proximity
    if rssi && rssi > @proximity_rssi_threshold do
      # Check if this node is a key holder (only key holders can approve joins)
      if Code.ensure_loaded?(Reality2Transnet.TrustGroup) and
         function_exported?(Reality2Transnet.TrustGroup, :is_key_holder?, 0) do
        case Reality2Transnet.TrustGroup.is_key_holder?() do
          true ->
            Logger.info("#{log_prefix()} Proximity prompt: #{peer.node_name || node_id} is very close (RSSI: #{rssi})")

            # Broadcast proximity event to UI via PubSub
            Phoenix.PubSub.broadcast(Reality2.PubSub, "trust_group:proximity", {
              :proximity_device_detected, node_id, %{
                node_id: node_id,
                node_name: peer.node_name,
                rssi: rssi,
                proximity: :very_close,
                timestamp: System.system_time(:second)
              }
            })

          _ ->
            :ok  # Not a key holder, skip prompt
        end
      end
    end
  end
end
