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

      # Host mode state (when hosting hotspot)
      hosting_config: nil,
      connected_clients: [],

      # System info
      wifi_interface: wifi_interface,

      # Statistics for monitoring
      stats: %{
        connections_made: 0,
        handovers_completed: 0,
        handovers_failed: 0,
        hosting_sessions: 0
      }
    }

    Logger.info("[ConnectionManager] Started - WiFi interface: #{wifi_interface || "none"}")
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
        # Only allow handover when actively connected to a host
        perform_handover(new_peer_id, new_join_offer, state)

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
  def handle_cast({:wifi_connected, ssid}, state) do
    # External notification that WiFi was connected (e.g., by ConnectionAssessor auto-discovery)
    Logger.info("[ConnectionManager] WiFi connection reported: #{ssid}")

    new_state = %{state |
      connection_state: :connected_as_client,
      current_host_ssid: ssid,
      connected_at: System.system_time(:millisecond),
      stats: Map.update!(state.stats, :connections_made, &(&1 + 1))
    }

    {:noreply, new_state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Connection Operations
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp perform_connection(peer_id, join_offer, state) do
    Logger.info("[ConnectionManager] Connecting to host: #{String.slice(peer_id, 0..7)}...")

    # Transition to :connecting state
    new_state = %{state | connection_state: :connecting}

    # Validate join offer hasn't expired
    # Offers typically expire 5 minutes after creation
    now = System.system_time(:second)
    if join_offer.offer_expiry < now do
      Logger.error("[ConnectionManager] Join offer expired")
      {:reply, {:error, "offer_expired"}, %{new_state | connection_state: :disconnected}}
    else
      # Step 1: Connect to WiFi hotspot using WPA2-PSK credentials
      case Wifi.connect_to_network(state.wifi_interface, join_offer.ssid, join_offer.psk) do
        {:ok, _connection_uuid} ->
          # Step 2: Wait for DHCP to assign IP address
          case Wifi.get_interface_ip(state.wifi_interface) do
            {:ok, my_ip} ->
              Logger.info("[ConnectionManager] Connected - IP: #{my_ip}")

              # Step 3: Exchange Sentant directories via GraphQL
              # This populates PNS routing table with host's available Sentants
              case perform_sentant_exchange(peer_id, join_offer.rendezvous_ip, join_offer.rendezvous_port) do
                :ok ->
                  # Step 4: Update state to :connected_as_client
                  final_state = %{new_state |
                    connection_state: :connected_as_client,
                    current_host_peer_id: peer_id,
                    current_host_ssid: join_offer.ssid,
                    current_host_ip: join_offer.rendezvous_ip,
                    connected_at: System.system_time(:millisecond),
                    last_sentant_exchange: System.system_time(:millisecond),
                    stats: Map.update!(new_state.stats, :connections_made, &(&1 + 1))
                  }

                  # Step 5: Notify PeerManager of transport upgrade (BLE → WiFi)
                  PeerManager.update_peer_transport(peer_id, :wifi_hotspot)

                  connection_info = %{
                    peer_id: peer_id,
                    ssid: join_offer.ssid,
                    host_ip: join_offer.rendezvous_ip,
                    my_ip: my_ip
                  }

                  Logger.info("[ConnectionManager] Connection established and sentantAll completed")
                  {:reply, {:ok, connection_info}, final_state}

                {:error, reason} ->
                  Logger.error("[ConnectionManager] sentantAll exchange failed: #{reason}")
                  # Disconnect
                  Wifi.disconnect_from_network(state.wifi_interface)
                  {:reply, {:error, "sentant_exchange_failed: #{reason}"},
                   %{new_state | connection_state: :disconnected}}
              end

            {:error, reason} ->
              Logger.error("[ConnectionManager] Failed to get IP: #{reason}")
              Wifi.disconnect_from_network(state.wifi_interface)
              {:reply, {:error, "ip_assignment_failed: #{reason}"},
               %{new_state | connection_state: :disconnected}}
          end

        {:error, reason} ->
          Logger.error("[ConnectionManager] Connection failed: #{reason}")
          {:reply, {:error, "wifi_connect_failed: #{reason}"},
           %{new_state | connection_state: :disconnected}}
      end
    end
  end

  defp perform_disconnection(state) do
    Logger.info("[ConnectionManager] Disconnecting from host")

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
    Logger.info("[ConnectionManager] Handover: #{String.slice(state.current_host_peer_id, 0..7)} -> #{String.slice(new_peer_id, 0..7)}")

    _old_host_id = state.current_host_peer_id
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
                  stats: Map.update!(new_state.stats, :handovers_completed, &(&1 + 1))
                }

                # Update PeerManager
                PeerManager.update_peer_transport(new_peer_id, :wifi_hotspot)

                Logger.info("[ConnectionManager] Handover completed successfully")
                {:reply, :ok, final_state}

              {:error, reason} ->
                Logger.error("[ConnectionManager] Handover sentantAll failed: #{reason}")
                # Try to reconnect to old host
                Logger.warning("[ConnectionManager] Attempting rollback to old host")
                # For now, just mark as failed
                {:reply, {:error, "handover_sentant_exchange_failed"},
                 %{new_state |
                   connection_state: :disconnected,
                   stats: Map.update!(new_state.stats, :handovers_failed, &(&1 + 1))
                 }}
            end

          {:error, reason} ->
            Logger.error("[ConnectionManager] Handover IP assignment failed: #{reason}")
            {:reply, {:error, "handover_ip_failed"},
             %{new_state |
               connection_state: :disconnected,
               stats: Map.update!(new_state.stats, :handovers_failed, &(&1 + 1))
             }}
        end

      {:error, reason} ->
        Logger.error("[ConnectionManager] Handover connection failed: #{reason}")
        {:reply, {:error, "handover_connect_failed"},
         %{new_state |
           connection_state: :connected_as_client,  # Restore previous state
           stats: Map.update!(new_state.stats, :handovers_failed, &(&1 + 1))
         }}
    end
  end

  defp perform_start_hosting(state) do
    Logger.info("[ConnectionManager] Starting hotspot hosting")

    # Generate unique credentials for this hotspot
    # SSID format: R2-<SITE_ID>-<HOST_SHORT_ID>
    # Example: R2-WAIROA-A3F7
    # Configure site_id via:
    #   Environment: export R2_SITE_ID=WAIROA
    #   Config: config :ai_reality2_transnet, site_id: "WAIROA"
    #   Default: "NODE"
    node_id = Reality2.Bootstrap.get(:node_id)
    ssid = Wifi.generate_ssid(node_id)  # Uses node_name from Bootstrap
    # Use deterministic PSK so other nodes can predict credentials from SSID
    psk = Wifi.generate_psk_for_node(ssid)
    channel = 6

    case Wifi.start_hotspot(state.wifi_interface, ssid, psk, channel) do
      {:ok, _uuid} ->
        # Get hotspot IP
        case Wifi.get_hotspot_ip(state.wifi_interface) do
          {:ok, ip_address} ->
            hotspot_config = %{
              ssid: ssid,
              psk: psk,
              channel: channel,
              ip_address: ip_address,
              port: 4005,  # HTTP/GraphQL server port (unified with Reality2Web)
              active: true
            }

            new_state = %{state |
              hosting_config: hotspot_config,
              connection_state: :hosting_ap,
              stats: Map.update!(state.stats, :hosting_sessions, &(&1 + 1))
            }

            Logger.info("[ConnectionManager] Hotspot started: #{ssid} on #{ip_address}")
            {:reply, {:ok, hotspot_config}, new_state}

          {:error, reason} ->
            Logger.error("[ConnectionManager] Failed to get hotspot IP: #{reason}")
            Wifi.stop_hotspot(state.wifi_interface)
            {:reply, {:error, "hotspot_ip_failed: #{reason}"}, state}
        end

      {:error, reason} ->
        Logger.error("[ConnectionManager] Failed to start hotspot: #{reason}")
        {:reply, {:error, "hotspot_start_failed: #{reason}"}, state}
    end
  end

  defp perform_stop_hosting(state) do
    Logger.info("[ConnectionManager] Stopping hotspot hosting")

    case Wifi.stop_hotspot(state.wifi_interface) do
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
        Logger.warning("[ConnectionManager] No WiFi adapters found")
        nil
    end
  end

  defp perform_sentant_exchange(host_node_id, host_ip, host_port) do
    Logger.info("[ConnectionManager] Performing sentantAll exchange with #{host_ip}:#{host_port}")

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

    # Make HTTP POST request to host's GraphQL endpoint
    # Note: Using port 4005 for Reality2Web GraphQL endpoint
    url = "http://#{host_ip}:4005/reality2"
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(graphql_request)

    Logger.debug("[ConnectionManager] Querying GraphQL endpoint: #{url}")

    case Finch.build(:post, url, headers, body)
         |> Finch.request(Reality2.HTTPClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"sentantAll" => host_sentants}}} ->
            Logger.info("[ConnectionManager] Received #{length(host_sentants)} sentants from host")

            # Update PNS routing table with host's sentants
            update_pns_routing_table(host_node_id, host_ip, host_sentants)

            Logger.info("[ConnectionManager] sentantAll exchange completed successfully")
            :ok

          {:ok, %{"errors" => errors}} ->
            Logger.error("[ConnectionManager] GraphQL errors: #{inspect(errors)}")
            {:error, "graphql_errors"}

          {:error, reason} ->
            Logger.error("[ConnectionManager] Failed to decode response: #{inspect(reason)}")
            {:error, "invalid_response"}
        end

      {:ok, %Finch.Response{status: status}} ->
        Logger.error("[ConnectionManager] HTTP request failed with status: #{status}")
        {:error, "http_error_#{status}"}

      {:error, reason} ->
        Logger.error("[ConnectionManager] HTTP request failed: #{inspect(reason)}")
        {:error, "connection_failed"}
    end
  end

  defp get_local_sentants do
    # Get all local sentants
    Reality2.Metadata.all(:SentantIDs)
    |> Enum.map(fn {sentant_id, _} ->
      case Reality2.Metadata.get(:Sentants, sentant_id) do
        {:ok, sentant} ->
          %{
            id: sentant_id,
            name: Map.get(sentant, :name, "unknown"),
            description: Map.get(sentant, :description, nil)
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp update_pns_routing_table(peer_node_id, peer_ip, peer_sentants) do
    # Update PNS routing table with peer's sentants
    # Format: peer_node_id|sentant_name -> peer_ip
    Enum.each(peer_sentants, fn sentant ->
      sentant_name = Map.get(sentant, "name")
      sentant_id = Map.get(sentant, "id")

      if sentant_name do
        # Store routing entry: node_id|sentant_name -> host_ip
        pns_key = "#{peer_node_id}|#{sentant_name}"

        # Store in PNS metadata (you may want to use a different storage mechanism)
        Reality2.Metadata.set(:PNS_Routes, pns_key, %{
          peer_node_id: peer_node_id,
          peer_ip: peer_ip,
          sentant_name: sentant_name,
          sentant_id: sentant_id,
          discovered_at: System.system_time(:millisecond)
        })

        Logger.debug("[ConnectionManager] PNS route added: #{pns_key} -> #{peer_ip}")
      end
    end)

    Logger.info("[ConnectionManager] PNS routing table updated with #{length(peer_sentants)} entries")
  end
end
