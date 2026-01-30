defmodule AiReality2Transnet.ConnectionManager do
  @moduledoc """
  Manages WiFi hotspot connections for Reality2 Transient Networks.

  This module implements the connection state machine for the hotspot-based
  mobility model, replacing the previous mesh upgrade logic.

  ## State Machine

  ```
  ┌─────────────┐
  │ Disconnected│◄──────────────┐
  └──────┬──────┘               │
         │                      │
         │ connect_to_host()    │ disconnect()
         │                      │
         ▼                      │
  ┌─────────────┐               │
  │ Connecting  ├───────────────┤
  └──────┬──────┘    failed     │
         │                      │
         │ IP assigned          │
         │                      │
         ▼                      │
  ┌───────────────────┐         │
  │ Connected_As_Client├─────────┤
  └────────┬──────────┘         │
           │                    │
           │ handover_to()      │
           │                    │
           ▼                    │
  ┌──────────────────┐          │
  │ Handover_Progress├──────────┘
  └──────────────────┘

  Parallel State (for hosts):
  ┌─────────────┐
  │ Hosting_AP  │  (can coexist with connected_as_client)
  └─────────────┘
  ```

  ## Roles

  **As Client (Mobile Node)**:
  - Connects to one hotspot host at a time
  - Continuously assesses connection quality
  - Performs handover when better host available
  - Re-sends sentantAll after handover

  **As Host (Fixed Anchor / Good Upstream)**:
  - Runs WPA2-PSK hotspot
  - Accepts multiple client connections
  - Advertises availability in beacon
  - Provides HTTP server for sentantAll

  ## Usage

  ```elixir
  # Connect to a host
  {:ok, state} = ConnectionManager.connect_to_host(peer_id, join_offer)

  # Check connection status
  {:ok, status} = ConnectionManager.get_connection_status()
  # => %{state: :connected_as_client, host_peer_id: "...", ...}

  # Handover to better host
  :ok = ConnectionManager.handover_to(new_peer_id, new_join_offer)

  # Start hosting (for anchors)
  {:ok, hotspot_config} = ConnectionManager.start_hosting()
  ```

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  alias AiReality2Transnet.{Wifi, PeerManager}

  # Helper to get node name for log messages
  defp log_prefix, do: "[ConnectionManager:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Type Definitions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc """
  Connection state machine states.
  """
  @type connection_state ::
          :disconnected
          | :connecting
          | :connected_as_client
          | :hosting_ap
          | :handover_in_progress

  @typedoc """
  Join offer received from potential host via GATT.
  """
  @type join_offer :: %{
          ssid: String.t(),
          psk: String.t(),
          channel: integer(),
          rendezvous_ip: String.t(),
          rendezvous_port: integer(),
          offer_expiry: integer(),
          host_node_id: String.t()
        }

  @typedoc """
  Hotspot configuration when acting as host.
  """
  @type hotspot_config :: %{
          ssid: String.t(),
          psk: String.t(),
          channel: integer(),
          ip_address: String.t(),
          port: integer(),
          active: boolean()
        }

  # Cooldown period after a failed handover to prevent thrashing (30 seconds)
  @handover_cooldown_ms 30_000

  # Hotspot health check settings - aggressive for wearable responsiveness
  @hotspot_health_check_interval_ms 15_000  # Check every 15 seconds
  @max_hotspot_restart_attempts 3

  # WiFi connection verification - detect external disconnects
  @wifi_verification_interval_ms 10_000  # Check every 10 seconds

  # Host reachability check - detect when connected but host is unreachable
  @host_reachability_check_interval_ms 30_000  # Check every 30 seconds
  @max_unreachable_count 2  # Disconnect after 2 consecutive failures

  @typedoc """
  Connection manager state.
  """
  @type state :: %{
          # Connection state
          connection_state: connection_state(),

          # Client mode state (when connected to a host)
          current_host_peer_id: String.t() | nil,
          current_host_ssid: String.t() | nil,
          current_host_ip: String.t() | nil,
          connected_at: integer() | nil,
          last_sentant_exchange: integer() | nil,

          # Handover cooldown tracking
          last_handover_failed_at: integer() | nil,

          # Host mode state (when hosting hotspot)
          hosting_config: hotspot_config() | nil,
          connected_clients: [String.t()],

          # WiFi adapter info
          wifi_interface: String.t() | nil,

          # Statistics
          stats: %{
            connections_made: integer(),
            handovers_completed: integer(),
            handovers_failed: integer(),
            hosting_sessions: integer()
          }
        }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Connects to a hotspot host as a client.

  ## Parameters
  - `peer_id` - UUID of the host node
  - `join_offer` - Join offer received via GATT

  ## Returns
  - `{:ok, connection_info}` - Successfully connected
  - `{:error, reason}` - Failed to connect

  ## Example

      join_offer = %{
        ssid: "R2-abc123",
        psk: "secure_password",
        channel: 6,
        rendezvous_ip: "192.168.42.1",
        rendezvous_port: 4005,
        offer_expiry: System.system_time(:second) + 300,
        host_node_id: "host-uuid"
      }

      {:ok, _info} = ConnectionManager.connect_to_host(peer_id, join_offer)
  """
  @spec connect_to_host(String.t(), join_offer()) ::
          {:ok, map()} | {:error, String.t()}
  def connect_to_host(peer_id, join_offer) do
    GenServer.call(__MODULE__, {:connect_to_host, peer_id, join_offer}, 30_000)
  end

  @doc """
  Disconnects from the current host.

  ## Returns
  - `:ok` - Disconnected successfully
  - `{:error, reason}` - Failed to disconnect
  """
  @spec disconnect_from_current_host() :: :ok | {:error, String.t()}
  def disconnect_from_current_host do
    GenServer.call(__MODULE__, :disconnect)
  end

  @doc """
  Performs a handover from current host to a new host.

  This is a seamless transition that:
  1. Connects to new host
  2. Performs sentantAll exchange
  3. Updates routing table
  4. Disconnects from old host

  ## Parameters
  - `new_peer_id` - UUID of new host
  - `new_join_offer` - Join offer for new host

  ## Returns
  - `:ok` - Handover completed
  - `{:error, reason}` - Handover failed (stays on current host)
  """
  @spec handover_to(String.t(), join_offer()) :: :ok | {:error, String.t()}
  def handover_to(new_peer_id, new_join_offer) do
    GenServer.call(__MODULE__, {:handover, new_peer_id, new_join_offer}, 30_000)
  end

  @doc """
  Starts hosting a WiFi hotspot.

  Generates credentials and starts WPA2-PSK hotspot that other nodes can connect to.

  ## Returns
  - `{:ok, hotspot_config}` - Hotspot started
  - `{:error, reason}` - Failed to start

  ## Example

      {:ok, config} = ConnectionManager.start_hosting()
      # => %{ssid: "R2-abc123", psk: "...", ip_address: "192.168.42.1", ...}
  """
  @spec start_hosting() :: {:ok, hotspot_config()} | {:error, String.t()}
  def start_hosting do
    GenServer.call(__MODULE__, :start_hosting, 30_000)
  end

  @doc """
  Stops hosting the WiFi hotspot.

  ## Returns
  - `:ok` - Hotspot stopped
  - `{:error, reason}` - Failed to stop
  """
  @spec stop_hosting() :: :ok | {:error, String.t()}
  def stop_hosting do
    GenServer.call(__MODULE__, :stop_hosting)
  end

  @doc """
  Gets the current connection status.

  ## Returns
  - `{:ok, status}` - Current status
  - `{:error, reason}` - Failed to get status

  ## Example

      {:ok, status} = ConnectionManager.get_connection_status()
      # => %{
      #   state: :connected_as_client,
      #   host_peer_id: "host-uuid",
      #   host_ip: "192.168.42.1",
      #   signal_strength: -45,
      #   hosting: false
      # }
  """
  @spec get_connection_status() :: {:ok, map()} | {:error, String.t()}
  def get_connection_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets the current hotspot configuration if hosting.

  ## Returns
  - `{:ok, hotspot_config}` - Currently hosting
  - `{:error, :not_hosting}` - Not hosting
  """
  @spec get_hosting_config() :: {:ok, hotspot_config()} | {:error, :not_hosting}
  def get_hosting_config do
    GenServer.call(__MODULE__, :get_hosting_config)
  end

  @doc """
  Refreshes remote sentants by re-querying the host.

  When connected as a client, this will query the host's sentantAll endpoint
  to get updated sentants (including any newly registered clients).

  ## Returns
  - `:ok` - Refresh initiated
  - `{:error, reason}` - Not connected or refresh failed
  """
  @spec refresh_remote_sentants() :: :ok | {:error, String.t()}
  def refresh_remote_sentants do
    GenServer.call(__MODULE__, :refresh_remote_sentants, 15_000)
  end

  @doc """
  Gets comprehensive health metrics for monitoring and debugging.

  ## Returns
  - `{:ok, metrics}` - Health metrics map

  ## Example

      {:ok, metrics} = ConnectionManager.get_health_metrics()
      # => %{
      #   uptime_ms: 3600000,
      #   connection_state: :connected_as_client,
      #   connections_made: 5,
      #   connections_lost: 2,
      #   handovers_completed: 1,
      #   handovers_failed: 0,
      #   ...
      # }
  """
  @spec get_health_metrics() :: {:ok, map()}
  def get_health_metrics do
    GenServer.call(__MODULE__, :get_health_metrics)
  end

  @doc """
  Reports that WiFi connection to an R2 hotspot was established externally.

  Called by ConnectionAssessor when it successfully connects to an R2 hotspot
  during auto-discovery. Updates internal state to reflect the connection.

  ## Parameters
  - `ssid` - SSID of the connected hotspot

  ## Returns
  - `:ok` - State updated
  """
  @spec report_wifi_connected(String.t()) :: :ok
  def report_wifi_connected(ssid) do
    GenServer.cast(__MODULE__, {:wifi_connected, ssid})
  end

  @doc """
  Register a connected client (called by MeshController when client registers).

  ## Parameters
  - `node_id` - UUID of the client node
  - `node_name` - Human-readable name of the client
  - `client_ip` - IP address of the client

  ## Returns
  - `:ok`
  """
  @spec register_connected_client(String.t(), String.t(), String.t()) :: :ok
  def register_connected_client(node_id, node_name, client_ip) do
    GenServer.cast(__MODULE__, {:register_client, node_id, node_name, client_ip})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Find WiFi adapter on system (e.g., wlan0, wlp2s0)
    # Returns nil if no WiFi adapter available (gracefully degrades to BLE-only mode)
    wifi_interface = find_wifi_interface()

    state = %{
      # Connection state machine
      connection_state: :disconnected,

      # Client mode state (when connected to a host)
      current_host_peer_id: nil,
      current_host_ssid: nil,
      current_host_ip: nil,
      connected_at: nil,
      last_sentant_exchange: nil,

      # Handover cooldown tracking
      last_handover_failed_at: nil,

      # Host mode state (when hosting hotspot)
      hosting_config: nil,
      connected_clients: [],

      # System info
      wifi_interface: wifi_interface,

      # Statistics for monitoring
      stats: %{
        connections_made: 0,
        connections_lost: 0,
        handovers_completed: 0,
        handovers_failed: 0,
        hosting_sessions: 0,
        registration_attempts: 0,
        registration_successes: 0,
        sentant_exchanges: 0,
        host_unreachable_events: 0,
        wifi_disconnects_detected: 0,
        hotspot_recoveries: 0,
        started_at: System.system_time(:millisecond)
      },

      # Hotspot health check state
      hotspot_restart_attempts: 0,

      # Host reachability tracking
      host_unreachable_count: 0
    }

    # Subscribe to sentants topic to detect local sentant changes
    Phoenix.PubSub.subscribe(Reality2.PubSub, "sentants")

    # Schedule hotspot health check
    Process.send_after(self(), :hotspot_health_check, @hotspot_health_check_interval_ms)

    # Schedule WiFi connection verification
    Process.send_after(self(), :verify_wifi_connection, @wifi_verification_interval_ms)

    # Schedule host reachability check
    Process.send_after(self(), :check_host_reachability, @host_reachability_check_interval_ms)

    # Check for existing R2 hotspot connection at startup (delayed to allow system to settle)
    Process.send_after(self(), :check_existing_r2_connection, 10_000)

    Logger.info("#{log_prefix()} Started - WiFi interface: #{wifi_interface || "none"}")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean shutdown: disconnect from networks and stop hosting
    # This ensures WiFi adapters are left in a clean state

    # Disconnect from host if connected as client
    if state.connection_state == :connected_as_client && state.wifi_interface do
      Wifi.disconnect_from_network(state.wifi_interface)
    end

    # Stop hotspot if hosting
    if state.hosting_config && state.hosting_config.active && state.wifi_interface do
      Wifi.stop_hotspot(state.wifi_interface)
    end

    :ok
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call({:connect_to_host, peer_id, join_offer}, _from, state) do
    # State machine: Only allow connections when disconnected
    # If already connected, caller must use handover_to/2 for seamless transition
    case state.connection_state do
      :disconnected ->
        # Valid state transition: :disconnected → :connecting → :connected_as_client
        perform_connection(peer_id, join_offer, state)

      :connected_as_client ->
        # Already connected to a host - must use handover for seamless transition
        {:reply, {:error, "already_connected - use handover_to/2 instead"}, state}

      :connecting ->
        # Connection already in progress - reject concurrent connection attempts
        {:reply, {:error, "connection_in_progress"}, state}

      :handover_in_progress ->
        # Handover in progress - reject concurrent operations
        {:reply, {:error, "handover_in_progress"}, state}

      _ ->
        {:reply, {:error, "invalid_state"}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    # Disconnect from current host (if connected)
    case state.connection_state do
      :connected_as_client ->
        # Perform WiFi disconnection and clean up state
        perform_disconnection(state)

      :disconnected ->
        # Already disconnected - return success (idempotent)
        {:reply, :ok, state}

      _ ->
        # Not in a state where disconnect makes sense
        {:reply, {:error, "not_connected"}, state}
    end
  end

  @impl true
  def handle_call({:handover, new_peer_id, new_join_offer}, _from, state) do
    # Seamless handover: connect to new host while maintaining connectivity
    # Performs: new connection → sentantAll exchange → disconnect from old host
    case state.connection_state do
      :connected_as_client ->
        # Check if we're in cooldown period after a recent failed handover
        if handover_in_cooldown?(state) do
          cooldown_remaining = @handover_cooldown_ms - (System.system_time(:millisecond) - state.last_handover_failed_at)
          Logger.warning("#{log_prefix()} Handover rejected - in cooldown period (#{div(cooldown_remaining, 1000)}s remaining)")
          {:reply, {:error, "handover_cooldown_active"}, state}
        else
          # Only allow handover when actively connected to a host
          perform_handover(new_peer_id, new_join_offer, state)
        end

      _ ->
        # Can't handover if not connected - must use connect_to_host instead
        {:reply, {:error, "not_connected - cannot handover"}, state}
    end
  end

  @impl true
  def handle_call(:start_hosting, _from, state) do
    # Start WiFi hotspot (anchor/gateway role)
    # Generates credentials and configures WPA2-PSK access point
    if state.wifi_interface do
      perform_start_hosting(state)
    else
      # No WiFi adapter available - can't host
      {:reply, {:error, "no_wifi_interface_available"}, state}
    end
  end

  @impl true
  def handle_call(:stop_hosting, _from, state) do
    # Stop WiFi hotspot (clean shutdown)
    if state.hosting_config && state.hosting_config.active do
      perform_stop_hosting(state)
    else
      # Not currently hosting
      {:reply, {:error, "not_hosting"}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    # Return comprehensive connection status for monitoring/debugging
    # Includes signal strength, connection info, hosting status, and stats

    # Query WiFi signal strength if connected as client
    signal_strength =
      if state.connection_state == :connected_as_client && state.wifi_interface do
        case Wifi.get_connection_status(state.wifi_interface) do
          {:ok, wifi_status} -> wifi_status.signal_strength
          _ -> nil
        end
      end

    # Build status map with all connection state
    status = %{
      state: state.connection_state,
      host_peer_id: state.current_host_peer_id,
      host_ssid: state.current_host_ssid,
      host_ip: state.current_host_ip,
      connected_at: state.connected_at,
      last_sentant_exchange: state.last_sentant_exchange,
      signal_strength: signal_strength,
      hosting: state.hosting_config != nil && state.hosting_config.active,
      hosting_config: state.hosting_config,
      connected_clients: state.connected_clients,  # Full list for push notifications
      connected_clients_count: length(state.connected_clients),
      wifi_interface: state.wifi_interface,
      stats: state.stats
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:get_hosting_config, _from, state) do
    # Return hotspot credentials if currently hosting
    # Used by BLE GATT to generate join offers for clients
    if state.hosting_config && state.hosting_config.active do
      {:reply, {:ok, state.hosting_config}, state}
    else
      {:reply, {:error, :not_hosting}, state}
    end
  end

  @impl true
  def handle_call(:get_health_metrics, _from, state) do
    now = System.system_time(:millisecond)
    started_at = Map.get(state.stats, :started_at, now)
    uptime_ms = now - started_at

    # Compute connection duration if connected
    connection_duration_ms = if state.connected_at do
      now - state.connected_at
    else
      nil
    end

    # Build comprehensive health metrics
    metrics = %{
      # Runtime
      uptime_ms: uptime_ms,
      uptime_formatted: format_duration(uptime_ms),

      # Current state
      connection_state: state.connection_state,
      connected_to_host: state.current_host_ssid,
      connection_duration_ms: connection_duration_ms,
      connected_clients_count: length(state.connected_clients),
      hosting: state.hosting_config != nil && Map.get(state.hosting_config, :active, false),

      # Health indicators
      host_unreachable_count: state.host_unreachable_count,
      hotspot_restart_attempts: state.hotspot_restart_attempts,
      last_sentant_exchange: state.last_sentant_exchange,

      # Counters from stats
      connections_made: state.stats.connections_made,
      connections_lost: Map.get(state.stats, :connections_lost, 0),
      handovers_completed: state.stats.handovers_completed,
      handovers_failed: state.stats.handovers_failed,
      hosting_sessions: state.stats.hosting_sessions,
      registration_attempts: Map.get(state.stats, :registration_attempts, 0),
      registration_successes: Map.get(state.stats, :registration_successes, 0),
      sentant_exchanges: Map.get(state.stats, :sentant_exchanges, 0),
      host_unreachable_events: Map.get(state.stats, :host_unreachable_events, 0),
      wifi_disconnects_detected: Map.get(state.stats, :wifi_disconnects_detected, 0),
      hotspot_recoveries: Map.get(state.stats, :hotspot_recoveries, 0),

      # Computed metrics
      connection_success_rate: compute_success_rate(
        state.stats.connections_made,
        Map.get(state.stats, :connections_lost, 0)
      ),
      handover_success_rate: compute_success_rate(
        state.stats.handovers_completed,
        state.stats.handovers_failed
      )
    }

    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call(:refresh_remote_sentants, _from, state) do
    # Re-query host's sentants (including other registered clients)
    case state.connection_state do
      :connected_as_client when not is_nil(state.current_host_ip) ->
        Logger.info("#{log_prefix()} Refreshing remote sentants from host #{state.current_host_ip}")

        # Get the host's node_id from PeerManager if we have it
        host_node_id = state.current_host_peer_id || "host"

        case do_refresh_sentants(host_node_id, state.current_host_ip, 4005) do
          {:ok, count} ->
            new_state = %{state | last_sentant_exchange: System.system_time(:millisecond)}
            {:reply, {:ok, count}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      :hosting_ap ->
        {:reply, {:error, "cannot_refresh_when_hosting"}, state}

      _ ->
        {:reply, {:error, "not_connected"}, state}
    end
  end

  @impl true
  def handle_cast({:wifi_connected, ssid}, state) do
    # External notification that WiFi was connected (e.g., by ConnectionAssessor auto-discovery)
    Logger.info("#{log_prefix()} WiFi connection reported: #{ssid}")

    # Get the gateway IP (the hotspot host's IP) - needed for re-registration on sentant changes
    host_ip = case get_gateway_ip() do
      {:ok, ip} -> ip
      {:error, _} -> nil
    end

    new_state = %{state |
      connection_state: :connected_as_client,
      current_host_ssid: ssid,
      current_host_ip: host_ip,
      connected_at: System.system_time(:millisecond),
      stats: Map.update!(state.stats, :connections_made, &(&1 + 1))
    }

    if host_ip do
      Logger.info("#{log_prefix()} Host IP: #{host_ip}")
    else
      Logger.warning("#{log_prefix()} Could not determine host IP - re-registration on sentant changes will fail")
    end

    # Find the peer by SSID (the SSID is the node_name)
    # and perform sentantAll exchange
    Task.start(fn ->
      try do
        perform_sentant_exchange_by_ssid(ssid)
      rescue
        e ->
          Logger.error("#{log_prefix()} Sentant exchange crashed: #{Exception.message(e)}")
          Logger.error("#{log_prefix()} Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
      catch
        kind, reason ->
          Logger.error("#{log_prefix()} Sentant exchange failed: #{kind} - #{inspect(reason)}")
      end
    end)

    {:noreply, new_state}
  end

  # Update host peer ID (called after successful exchange in auto-discovery flow)
  @impl true
  def handle_cast({:set_host_peer_id, peer_node_id}, state) do
    Logger.debug("#{log_prefix()} Setting host peer ID: #{String.slice(peer_node_id, 0..7)}...")
    {:noreply, %{state | current_host_peer_id: peer_node_id}}
  end

  # Handle client registration (from MeshController)
  @impl true
  def handle_cast({:register_client, node_id, node_name, client_ip}, state) do
    Logger.info("#{log_prefix()} Client registered: #{node_name} (#{String.slice(node_id, 0..7)}...) at #{client_ip}")

    # Add or update client in connected_clients list
    client_info = %{node_id: node_id, node_name: node_name, ip: client_ip, registered_at: System.system_time(:millisecond)}
    updated_clients = state.connected_clients
      |> Enum.reject(fn c -> c.node_id == node_id end)  # Remove old entry if exists
      |> Kernel.++([client_info])  # Add new entry

    {:noreply, %{state | connected_clients: updated_clients}}
  end

  # Handle local sentant creation - re-register with host if connected as client
  @impl true
  def handle_info({:sentants, :created, %{id: id, name: name}}, state) do
    Logger.debug("#{log_prefix()} Local sentant created: #{name} (#{String.slice(id, 0..7)}...)")
    handle_sentant_change(state)
  end

  @impl true
  def handle_info({:sentants, :updated, %{id: id, name: name}}, state) do
    Logger.debug("#{log_prefix()} Local sentant updated: #{name} (#{String.slice(id, 0..7)}...)")
    handle_sentant_change(state)
  end

  @impl true
  def handle_info({:sentants, :deleted, %{id: id}}, state) do
    Logger.debug("#{log_prefix()} Local sentant deleted: #{String.slice(id, 0..7)}...")
    handle_sentant_change(state)
  end

  # Catch-all for other sentant events
  @impl true
  def handle_info({:sentants, _event, _data}, state) do
    {:noreply, state}
  end

  # Hotspot health check - detect when state says hosting but hotspot died
  @impl true
  def handle_info(:hotspot_health_check, state) do
    state = check_hotspot_health(state)
    # Schedule next health check
    Process.send_after(self(), :hotspot_health_check, @hotspot_health_check_interval_ms)
    {:noreply, state}
  end

  # WiFi connection verification - detect external disconnects
  @impl true
  def handle_info(:verify_wifi_connection, state) do
    state = verify_wifi_connection(state)
    # Schedule next verification
    Process.send_after(self(), :verify_wifi_connection, @wifi_verification_interval_ms)
    {:noreply, state}
  end

  # Host reachability check - detect when WiFi is connected but host is unreachable
  @impl true
  def handle_info(:check_host_reachability, state) do
    state = check_host_reachability(state)
    # Schedule next check
    Process.send_after(self(), :check_host_reachability, @host_reachability_check_interval_ms)
    {:noreply, state}
  end

  # Check for existing R2 hotspot connection at startup
  # This handles the case where WiFi was already connected to an R2 hotspot before this node started
  @impl true
  def handle_info(:check_existing_r2_connection, %{connection_state: :disconnected} = state) do
    Logger.info("#{log_prefix()} Checking for existing R2 hotspot connection...")

    case state.wifi_interface do
      nil ->
        Logger.debug("#{log_prefix()} No WiFi interface available")
        {:noreply, state}

      interface ->
        case Wifi.get_connection_status(interface) do
          {:ok, %{state: :connected, ssid: ssid}} when is_binary(ssid) ->
            # Check if connected to an R2 hotspot (SSID starts with R2Node_ or R2-)
            if String.starts_with?(ssid, "R2Node_") or String.starts_with?(ssid, "R2-") do
              Logger.info("#{log_prefix()} Found existing R2 hotspot connection: #{ssid}")
              # Trigger the same flow as if we just connected
              report_wifi_connected(ssid)
            else
              Logger.debug("#{log_prefix()} Connected to non-R2 network: #{ssid}")
            end
            {:noreply, state}

          {:ok, %{state: conn_state}} when conn_state in [:disconnected, :connecting] ->
            Logger.debug("#{log_prefix()} WiFi state: #{conn_state}")
            {:noreply, state}

          {:ok, _status} ->
            Logger.debug("#{log_prefix()} Not connected to any R2 WiFi network")
            {:noreply, state}

          {:error, reason} ->
            Logger.debug("#{log_prefix()} Could not check WiFi status: #{inspect(reason)}")
            {:noreply, state}
        end
    end
  end

  # If not in disconnected state, we're already handling the connection
  @impl true
  def handle_info(:check_existing_r2_connection, state) do
    Logger.debug("#{log_prefix()} Already in state #{state.connection_state}, skipping R2 hotspot check")
    {:noreply, state}
  end

  defp handle_sentant_change(state) do
    case state.connection_state do
      :connected_as_client ->
        # We're connected to a host - re-register our sentants
        if state.current_host_ip do
          Task.start(fn ->
            Logger.info("#{log_prefix()} Re-registering sentants with host after local change")
            register_with_host(state.current_host_ip, 4005)
          end)
        end

      :hosting_ap ->
        # We're hosting - notify connected clients
        # Clients will need to re-query us or we push to them
        notify_clients_of_sentant_change(state)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  defp notify_clients_of_sentant_change(state) do
    # Notify PNS router if available
    if Code.ensure_loaded?(AiReality2Pns.Router) and function_exported?(AiReality2Pns.Router, :refresh_topology, 0) do
      apply(AiReality2Pns.Router, :refresh_topology, [])
    end

    # Push updated sentants to all connected clients
    if length(state.connected_clients) > 0 do
      my_node_id = Reality2.Bootstrap.get(:node_id)
      my_node_name = Reality2.Bootstrap.get(:node_name)
      my_sentants = get_local_sentants()

      Logger.info("#{log_prefix()} Pushing #{length(my_sentants)} sentants to #{length(state.connected_clients)} connected client(s)")

      Enum.each(state.connected_clients, fn client ->
        Task.start(fn ->
          push_sentants_to_client(client.ip, my_node_id, my_node_name, my_sentants)
        end)
      end)
    else
      Logger.debug("#{log_prefix()} Host sentant change - no connected clients to notify")
    end

    :ok
  end

  defp push_sentants_to_client(client_ip, my_node_id, my_node_name, my_sentants) do
    register_request = %{
      node_id: my_node_id,
      node_name: my_node_name,
      sentants: my_sentants
    }

    url = "https://#{client_ip}:4005/mesh/register"
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(register_request)

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200}} ->
        Logger.debug("#{log_prefix()} Successfully pushed sentants to client #{client_ip}")

      {:ok, %Finch.Response{status: status}} ->
        Logger.warning("#{log_prefix()} Push to client #{client_ip} returned status #{status}")

      {:error, reason} ->
        Logger.warning("#{log_prefix()} Failed to push to client #{client_ip}: #{inspect(reason)}")
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Connection Operations
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp perform_connection(peer_id, join_offer, state) do
    Logger.info("#{log_prefix()} Connecting to host: #{String.slice(peer_id, 0..7)}...")

    # Transition to :connecting state
    new_state = %{state | connection_state: :connecting}

    # Validate join offer hasn't expired
    # Offers typically expire 5 minutes after creation
    now = System.system_time(:second)
    if join_offer.offer_expiry < now do
      Logger.error("#{log_prefix()} Join offer expired")
      {:reply, {:error, "offer_expired"}, %{new_state | connection_state: :disconnected}}
    else
      # Step 1: Connect to WiFi hotspot using WPA2-PSK credentials
      case Wifi.connect_to_network(state.wifi_interface, join_offer.ssid, join_offer.psk) do
        {:ok, _connection_uuid} ->
          # Step 2: Wait for DHCP to assign IP address
          case Wifi.get_interface_ip(state.wifi_interface) do
            {:ok, my_ip} ->
              Logger.info("#{log_prefix()} Connected - IP: #{my_ip}")

              # Step 3: Set transport BEFORE sentant exchange so sentants are associated correctly
              PeerManager.update_peer_transport(peer_id, :wifi_hotspot)

              # Step 4: Exchange Sentant directories via GraphQL
              # This populates PNS routing table with host's available Sentants
              case perform_sentant_exchange(peer_id, join_offer.rendezvous_ip, join_offer.rendezvous_port) do
                :ok ->
                  # Step 5: Update state to :connected_as_client
                  final_state = %{new_state |
                    connection_state: :connected_as_client,
                    current_host_peer_id: peer_id,
                    current_host_ssid: join_offer.ssid,
                    current_host_ip: join_offer.rendezvous_ip,
                    connected_at: System.system_time(:millisecond),
                    last_sentant_exchange: System.system_time(:millisecond),
                    stats: Map.update!(new_state.stats, :connections_made, &(&1 + 1))
                  }

                  # Step 6: Emit event so client webapp updates to show host's sentants
                  if Code.ensure_loaded?(Reality2.Sentants) do
                    host_name = PeerManager.get_peer(peer_id)
                      |> case do
                        {:ok, peer} -> Map.get(peer, :node_name, "Unknown")
                        _ -> "Unknown"
                      end
                    host_sentant_count = PeerManager.get_peer(peer_id)
                      |> case do
                        {:ok, peer} -> length(Map.get(peer, :sentants, []))
                        _ -> 0
                      end

                    Reality2.Sentants.sendto_all(%{
                      event: "__internal",
                      parameters: %{
                        mesh_event: "mesh_host_connected",  # Use mesh_event to avoid signal name collision
                        peer_id: peer_id,
                        peer_name: host_name,
                        sentant_count: host_sentant_count
                      }
                    })
                  end

                  connection_info = %{
                    peer_id: peer_id,
                    ssid: join_offer.ssid,
                    host_ip: join_offer.rendezvous_ip,
                    my_ip: my_ip
                  }

                  Logger.info("#{log_prefix()} Connection established and sentantAll completed")
                  {:reply, {:ok, connection_info}, final_state}

                {:error, reason} ->
                  Logger.error("#{log_prefix()} sentantAll exchange failed: #{reason}")
                  # Disconnect
                  Wifi.disconnect_from_network(state.wifi_interface)
                  {:reply, {:error, "sentant_exchange_failed: #{reason}"},
                   %{new_state | connection_state: :disconnected}}
              end

            {:error, reason} ->
              Logger.error("#{log_prefix()} Failed to get IP: #{reason}")
              Wifi.disconnect_from_network(state.wifi_interface)
              {:reply, {:error, "ip_assignment_failed: #{reason}"},
               %{new_state | connection_state: :disconnected}}
          end

        {:error, reason} ->
          Logger.error("#{log_prefix()} Connection failed: #{reason}")
          {:reply, {:error, "wifi_connect_failed: #{reason}"},
           %{new_state | connection_state: :disconnected}}
      end
    end
  end

  defp perform_disconnection(state) do
    Logger.info("#{log_prefix()} Disconnecting from host")

    case Wifi.disconnect_from_network(state.wifi_interface) do
      :ok ->
        new_state = %{state |
          connection_state: :disconnected,
          current_host_peer_id: nil,
          current_host_ssid: nil,
          current_host_ip: nil,
          connected_at: nil
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp perform_handover(new_peer_id, new_join_offer, state) do
    Logger.info("#{log_prefix()} Handover: #{String.slice(state.current_host_peer_id, 0..7)} -> #{String.slice(new_peer_id, 0..7)}")

    # Store old host info for potential rollback
    old_host_peer_id = state.current_host_peer_id
    old_host_ssid = state.current_host_ssid
    old_host_ip = state.current_host_ip

    new_state = %{state | connection_state: :handover_in_progress}

    # Connect to new host
    case Wifi.connect_to_network(state.wifi_interface, new_join_offer.ssid, new_join_offer.psk) do
      {:ok, _} ->
        # Wait for IP
        Process.sleep(2000)

        case Wifi.get_interface_ip(state.wifi_interface) do
          {:ok, _my_ip} ->
            # Perform sentantAll with new host
            case perform_sentant_exchange(new_peer_id, new_join_offer.rendezvous_ip, new_join_offer.rendezvous_port) do
              :ok ->
                final_state = %{new_state |
                  connection_state: :connected_as_client,
                  current_host_peer_id: new_peer_id,
                  current_host_ssid: new_join_offer.ssid,
                  current_host_ip: new_join_offer.rendezvous_ip,
                  connected_at: System.system_time(:millisecond),
                  last_sentant_exchange: System.system_time(:millisecond),
                  last_handover_failed_at: nil,  # Clear cooldown on success
                  stats: Map.update!(new_state.stats, :handovers_completed, &(&1 + 1))
                }

                # Update PeerManager
                PeerManager.update_peer_transport(new_peer_id, :wifi_hotspot)

                Logger.info("#{log_prefix()} Handover completed successfully")
                {:reply, :ok, final_state}

              {:error, reason} ->
                Logger.error("#{log_prefix()} Handover sentantAll failed: #{reason}")
                # Connected to new host but sentantAll failed - disconnect and set cooldown
                Wifi.disconnect_from_network(state.wifi_interface)

                {:reply, {:error, "handover_sentant_exchange_failed"},
                 %{new_state |
                   connection_state: :disconnected,
                   current_host_peer_id: nil,
                   current_host_ssid: nil,
                   current_host_ip: nil,
                   last_handover_failed_at: System.system_time(:millisecond),
                   stats: Map.update!(new_state.stats, :handovers_failed, &(&1 + 1))
                 }}
            end

          {:error, reason} ->
            Logger.error("#{log_prefix()} Handover IP assignment failed: #{reason}")
            # Connected but no IP - disconnect and set cooldown
            Wifi.disconnect_from_network(state.wifi_interface)

            {:reply, {:error, "handover_ip_failed"},
             %{new_state |
               connection_state: :disconnected,
               current_host_peer_id: nil,
               current_host_ssid: nil,
               current_host_ip: nil,
               last_handover_failed_at: System.system_time(:millisecond),
               stats: Map.update!(new_state.stats, :handovers_failed, &(&1 + 1))
             }}
        end

      {:error, reason} ->
        Logger.error("#{log_prefix()} Handover connection failed: #{reason}")
        # Connection to new host failed - restore previous state completely
        {:reply, {:error, "handover_connect_failed"},
         %{new_state |
           connection_state: :connected_as_client,
           current_host_peer_id: old_host_peer_id,
           current_host_ssid: old_host_ssid,
           current_host_ip: old_host_ip,
           last_handover_failed_at: System.system_time(:millisecond),
           stats: Map.update!(new_state.stats, :handovers_failed, &(&1 + 1))
         }}
    end
  end

  # Check if we're in handover cooldown period
  defp handover_in_cooldown?(state) do
    case state.last_handover_failed_at do
      nil -> false
      timestamp ->
        elapsed = System.system_time(:millisecond) - timestamp
        elapsed < @handover_cooldown_ms
    end
  end

  defp perform_start_hosting(state) do
    Logger.info("#{log_prefix()} Starting hotspot hosting")

    # Select the best WiFi adapter for hotspot mode
    # This intelligently chooses an adapter that preserves internet access if possible:
    # - Uses a different adapter than the one providing internet (if multi-WiFi)
    # - Uses any WiFi adapter if we have wired internet
    # - Falls back to only available adapter if necessary
    hotspot_interface = case Wifi.select_adapter_for_hotspot() do
      {:ok, %{interface: interface, preserves_internet: preserves}} ->
        Logger.info("#{log_prefix()} Selected #{interface} for hotspot (preserves internet: #{preserves})")
        interface

      {:error, reason} ->
        Logger.warning("#{log_prefix()} Could not select optimal adapter: #{reason}, using default")
        state.wifi_interface
    end

    # Generate unique credentials for this hotspot
    # SSID format: R2-<SITE_ID>-<HOST_SHORT_ID>
    # Example: R2-WAIROA-A3F7
    # Configure site_id via:
    #   Environment: export R2_SITE_ID=WAIROA
    #   Config: config :ai_reality2_transnet, site_id: "WAIROA"
    #   Default: "NODE"
    ssid = Wifi.generate_ssid()  # Uses node_name from Bootstrap
    # Use deterministic PSK so other nodes can predict credentials from SSID
    psk = Wifi.generate_psk_for_node(ssid)
    channel = 6

    case Wifi.start_hotspot(hotspot_interface, ssid, psk, channel) do
      {:ok, _uuid} ->
        # Get hotspot IP
        case Wifi.get_hotspot_ip(hotspot_interface) do
          {:ok, ip_address} ->
            hotspot_config = %{
              ssid: ssid,
              psk: psk,
              channel: channel,
              ip_address: ip_address,
              port: 4005,  # HTTP/GraphQL server port (unified with Reality2Web)
              interface: hotspot_interface,  # Store which interface is hosting
              active: true
            }

            new_state = %{state |
              hosting_config: hotspot_config,
              connection_state: :hosting_ap,
              stats: Map.update!(state.stats, :hosting_sessions, &(&1 + 1))
            }

            Logger.info("#{log_prefix()} Hotspot started: #{ssid} on #{ip_address} (#{hotspot_interface})")
            {:reply, {:ok, hotspot_config}, new_state}

          {:error, reason} ->
            Logger.error("#{log_prefix()} Failed to get hotspot IP: #{reason}")
            Wifi.stop_hotspot(hotspot_interface)
            {:reply, {:error, "hotspot_ip_failed: #{reason}"}, state}
        end

      {:error, reason} ->
        Logger.error("#{log_prefix()} Failed to start hotspot: #{reason}")
        {:reply, {:error, "hotspot_start_failed: #{reason}"}, state}
    end
  end

  defp perform_stop_hosting(state) do
    Logger.info("#{log_prefix()} Stopping hotspot hosting")

    # Use the interface stored in hosting_config (set during start_hosting)
    # Fall back to default wifi_interface if not set
    hotspot_interface = Map.get(state.hosting_config, :interface, state.wifi_interface)

    case Wifi.stop_hotspot(hotspot_interface) do
      :ok ->
        new_state = %{state |
          hosting_config: nil,
          connected_clients: [],
          connection_state: if(state.connection_state == :hosting_ap, do: :disconnected, else: state.connection_state)
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp find_wifi_interface do
    case Wifi.list_adapters() do
      {:ok, [adapter | _]} ->
        # Take first WiFi adapter
        adapter.interface

      _ ->
        Logger.warning("#{log_prefix()} No WiFi adapters found")
        nil
    end
  end

  # Check if hotspot is actually running when state says it should be
  defp check_hotspot_health(%{connection_state: :hosting_ap, hosting_config: config} = state)
       when not is_nil(config) do
    interface = Map.get(config, :interface, state.wifi_interface)
    ssid = Map.get(config, :ssid)

    case verify_hotspot_running(interface, ssid) do
      :running ->
        # Hotspot is healthy
        Logger.debug("#{log_prefix()} Hotspot health check: OK (#{ssid} on #{interface})")
        %{state | hotspot_restart_attempts: 0}

      :not_running ->
        # Hotspot died but state thinks it's hosting - try to restart
        Logger.warning("#{log_prefix()} Hotspot health check: hotspot not running but state says hosting!")
        attempt_hotspot_recovery(state)
    end
  end

  defp check_hotspot_health(state) do
    # Not hosting - nothing to check
    state
  end

  # Verify the hotspot is actually running via nmcli
  defp verify_hotspot_running(interface, expected_ssid) do
    case System.cmd("nmcli", ["-t", "-f", "NAME,DEVICE,TYPE", "connection", "show", "--active"],
           stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output lines like "Hotspot:wlan0:wifi"
        lines = String.split(output, "\n", trim: true)

        hotspot_active =
          Enum.any?(lines, fn line ->
            parts = String.split(line, ":")
            # Check if this is a hotspot on our interface
            # The connection name is often the SSID or "Hotspot"
            length(parts) >= 2 &&
              (Enum.at(parts, 1) == interface &&
                 (String.contains?(Enum.at(parts, 0), expected_ssid) ||
                    String.contains?(Enum.at(parts, 0), "Hotspot")))
          end)

        if hotspot_active, do: :running, else: :not_running

      {_error, _} ->
        # nmcli failed - can't determine, assume running
        Logger.warning("#{log_prefix()} nmcli failed during hotspot health check")
        :running
    end
  end

  # Try to restart the hotspot after detecting it died
  defp attempt_hotspot_recovery(%{hotspot_restart_attempts: attempts} = state)
       when attempts >= @max_hotspot_restart_attempts do
    Logger.error(
      "#{log_prefix()} Hotspot recovery failed after #{attempts} attempts, giving up"
    )

    # Clear hosting state since we can't recover
    %{state |
      connection_state: :disconnected,
      hosting_config: nil,
      connected_clients: [],
      hotspot_restart_attempts: 0
    }
  end

  defp attempt_hotspot_recovery(state) do
    config = state.hosting_config
    interface = Map.get(config, :interface, state.wifi_interface)
    ssid = config.ssid
    psk = config.psk
    channel = config.channel
    attempts = state.hotspot_restart_attempts + 1

    Logger.warning("#{log_prefix()} Attempting hotspot recovery (attempt #{attempts}/#{@max_hotspot_restart_attempts})")

    # Try to stop any stale hotspot first
    Wifi.stop_hotspot(interface)
    Process.sleep(1000)

    # Restart hotspot with same credentials
    case Wifi.start_hotspot(interface, ssid, psk, channel) do
      {:ok, _uuid} ->
        Logger.info("#{log_prefix()} Hotspot recovered successfully")
        %{state | hotspot_restart_attempts: 0}

      {:error, reason} ->
        Logger.error("#{log_prefix()} Hotspot recovery failed: #{reason}")
        %{state | hotspot_restart_attempts: attempts}
    end
  end

  # Verify WiFi connection is still active when state says connected_as_client
  # Detects external disconnects (user action, signal loss, host reboot)
  defp verify_wifi_connection(%{connection_state: :connected_as_client} = state) do
    case Wifi.get_connection_status(state.wifi_interface) do
      {:ok, %{state: :connected, ssid: current_ssid}} ->
        # Verify we're still connected to the expected SSID
        if current_ssid == state.current_host_ssid do
          # Connection healthy - no state change needed
          state
        else
          # Connected to a different network - unexpected state
          Logger.warning("#{log_prefix()} WiFi connected to different network: #{current_ssid} (expected #{state.current_host_ssid})")
          handle_wifi_connection_lost(state, "ssid_mismatch")
        end

      {:ok, %{state: conn_state}} when conn_state in [:disconnected, :connecting] ->
        # WiFi disconnected externally
        Logger.warning("#{log_prefix()} WiFi connection lost externally (state: #{conn_state})")
        handle_wifi_connection_lost(state, "external_disconnect")

      {:error, reason} ->
        # Could not determine WiFi status - assume still connected to avoid false positives
        Logger.debug("#{log_prefix()} Could not verify WiFi status: #{inspect(reason)}")
        state
    end
  end

  # When disconnected, check if we're actually connected to an R2 hotspot
  # This handles reconnects that happen without going through report_wifi_connected
  defp verify_wifi_connection(%{connection_state: :disconnected, wifi_interface: interface} = state)
       when not is_nil(interface) do
    case Wifi.get_connection_status(interface) do
      {:ok, %{state: :connected, ssid: ssid}} when is_binary(ssid) ->
        # Check if connected to an R2 hotspot
        if String.starts_with?(ssid, "R2Node_") or String.starts_with?(ssid, "R2-") do
          Logger.info("#{log_prefix()} Detected R2 hotspot connection during verification: #{ssid}")
          # Trigger mesh registration
          report_wifi_connected(ssid)
        end
        state

      _ ->
        state
    end
  end

  # No verification needed for hosting or other states
  defp verify_wifi_connection(state), do: state

  # Handle loss of WiFi connection - clean up state and trigger recovery
  defp handle_wifi_connection_lost(state, reason) do
    Logger.info("#{log_prefix()} Handling WiFi connection loss: #{reason}")

    # Clean up PNS routes for the lost host
    if state.current_host_peer_id do
      cleanup_host_routes(state.current_host_peer_id)
    end

    # Update stats based on reason
    updated_stats = state.stats
      |> Map.update!(:connections_lost, &(&1 + 1))
      |> then(fn stats ->
        case reason do
          "external_disconnect" -> Map.update(stats, :wifi_disconnects_detected, 1, &(&1 + 1))
          "ssid_mismatch" -> Map.update(stats, :wifi_disconnects_detected, 1, &(&1 + 1))
          "host_unreachable" -> Map.update(stats, :host_unreachable_events, 1, &(&1 + 1))
          _ -> stats
        end
      end)

    # Reset to disconnected state
    new_state = %{state |
      connection_state: :disconnected,
      current_host_peer_id: nil,
      current_host_ssid: nil,
      current_host_ip: nil,
      connected_at: nil,
      last_sentant_exchange: nil,
      host_unreachable_count: 0,
      stats: updated_stats
    }

    # Trigger immediate assessment to find new host
    Task.start(fn ->
      # Small delay to let state settle
      Process.sleep(1000)
      AiReality2Transnet.ConnectionAssessor.assess_now()
    end)

    new_state
  end

  # Clean up PNS routes when host connection is lost
  defp cleanup_host_routes(host_node_id) do
    # Remove sentants from PeerManager
    AiReality2Transnet.PeerManager.update_peer_sentants(host_node_id, [])

    # Clean up PNS_Routes for this host
    case Reality2.Metadata.all(:PNS_Routes) do
      routes when is_map(routes) ->
        Enum.each(routes, fn {key, route_info} ->
          if Map.get(route_info, :peer_node_id) == host_node_id do
            Reality2.Metadata.delete(:PNS_Routes, key)
          end
        end)

      _ ->
        :ok
    end

    # Remove from PNS_Peers
    Reality2.Metadata.delete(:PNS_Peers, host_node_id)

    Logger.debug("#{log_prefix()} Cleaned up routes for host #{String.slice(host_node_id, 0..7)}...")
  end

  # Check if host is reachable (WiFi connected but host may have rebooted/died)
  defp check_host_reachability(%{connection_state: :connected_as_client, current_host_ip: host_ip} = state)
       when not is_nil(host_ip) do
    # Try to reach the host's /mesh/info endpoint
    url = "https://#{host_ip}:4005/mesh/info"
    request = Finch.build(:get, url, [{"accept", "application/json"}])

    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200}} ->
        # Host is reachable - reset counter
        if state.host_unreachable_count > 0 do
          Logger.info("#{log_prefix()} Host reachable again after #{state.host_unreachable_count} failures")
        end
        %{state | host_unreachable_count: 0}

      {:ok, %Finch.Response{status: status}} ->
        Logger.warning("#{log_prefix()} Host returned unexpected status #{status}")
        increment_unreachable_count(state)

      {:error, reason} ->
        Logger.warning("#{log_prefix()} Host unreachable: #{inspect(reason)}")
        increment_unreachable_count(state)
    end
  end

  # No check needed for other states
  defp check_host_reachability(state), do: state

  defp increment_unreachable_count(state) do
    new_count = state.host_unreachable_count + 1

    if new_count >= @max_unreachable_count do
      Logger.warning("#{log_prefix()} Host unreachable for #{new_count} checks - disconnecting")
      handle_wifi_connection_lost(state, "host_unreachable")
    else
      Logger.info("#{log_prefix()} Host unreachable count: #{new_count}/#{@max_unreachable_count}")
      %{state | host_unreachable_count: new_count}
    end
  end

  defp perform_sentant_exchange(host_node_id, host_ip, host_port) do
    # Retry up to 3 times with delays to handle host startup race condition
    perform_sentant_exchange(host_node_id, host_ip, host_port, 3)
  end

  defp perform_sentant_exchange(host_node_id, host_ip, host_port, retries_left) do
    Logger.info("#{log_prefix()} Performing sentantAll exchange with #{host_ip}:#{host_port} (retries: #{retries_left})")

    # Store peer connection info for PNS Router lookup
    Reality2.Metadata.set(:PNS_Peers, host_node_id, %{
      peer_ip: host_ip,
      port: host_port,
      connected_at: System.system_time(:millisecond)
    })

    _my_sentants = get_local_sentants()  # Reserved for future bidirectional exchange

    # Build GraphQL query for sentantAll
    graphql_query = """
    {
      sentantAll {
        id
        name
        description
        events {
          event
          parameters
        }
        signals
      }
    }
    """

    graphql_request = %{
      query: graphql_query
    }

    # Make HTTPS POST request to host's GraphQL endpoint
    # Using port 4005 (HTTPS) with certificate verification disabled for self-signed certs
    url = "https://#{host_ip}:4005/reality2"
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(graphql_request)

    Logger.debug("#{log_prefix()} Querying GraphQL endpoint: #{url}")

    # Build request with SSL options to accept self-signed certificates
    request = Finch.build(:post, url, headers, body)

    # Use pool with relaxed SSL verification for transient network peers
    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"sentantAll" => host_sentants}}} ->
            Logger.info("#{log_prefix()} Received #{length(host_sentants)} sentants from host")

            # Update PeerManager with host's sentants
            AiReality2Transnet.PeerManager.update_peer_sentants(host_node_id, host_sentants)

            # Update PNS routing table with host's sentants
            update_pns_routing_table(host_node_id, host_ip, host_sentants)

            # Register our sentants with the host (bidirectional exchange)
            register_with_host(host_ip, host_port)

            Logger.info("#{log_prefix()} sentantAll exchange completed successfully")

            # Log current remote sentant count for debugging
            all_peers = AiReality2Transnet.PeerManager.get_all_peers()
            total_remote = Enum.reduce(all_peers, 0, fn {_id, peer}, acc ->
              acc + length(peer.sentants)
            end)
            Logger.info("#{log_prefix()} Total remote sentants now: #{total_remote} (across #{map_size(all_peers)} peers)")

            :ok

          {:ok, %{"errors" => errors}} ->
            Logger.error("#{log_prefix()} GraphQL errors: #{inspect(errors)}")
            {:error, "graphql_errors"}

          {:error, reason} ->
            Logger.error("#{log_prefix()} Failed to decode response: #{inspect(reason)}")
            {:error, "invalid_response"}
        end

      {:ok, %Finch.Response{status: status}} when retries_left > 0 ->
        Logger.warning("#{log_prefix()} HTTP request failed with status: #{status}, retrying in 3s...")
        Process.sleep(3_000)
        perform_sentant_exchange(host_node_id, host_ip, host_port, retries_left - 1)

      {:ok, %Finch.Response{status: status}} ->
        Logger.error("#{log_prefix()} HTTP request failed with status: #{status}")
        {:error, "http_error_#{status}"}

      {:error, reason} when retries_left > 0 ->
        Logger.warning("#{log_prefix()} HTTP request failed: #{inspect(reason)}, retrying in 3s...")
        Process.sleep(3_000)
        perform_sentant_exchange(host_node_id, host_ip, host_port, retries_left - 1)

      {:error, reason} ->
        Logger.error("#{log_prefix()} HTTP request failed: #{inspect(reason)}")
        {:error, "connection_failed"}
    end
  end

  defp get_local_sentants do
    # Get all local sentants with full public info including event parameters
    case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} ->
        Enum.map(sentants, fn sentant ->
          %{
            id: Map.get(sentant, :id),
            name: Map.get(sentant, :name),
            description: Map.get(sentant, :description),
            events: get_events_with_parameters(Map.get(sentant, :events, [])),
            signals: get_signal_names(Map.get(sentant, :signals, []))
          }
        end)

      _ ->
        []
    end
  end

  defp get_events_with_parameters(events) when is_list(events) do
    Enum.map(events, fn
      %{event: name, parameters: params} -> %{event: name, parameters: params}
      %{event: name} -> %{event: name, parameters: %{}}
      %{"event" => name, "parameters" => params} -> %{event: name, parameters: params}
      %{"event" => name} -> %{event: name, parameters: %{}}
      name when is_binary(name) -> %{event: name, parameters: %{}}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_events_with_parameters(_), do: []

  defp get_signal_names(signals) when is_list(signals) do
    Enum.map(signals, fn
      %{signal: name} -> name
      %{name: name} -> name
      %{"signal" => name} -> name
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_signal_names(_), do: []

  # Refresh sentants from host (for re-querying after other clients connect)
  defp do_refresh_sentants(host_node_id, host_ip, host_port) do
    graphql_query = """
    {
      sentantAll {
        id
        name
        description
        events {
          event
          parameters
        }
        signals
      }
    }
    """

    graphql_request = %{query: graphql_query}
    url = "https://#{host_ip}:#{host_port}/reality2"
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(graphql_request)

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 10_000) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"sentantAll" => sentants}}} ->
            Logger.info("#{log_prefix()} Refreshed: received #{length(sentants)} sentants from host")

            # Update PeerManager with refreshed sentants
            AiReality2Transnet.PeerManager.update_peer_sentants(host_node_id, sentants)

            # Update PNS routing table
            update_pns_routing_table(host_node_id, host_ip, sentants)

            {:ok, length(sentants)}

          {:ok, %{"errors" => errors}} ->
            Logger.error("#{log_prefix()} Refresh GraphQL errors: #{inspect(errors)}")
            {:error, "graphql_errors"}

          _ ->
            {:error, "invalid_response"}
        end

      {:ok, %Finch.Response{status: status}} ->
        Logger.error("#{log_prefix()} Refresh failed with status #{status}")
        {:error, "http_error_#{status}"}

      {:error, reason} ->
        Logger.error("#{log_prefix()} Refresh request failed: #{inspect(reason)}")
        {:error, "connection_failed"}
    end
  end

  # Register our sentants with the host for bidirectional discovery
  defp register_with_host(host_ip, host_port) do
    my_node_id = Reality2.Bootstrap.get(:node_id)
    my_node_name = Reality2.Bootstrap.get(:node_name)
    my_sentants = get_local_sentants()

    Logger.info("#{log_prefix()} Registering #{length(my_sentants)} sentants with host at #{host_ip}:#{host_port}")

    # Log sentant names for debugging
    sentant_names = Enum.map(my_sentants, fn s -> Map.get(s, :name, "?") end)
    Logger.debug("#{log_prefix()} Sentants to register: #{inspect(sentant_names)}")

    register_request = %{
      node_id: my_node_id,
      node_name: my_node_name,
      sentants: my_sentants
    }

    url = "https://#{host_ip}:#{host_port}/mesh/register"
    headers = [{"content-type", "application/json"}]

    case Jason.encode(register_request) do
      {:ok, body} ->
        Logger.debug("#{log_prefix()} Sending registration request to #{url}")
        request = Finch.build(:post, url, headers, body)

        case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 10_000) do
          {:ok, %Finch.Response{status: 200, body: response_body}} ->
            case Jason.decode(response_body) do
              {:ok, %{"status" => "ok", "stored_sentant_ids" => stored_ids} = response} ->
                count = Map.get(response, "registered_sentants", 0)
                host_node_id = Map.get(response, "host_node_id")
                host_node_name = Map.get(response, "host_node_name", "")

                # Verify all sentants were stored
                my_ids = Enum.map(my_sentants, fn s -> Map.get(s, :id) end) |> Enum.reject(&is_nil/1)
                stored_set = MapSet.new(stored_ids || [])
                missing = Enum.reject(my_ids, fn id -> MapSet.member?(stored_set, id) end)

                if length(missing) > 0 do
                  Logger.warning("#{log_prefix()} Registration incomplete: #{length(missing)} sentants not stored on host")
                  Logger.debug("#{log_prefix()} Missing IDs: #{inspect(Enum.map(missing, &String.slice(&1, 0..7)))}")
                else
                  Logger.info("#{log_prefix()} Successfully registered #{count} sentants with host #{host_node_name} - all confirmed")
                end

                # Update state with the confirmed host_node_id
                if host_node_id do
                  GenServer.cast(__MODULE__, {:set_host_peer_id, host_node_id})
                end

                :ok

              {:ok, %{"status" => "ok", "registered_sentants" => count, "host_node_id" => host_node_id}} ->
                # Legacy response without stored_sentant_ids
                Logger.info("#{log_prefix()} Successfully registered #{count} sentants with host #{String.slice(host_node_id, 0..7)}...")
                GenServer.cast(__MODULE__, {:set_host_peer_id, host_node_id})
                :ok

              {:ok, %{"status" => "ok", "registered_sentants" => count}} ->
                Logger.info("#{log_prefix()} Successfully registered #{count} sentants with host")
                :ok

              {:ok, response} ->
                Logger.warning("#{log_prefix()} Unexpected register response: #{inspect(response)}")
                :ok

              {:error, reason} ->
                Logger.error("#{log_prefix()} Failed to decode register response: #{inspect(reason)}")
                {:error, "invalid_response"}
            end

          {:ok, %Finch.Response{status: status, body: resp_body}} ->
            Logger.error("#{log_prefix()} Register request failed with status #{status}: #{resp_body}")
            {:error, "http_error_#{status}"}

          {:error, %Mint.TransportError{reason: reason}} ->
            Logger.error("#{log_prefix()} Register transport error: #{inspect(reason)}")
            {:error, "transport_error"}

          {:error, reason} ->
            Logger.error("#{log_prefix()} Register request failed: #{inspect(reason)}")
            {:error, "connection_failed"}
        end

      {:error, reason} ->
        Logger.error("#{log_prefix()} Failed to encode registration request: #{inspect(reason)}")
        {:error, "encode_failed"}
    end
  end

  defp update_pns_routing_table(peer_node_id, peer_ip, peer_sentants) do
    # Get peer's node_name from PeerManager for better identification
    peer_node_name = case AiReality2Transnet.PeerManager.get_peer(peer_node_id) do
      {:ok, peer} -> Map.get(peer, :node_name, "Unknown")
      _ -> "Unknown"
    end

    # Update PNS routing table with peer's sentants
    # Format: peer_node_id|sentant_name -> peer_ip
    Enum.each(peer_sentants, fn sentant ->
      sentant_name = Map.get(sentant, "name")
      sentant_id = Map.get(sentant, "id")

      if sentant_name do
        # Store routing entry: node_id|sentant_name -> host_ip
        pns_key = "#{peer_node_id}|#{sentant_name}"

        # Store in PNS metadata with peer node name for easier identification
        Reality2.Metadata.set(:PNS_Routes, pns_key, %{
          peer_node_id: peer_node_id,
          peer_node_name: peer_node_name,
          peer_ip: peer_ip,
          sentant_name: sentant_name,
          sentant_id: sentant_id,
          discovered_at: System.system_time(:millisecond)
        })

        Logger.debug("#{log_prefix()} PNS route added: #{peer_node_name}|#{sentant_name} -> #{peer_ip}")
      end
    end)

    Logger.info("#{log_prefix()} PNS routing table updated with #{length(peer_sentants)} entries from #{peer_node_name}")
  end

  # Perform sentantAll exchange after auto-connecting to an R2 hotspot via SSID
  # Called when ConnectionAssessor discovers and connects to a hotspot
  # Includes retry logic to handle race condition where BLE discovery hasn't completed yet
  defp perform_sentant_exchange_by_ssid(ssid) do
    Logger.info("#{log_prefix()} Performing sentantAll exchange for SSID: #{ssid}")

    # Retry up to 5 times with 2 second delays to allow BLE discovery to complete
    perform_sentant_exchange_by_ssid(ssid, 5)
  end

  defp perform_sentant_exchange_by_ssid(ssid, retries_left) when retries_left <= 0 do
    # All retries exhausted - try exchange with gateway IP as last resort
    Logger.warning("#{log_prefix()} Peer lookup exhausted for #{ssid}, attempting exchange with gateway")
    perform_exchange_with_gateway(ssid)
  end

  defp perform_sentant_exchange_by_ssid(ssid, retries_left) do
    # The SSID is the node_name - find the peer by looking up the node_id
    case Reality2.Metadata.get(:PNS_NodeNames, ssid) do
      nil ->
        # Peer not found by node_name, try to find by scanning all peers
        find_peer_by_ssid_and_exchange(ssid, retries_left)

      peer_node_id ->
        # Found peer node_id, get gateway IP and perform exchange
        perform_exchange_with_peer(peer_node_id, ssid)
    end
  end

  defp find_peer_by_ssid_and_exchange(ssid, retries_left) do
    # Search all peers for one with matching node_name
    peers = AiReality2Transnet.PeerManager.get_all_peers()

    case Enum.find(peers, fn {_id, peer} -> peer.node_name == ssid end) do
      {peer_node_id, _peer} ->
        perform_exchange_with_peer(peer_node_id, ssid)

      nil when retries_left > 1 ->
        # Peer not found yet - wait and retry (BLE discovery may still be in progress)
        Logger.debug("#{log_prefix()} Peer #{ssid} not found, waiting for BLE discovery (#{retries_left - 1} retries left)")
        Process.sleep(2_000)
        perform_sentant_exchange_by_ssid(ssid, retries_left - 1)

      nil ->
        # Last retry failed
        Logger.warning("#{log_prefix()} No peer found for SSID #{ssid} after retries")
        perform_exchange_with_gateway(ssid)
    end
  end

  defp perform_exchange_with_peer(peer_node_id, ssid) do
    # Get the gateway IP (the hotspot host's IP)
    case get_gateway_ip() do
      {:ok, gateway_ip} ->
        Logger.info("#{log_prefix()} Found gateway IP: #{gateway_ip} for peer #{String.slice(peer_node_id, 0..7)}...")

        # Update transport BEFORE exchange so sentants are associated with wifi_hotspot
        PeerManager.update_peer_transport(peer_node_id, :wifi_hotspot)

        case perform_sentant_exchange(peer_node_id, gateway_ip, 4005) do
          :ok ->
            Logger.info("#{log_prefix()} sentantAll exchange completed for #{ssid}")
            # Update the state with the discovered peer_node_id
            GenServer.cast(__MODULE__, {:set_host_peer_id, peer_node_id})

            # Emit mesh_host_connected event so client webapp updates
            emit_mesh_host_connected_event(peer_node_id)

          {:error, reason} ->
            Logger.error("#{log_prefix()} sentantAll exchange failed for #{ssid}: #{reason}")
        end

      {:error, reason} ->
        Logger.error("#{log_prefix()} Could not get gateway IP: #{reason}")
    end
  end

  defp perform_exchange_with_gateway(ssid) do
    # Try to exchange with gateway IP even without knowing the peer_node_id
    case get_gateway_ip() do
      {:ok, gateway_ip} ->
        Logger.info("#{log_prefix()} Attempting exchange with gateway: #{gateway_ip}")

        # Query /mesh/info to get the real node_id instead of using a placeholder
        # This ensures sentants are stored under the correct peer ID
        case query_mesh_info(gateway_ip) do
          {:ok, %{"node_id" => real_node_id}} ->
            Logger.info("#{log_prefix()} Got real node_id from mesh/info: #{String.slice(real_node_id, 0..7)}...")

            # Update transport BEFORE exchange so sentants are associated with wifi_hotspot
            PeerManager.update_peer_transport(real_node_id, :wifi_hotspot)

            case perform_sentant_exchange(real_node_id, gateway_ip, 4005) do
              :ok ->
                Logger.info("#{log_prefix()} sentantAll exchange completed via gateway for #{ssid}")
                # Emit mesh_host_connected event so client webapp updates
                emit_mesh_host_connected_event(real_node_id)

              {:error, reason} ->
                Logger.error("#{log_prefix()} sentantAll exchange failed via gateway: #{reason}")
            end

          {:error, reason} ->
            Logger.warning("#{log_prefix()} Could not get node_id from mesh/info: #{reason}, using placeholder")
            # Fallback to placeholder (not ideal but better than failing completely)
            placeholder_node_id = "unknown-#{ssid}"

            # Update transport BEFORE exchange so sentants are associated with wifi_hotspot
            PeerManager.update_peer_transport(placeholder_node_id, :wifi_hotspot)

            case perform_sentant_exchange(placeholder_node_id, gateway_ip, 4005) do
              :ok ->
                Logger.info("#{log_prefix()} sentantAll exchange completed via gateway for #{ssid} (placeholder)")
                # Emit mesh_host_connected event so client webapp updates
                emit_mesh_host_connected_event(placeholder_node_id)

              {:error, reason} ->
                Logger.error("#{log_prefix()} sentantAll exchange failed via gateway: #{reason}")
            end
        end

      {:error, reason} ->
        Logger.error("#{log_prefix()} Could not get gateway IP: #{reason}")
    end
  end

  # Query the host's /mesh/info endpoint to get its node_id
  defp query_mesh_info(host_ip) do
    url = "https://#{host_ip}:4005/mesh/info"

    request = Finch.build(:get, url, [{"accept", "application/json"}])

    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, info} -> {:ok, info}
          {:error, _} -> {:error, "invalid_json"}
        end

      {:ok, %Finch.Response{status: status}} ->
        {:error, "http_#{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # Get the default gateway IP (the hotspot host's IP)
  defp get_gateway_ip do
    case System.cmd("ip", ["route", "show", "default"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse: "default via 10.42.0.1 dev wlp195s0 proto dhcp metric 600"
        case Regex.run(~r/default via ([0-9.]+)/, output) do
          [_, gateway_ip] -> {:ok, gateway_ip}
          _ -> {:error, :no_default_route}
        end

      {error, _} ->
        {:error, "ip_route_failed: #{error}"}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Event Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Emit mesh_host_connected event for client webapp to refresh
  # Called after sentant exchange completes in auto-connect paths
  defp emit_mesh_host_connected_event(peer_node_id) do
    if Code.ensure_loaded?(Reality2.Sentants) do
      host_name = PeerManager.get_peer(peer_node_id)
        |> case do
          {:ok, peer} -> Map.get(peer, :node_name, "Unknown")
          _ -> "Unknown"
        end
      host_sentant_count = PeerManager.get_peer(peer_node_id)
        |> case do
          {:ok, peer} -> length(Map.get(peer, :sentants, []))
          _ -> 0
        end

      Logger.info("#{log_prefix()} Emitting mesh_host_connected event for #{host_name} (#{host_sentant_count} sentants)")

      Reality2.Sentants.sendto_all(%{
        event: "__internal",
        parameters: %{
          mesh_event: "mesh_host_connected",
          peer_id: peer_node_id,
          peer_name: host_name,
          sentant_count: host_sentant_count
        }
      })
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Health Metrics Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Format duration in milliseconds to human-readable string
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{div(ms, 1000)}s"
  defp format_duration(ms) when ms < 3_600_000 do
    mins = div(ms, 60_000)
    secs = rem(div(ms, 1000), 60)
    "#{mins}m #{secs}s"
  end
  defp format_duration(ms) do
    hours = div(ms, 3_600_000)
    mins = rem(div(ms, 60_000), 60)
    "#{hours}h #{mins}m"
  end

  # Compute success rate as percentage (0-100)
  defp compute_success_rate(successes, failures) when successes + failures == 0, do: nil
  defp compute_success_rate(successes, failures) do
    total = successes + failures
    Float.round(successes / total * 100, 1)
  end
end
