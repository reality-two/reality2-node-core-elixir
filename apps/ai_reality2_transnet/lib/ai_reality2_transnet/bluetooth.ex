defmodule AiReality2Transnet.Bluetooth do
  # *******************************************************************************************************************************************
  @moduledoc """
  Bluetooth module for Transient Networks. Handles BLE beacons, node discovery, and GATT server
  for Sentant access. Calls into the Rust NIFs detailed in AiReality2Transnet.Action.

  ## GATT Server Operations:

  ### Query Characteristic (Read) - UUID: 00002a57
  - sentantAll - Get all Sentants on the node

  ### Mutation Characteristic (Write) - UUID: 00002a58
  - sentantSend - Send event to a Sentant

  ### Subscription Characteristic (Notify) - UUID: 00002a59
  - awaitSignal - Stream signals from Sentants (BLE notifications)

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  alias Reality2.Sentants, as: Sentants
  alias Reality2.Helpers.R2Map, as: R2Map
  use GenServer, restart: :transient
  require Logger

  # Helper to get node name for log messages
  defp log_prefix, do: "[Bluetooth:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  # Default Company ID for R2 manufacturer data.
  # TODO: Replace with an assigned company ID.
  @r2_company_id 0xFFFF
  # Increased to support larger sentant data
  @max_characteristic_size 4096
  @protocol_version "1.0"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Broadcasts a Sentant signal to all subscribed BLE clients.
  Mirrors GraphQL: awaitSignal(id, signal)

  This should be called whenever a Sentant emits a signal.
  """
  def broadcast_signal(sentant_id, signal, event, parameters, passthrough \\ nil) do
    GenServer.cast(
      __MODULE__,
      {:broadcast_signal, sentant_id, signal, event, parameters, passthrough}
    )
  end

  @doc """
  Gets the current Bluetooth server state and statistics.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Send a mutation to a peer node's Sentant.

  ## Parameters
  - `peer_node_id` - The Reality2 node ID of the peer
  - `sentant_id` - The UUID of the Sentant on the peer node
  - `event` - The event name to trigger
  - `parameters` - Optional parameters map
  - `passthrough` - Optional passthrough data

  ## Returns
  - `{:ok, response}` - Success with response data
  - `{:error, reason}` - Error reason
  """
  def send_to_peer_sentant(peer_node_id, sentant_id, event, parameters \\ %{}, passthrough \\ nil) do
    GenServer.call(
      __MODULE__,
      {:send_to_peer, peer_node_id, sentant_id, event, parameters, passthrough}
    )
  end

  @doc """
  Get list of connected peer nodes.

  DEPRECATED: Use AiReality2Transnet.PeerManager.get_all_peers() instead.

  ## Returns
  - `%{node_id => %{address, sentants, connected_at}}`
  """
  def get_connected_peers do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      AiReality2Transnet.PeerManager.get_all_peers()
    else
      %{}
    end
  end

  @doc """
  Get a specific peer's information.

  DEPRECATED: Use AiReality2Transnet.PeerManager.get_peer(peer_id) instead.

  ## Returns
  - `{:ok, peer_info}` - Peer found
  - `{:error, :not_found}` - Peer not connected
  """
  def get_peer(peer_node_id) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      AiReality2Transnet.PeerManager.get_peer(peer_node_id)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Broadcasts an R2 Mesh message to nearby nodes.

  This function transmits mesh messages using available BLE mechanisms:
  1. GATT notifications to connected clients
  2. Discovery relay to nearby nodes (via PeerManager)

  ## Parameters
  - `encoded_message` - Binary message (24 bytes max for BLE advertising)

  ## Message Format
  ```
  [msg_id:2][ttl:1][type:1][src_hash:2][payload:18]
  ```

  ## Returns
  - `:ok` - Message queued for broadcast
  - `{:error, reason}` - Failed to broadcast
  """
  def broadcast_mesh_message(encoded_message) do
    GenServer.cast(__MODULE__, {:broadcast_mesh_message, encoded_message})
  end

  @doc """
  Handles incoming R2 Mesh messages from BLE discovery.

  Called when a mesh message is detected in manufacturer data from a nearby node.
  The message is forwarded to R2Mesh for processing and potential relay.

  ## Parameters
  - `encoded_message` - Binary mesh message
  - `source_info` - Map with source node info (address, rssi, etc.)
  """
  def handle_incoming_mesh_message(encoded_message, source_info) do
    GenServer.cast(__MODULE__, {:incoming_mesh_message, encoded_message, source_info})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(state) do
    # Find the bluetooth adapter (taking the first one)
    # TODO: Handle multiple adapters and/or set adapter to use as an Environment variable

    # Initialize state with default counters to prevent crashes if startup fails
    initial_state =
      Map.merge(state, %{
        events_sent: 0,
        signals_broadcast: 0,
        queries_processed: 0,
        connected_peers: %{},
        bluetooth_available: false
      })

    # Try to initialize Bluetooth, but continue in degraded mode if unavailable
    result =
      {:ok, initial_state}
      |> get_adapter_and_name()
      |> start_beacon()
      |> start_gatt_server()
      |> start_watch()
      |> subscribe_to_pubsub()

    case result do
      {:ok, final_state} ->
        {:ok, Map.put(final_state, :bluetooth_available, true)}

      {:error, reason} ->
        Logger.warning("#{log_prefix()} Bluetooth unavailable: #{inspect(reason)} - running in WiFi-only mode")
        # Subscribe to PubSub even without Bluetooth for future use
        Phoenix.PubSub.subscribe(Reality2.PubSub, "sentants")
        {:ok, initial_state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Stop watcher + beacon + GATT server using the stored keys
    Logger.info("Terminating Bluetooth service")
    if h = state[:r2_watch], do: AiReality2Transnet.Action.stop_watching(h)
    if h = state[:r2_beacon], do: AiReality2Transnet.Action.stop_broadcast(h)
    if h = state[:gatt_handle], do: AiReality2Transnet.Action.stop_gatt_server(h)
    :ok
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_call
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:send_to_peer, peer_id, sentant_id, event, params, passthrough}, _from, state) do
    # Use PeerManager to get peer info
    peer_result =
      if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
        AiReality2Transnet.PeerManager.get_peer(peer_id)
      else
        {:error, :not_found}
      end

    case peer_result do
      {:error, :not_found} ->
        {:reply, {:error, :peer_not_connected}, state}

      {:ok, peer_info} ->
        mutation = %{
          id: sentant_id,
          event: event,
          parameters: params,
          passthrough: passthrough
        }

        mutation_json = Jason.encode!(mutation)
        data_uuid = "00002a58-0000-1000-8000-00805f9b34fb"
        adapter_name = Map.get(state, :adapter_name, "hci0")

        result =
          AiReality2Transnet.Action.gatt_write_to_device(
            self(),
            peer_info.address,
            data_uuid,
            mutation_json,
            adapter_name
          )

        {:reply, result, state}
    end
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, :unknown_command}, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_cast
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_cast(%{command: "list_adapters"}, state) do
    list_adapters(state)
  end

  def handle_cast(%{command: "scan_nodes", parameters: parameters}, state) do
    scan_nodes(state, parameters)
    {:noreply, state}
  end

  def handle_cast(%{command: "reset_nodes"}, state) do
    reset_nodes(state)
    {:noreply, state}
  end

  # Subscription Operations (BLE Notify) - Mirrors awaitSignal
  def handle_cast(
        {:broadcast_signal, sentant_id, signal, event, parameters, passthrough},
        %{gatt_handle: handle} = state
      ) do
    # Mirrors GraphQL subscription: awaitSignal(id, signal)
    message = %{
      type: "await_signal",
      version: @protocol_version,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      data: %{
        sentant_id: sentant_id,
        signal: signal,
        event: event,
        parameters: parameters,
        passthrough: passthrough
      }
    }

    case encode_and_notify(handle, message) do
      :ok ->
        node_name = get_node_name_from_params(parameters)
        Logger.debug("GATT notify from #{node_name}: Sentant #{sentant_id} - #{signal}")
        new_state = %{state | signals_broadcast: state.signals_broadcast + 1}
        {:noreply, new_state}

      :error ->
        Logger.error("Failed to broadcast signal")
        {:noreply, state}
    end
  end

  # R2 Mesh message broadcast - send to nearby nodes via GATT and relay
  def handle_cast({:broadcast_mesh_message, encoded_message}, state) do
    Logger.debug("#{log_prefix()} Broadcasting mesh message (#{byte_size(encoded_message)} bytes)")

    # 1. Send via GATT notification to connected clients
    if handle = Map.get(state, :gatt_handle) do
      mesh_notification = %{
        type: "r2_mesh",
        version: @protocol_version,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        data: Base.encode64(encoded_message)
      }
      encode_and_notify(handle, mesh_notification)
    end

    # 2. Queue for relay via discovery mechanism
    # The mesh message will be picked up by nearby nodes during their next scan
    # For now, we rely on GATT notifications to connected peers
    # Future: Could embed mesh data in manufacturer data alongside beacon

    # Track mesh messages broadcast
    mesh_sent = Map.get(state, :mesh_messages_sent, 0)
    {:noreply, Map.put(state, :mesh_messages_sent, mesh_sent + 1)}
  end

  # Incoming R2 Mesh message from BLE discovery - forward to R2Mesh for processing
  def handle_cast({:incoming_mesh_message, encoded_message, source_info}, state) do
    Logger.debug("#{log_prefix()} Received mesh message from #{inspect(source_info[:address])}")

    # Forward to R2Mesh module for deduplication, processing, and potential relay
    if Code.ensure_loaded?(AiReality2Transnet.R2Mesh) do
      AiReality2Transnet.R2Mesh.handle_incoming(encoded_message)
    else
      Logger.warning("#{log_prefix()} R2Mesh module not available, dropping mesh message")
    end

    # Track mesh messages received
    mesh_received = Map.get(state, :mesh_messages_received, 0)
    {:noreply, Map.put(state, :mesh_messages_received, mesh_received + 1)}
  end

  def handle_cast(_, state), do: {:noreply, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_info (return values from Rust NIFs and GATT events)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true

  # GATT Server Events
  def handle_info(:gatt_server_started, state) do
    Logger.info("GATT Sentant Server is ready and discoverable")
    {:noreply, state}
  end

  # Query Operations (BLE Read) - Mirrors sentantAll
  def handle_info({:gatt_write, "command", _data}, state) do
    # Any write to command characteristic triggers a refresh of Sentant list
    Logger.debug("Query characteristic written - refreshing Sentant list")
    update_query_characteristic(state.gatt_handle)
    new_state = %{state | queries_processed: state.queries_processed + 1}
    {:noreply, new_state}
  end

  # Mutation Operations (BLE Write) - Mirrors sentantSend
  def handle_info({:gatt_write, "data", data}, state) do
    Logger.info("Mutation received: #{inspect(data)}")

    case parse_sentant_send(data) do
      {:ok, mutation} ->
        handle_sentant_send(mutation, state)

      {:error, reason} ->
        Logger.error("Invalid sentantSend mutation: #{reason}")
        send_error_notification(state.gatt_handle, "invalid_mutation", reason)
        {:noreply, state}
    end
  end

  # The details of a Reality2 node that has been found nearby.
  def handle_info({:r2node_found, id, info}, state) do
    # Extract BLE address and node name from info
    address = Map.get(info, :address)
    # BLE discovery provides :name (device name), map it to :node_name for PeerManager
    node_name = Map.get(info, :name) || Map.get(info, :node_name) || "Unknown"
    # Extract hosting priority from beacon (0-100, 0 means not broadcast/unknown)
    hosting_priority = Map.get(info, :hosting_priority, 0)

    Logger.info("R2 Node discovered: #{node_name} (#{String.slice(id, 0..7)}...) priority: #{hosting_priority}")

    # Enrich info with properly named fields for downstream consumers
    enriched_info = info
      |> Map.put(:node_name, node_name)
      |> Map.put(:node_id, id)
      |> Map.put(:hosting_priority, hosting_priority)

    # Notify all Sentants about the discovery
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        activity: "r2_node_found",
        id: id,
        node_name: node_name,
        info: enriched_info,
        address: address,
        hosting_priority: hosting_priority
      }
    })

    # Register peer with PeerManager (BLE discovery only - no GATT sentant reading)
    # Sentant queries will happen via WiFi mesh HTTP after upgrade
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      AiReality2Transnet.PeerManager.register_peer(id, enriched_info)
      Logger.info("Peer #{node_name} (#{String.slice(id, 0..7)}...) registered with PeerManager (priority: #{hosting_priority})")
    end

    {:noreply, state}
  end

  # Notice that a Reality2 node is now out of range.
  def handle_info({:r2node_lost, id}, state) do
    Logger.info("R2 Node lost: #{id}")

    # Notify all Sentants about the loss
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{activity: "r2_node_lost", id: id}
    })

    # Remove from PeerManager
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      AiReality2Transnet.PeerManager.remove_peer(id)
    end

    {:noreply, state}
  end

  # List of nodes found during a scan.
  def handle_info({:r2nodes, nodes}, state) do
    # TODO: notify the pathing Plugin (useful for checking and updating).

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{nodes: nodes}
    })

    {:noreply, state}
  end

  # Result of asking for a list of adapters.
  def handle_info({:adapters, adapters}, state) do
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        adapters: adapters,
        id: Reality2.Bootstrap.get(:node_id)
      }
    })

    {:noreply, state}
  end

  # GATT mesh data received from connected client
  def handle_info({:gatt_write, "mesh", data}, state) do
    Logger.debug("#{log_prefix()} GATT mesh data received")

    # Decode from bytes and forward to R2Mesh
    mesh_data = if is_list(data), do: :binary.list_to_bin(data), else: data

    if Code.ensure_loaded?(AiReality2Transnet.R2Mesh) do
      AiReality2Transnet.R2Mesh.handle_incoming(mesh_data)
    end

    {:noreply, state}
  end

  # GATT errors
  def handle_info({:error, reason}, state) do
    Logger.error("GATT error: #{reason}")
    {:noreply, state}
  end

  # PubSub message: Sentants changed (created, updated, deleted)
  # Refresh the query characteristic so clients see updated sentant list
  def handle_info({:sentants, action, sentant_data}, %{gatt_handle: handle} = state) do
    Logger.info("PubSub: Sentants #{action} - #{inspect(sentant_data)} - refreshing query characteristic")
    update_query_characteristic(handle)
    {:noreply, state}
  end

  def handle_info({:sentants, _action, _sentant_data}, state) do
    # No GATT handle yet, ignore
    {:noreply, state}
  end

  # PubSub message: Sentant signal received (mirrors GraphQL awaitSignal subscription)
  def handle_info({:sentant_signal, signal_data}, state) do
    %{id: id, event: event, parameters: parameters, passthrough: passthrough} = signal_data
    # Extract signal name if present, otherwise use event name as the signal
    signal = Map.get(signal_data, :signal, event)
    # Get node name from parameters (remote) or local node
    node_name = get_node_name_from_params(parameters)
    Logger.debug("PubSub event from #{node_name}: Sentant #{id} - #{signal}")

    # Broadcast to GATT clients via notification characteristic
    broadcast_signal(id, signal, event, parameters, passthrough)

    {:noreply, state}
  end

  # Catchall
  def handle_info(msg, state) do
    Logger.debug("Unhandled Bluetooth message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - starting various services
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_adapter_and_name({:ok, state}) do
    case AiReality2Transnet.Action.list_adapters_seq() do
      [] ->
        {:error, :no_adapters_found}

      [adapter | _] ->
        adapter_name =
          case adapter do
            %{name: id} when is_binary(id) -> id
            _ -> "hci0"
          end

        state =
          state
          |> Map.put(:adapter, adapter)
          |> Map.put(:adapter_name, adapter_name)

        {:ok, state}
    end
  end

  # Start up the BLE beacon on the previously found given adapter. Uses the ALTBeacon format.
  # Includes hosting_priority so other nodes can make informed host selection decisions.
  defp start_beacon({:ok, state}) do
    node_id = Reality2.Bootstrap.get(:node_id)
    node_name = Reality2.Bootstrap.get(:node_name)
    adapter_name = Map.get(state, :adapter_name, "hci0")

    # Get current hosting priority (0-100) based on node capabilities
    hosting_priority = get_hosting_priority()

    case AiReality2Transnet.Action.start_broadcast(
           @r2_company_id,
           node_id,
           1,
           2,
           -59,
           node_name,
           hosting_priority,
           adapter_name
         ) do
      {:ok, h} ->
        Logger.info("Node ID: #{node_id} beacon started on #{adapter_name} (priority: #{hosting_priority})")
        {:ok, Map.put(state, :r2_beacon, h)}

      {:error, reason} ->
        Logger.warning("start_beacon failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_beacon({:error, reason}), do: {:error, reason}

  # Get hosting priority from Wifi module if available, otherwise return basic priority
  defp get_hosting_priority do
    if Code.ensure_loaded?(AiReality2Transnet.Wifi) &&
       function_exported?(AiReality2Transnet.Wifi, :get_hosting_priority, 0) do
      AiReality2Transnet.Wifi.get_hosting_priority()
    else
      # Basic priority - can host but no special capabilities
      10
    end
  end

  # Start the GATT server for Sentant access
  defp start_gatt_server({:ok, state}) do
    adapter_name = Map.get(state, :adapter_name, "hci0")

    case AiReality2Transnet.Action.start_gatt_server(self(), adapter_name) do
      {:ok, handle} ->
        Logger.info("GATT Sentant Server started successfully")

        # Initialize the Query characteristic with current Sentants
        update_query_characteristic(handle)

        # Initialize the Join Offer characteristic with WiFi hotspot credentials
        update_join_offer_characteristic(handle)

        # TODO: Subscribe to Sentant signals via PubSub
        # Phoenix.PubSub.subscribe(YourPubSub, "sentant:signals")

        {:ok,
         Map.merge(state, %{
           gatt_handle: handle,
           events_sent: 0,
           signals_broadcast: 0,
           queries_processed: 0,
           connected_peers: %{}
         })}

      {:error, reason} ->
        Logger.warning("Failed to start GATT Sentant Server: #{reason}")
        {:error, reason}
    end
  end

  defp start_gatt_server({:error, reason}), do: {:error, reason}

  # Start watching for nearby Reality2 Nodes.
  defp start_watch({:ok, state}) do
    adapter_name = Map.get(state, :adapter_name, "hci0")
    company_id = @r2_company_id
    lost_after_ms = 30_000

    case AiReality2Transnet.Action.start_watching(self(), company_id, adapter_name, lost_after_ms) do
      {:ok, h} ->
        Logger.info("R2 watch started on #{adapter_name}")
        {:ok, Map.put(state, :r2_watch, h)}

      {:error, reason} ->
        Logger.warning("Failed to start R2 watch: #{reason}")
        {:error, reason}
    end
  end

  defp start_watch({:error, reason}), do: {:error, reason}

  # Subscribe to PubSub for Sentant signals
  defp subscribe_to_pubsub({:ok, state}) do
    # Subscribe to sentant signals from Reality2.PubSub (shared across all apps)
    Phoenix.PubSub.subscribe(Reality2.PubSub, "sentant:signals")
    Logger.debug("Subscribed to sentant:signals PubSub topic")
    {:ok, state}
  end

  defp subscribe_to_pubsub({:error, reason}), do: {:error, reason}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Beacon and Watch Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Stop the previously started BLE beacon.
  # defp stop_beacon(state, _params) do
  #   case Map.get(state, :r2_beacon) do
  #     nil ->
  #       {:ok, state}

  #     h ->
  #       AiReality2Transnet.Action.stop_broadcast(h)
  #       {:ok, Map.put(state, :r2_beacon, nil)}
  #   end
  # end

  # Stop watching for nearby Reality2 Nodes.
  # defp stop_watch(state, _params) do
  #   case Map.get(state, :r2_watch) do
  #     nil ->
  #       {:ok, state}

  #     h ->
  #       AiReality2Transnet.Action.stop_watching(h)
  #       {:ok, Map.put(state, :r2_watch, nil)}
  #   end
  # end

  # List the Bluetooth adapters on this device.
  defp list_adapters(state) do
    AiReality2Transnet.Action.list_adapters(self())
    {:noreply, state}
  end

  # Do a manual scan for nearby Reality2 Nodes.
  # After the given time, an __internal message is sent to all Sentants with an array of R2 node IDs.
  defp scan_nodes(state, parameters) do
    timeout =
      case R2Map.get(parameters, :timeout, 5000) do
        "" -> 5000
        v -> v
      end

    AiReality2Transnet.Action.scan_nodes(self(), timeout)
    {:noreply, state}
  end

  defp reset_nodes(state) do
    AiReality2Transnet.Action.reset_nodes(state.r2_watch)
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GATT Server - sentantSend Mutation Handler
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp parse_sentant_send(data) when is_list(data) do
    data |> :binary.list_to_bin() |> parse_sentant_send()
  end

  defp parse_sentant_send(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"id" => id, "event" => event} = mutation} ->
        {:ok,
         %{
           id: id,
           event: event,
           parameters: Map.get(mutation, "parameters", %{}),
           passthrough: Map.get(mutation, "passthrough")
         }}

      {:ok, _} ->
        {:error, "missing_required_fields_id_and_event"}

      {:error, reason} ->
        {:error, "json_decode_error: #{inspect(reason)}"}
    end
  end

  defp handle_sentant_send(
         %{id: id, event: event, parameters: parameters, passthrough: passthrough},
         %{gatt_handle: handle} = state
       ) do
    Logger.info("Processing sentantSend: id=#{id}, event=#{event}")

    # Mirror GraphQL resolver pattern: validate Sentant exists and event is allowed
    case Reality2.Sentants.read(%{id: id}, :definition) do
      {:ok, sentant} ->
        # Validate event is allowed (same as GraphQL does)
        events = get_event_list(Map.get(sentant, :events, []))

        if Enum.member?(events, event) do
          # Send the event to the Sentant
          case Reality2.Sentants.sendto(%{id: id}, %{
                 event: event,
                 parameters: parameters,
                 passthrough: passthrough
               }) do
            {:ok, _pid} ->
              # Success response
              response = %{
                type: "mutation_response",
                mutation: "sentantSend",
                success: true,
                version: @protocol_version,
                timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
                data: sentant
              }

              encode_and_notify(handle, response)
              {:noreply, %{state | events_sent: state.events_sent + 1}}

            {:error, reason} ->
              # Error sending event
              error_response = %{
                type: "mutation_response",
                mutation: "sentantSend",
                success: false,
                error: to_string(reason),
                version: @protocol_version,
                timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
              }

              encode_and_notify(handle, error_response)
              {:noreply, state}
          end
        else
          # Event not allowed
          error_response = %{
            type: "mutation_response",
            mutation: "sentantSend",
            success: false,
            error: "invalid_event",
            version: @protocol_version,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }

          encode_and_notify(handle, error_response)
          {:noreply, state}
        end

      {:error, reason} ->
        # Sentant not found
        error_response = %{
          type: "mutation_response",
          mutation: "sentantSend",
          success: false,
          error: to_string(reason),
          version: @protocol_version,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        encode_and_notify(handle, error_response)
        {:noreply, state}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GATT Server - Data Fetching Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp fetch_all_sentants do
    # TODO: Replace with your actual Sentant registry
    # YourSentantModule.list_all_sentants()
    # |> Enum.map(&format_sentant/1)
    #
    {:ok, sentants} = Reality2.Sentants.read_all(:definition)
    sentants_map = Enum.map(sentants, fn sentant -> sentant end)
    Logger.debug("Fetched all sentants: #{inspect(sentants_map, pretty: false, limit: 500)}")
    sentants_map
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GATT Server - Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Extract event names from event list (mirrors GraphQL resolver pattern)
  defp get_event_list(events) when is_list(events) do
    Enum.map(events, &Map.get(&1, :name))
  end

  defp get_event_list(_), do: []

  # Extract node name from parameters (for remote signals) or fall back to local node name
  defp get_node_name_from_params(parameters) when is_map(parameters) do
    # Try various keys that might contain node name from remote nodes
    Map.get(parameters, :node_name) ||
      Map.get(parameters, "node_name") ||
      Map.get(parameters, :source_node) ||
      Map.get(parameters, "source_node") ||
      Reality2.Bootstrap.get(:node_name, "local")
  end

  defp get_node_name_from_params(_), do: Reality2.Bootstrap.get(:node_name, "local")

  defp update_query_characteristic(handle) do
    sentants = fetch_all_sentants()
    Logger.info("update_query_characteristic: Found #{length(sentants)} sentants")

    # Create compact version with only essential fields for BLE transmission
    # Remove parameters to reduce size - they're just type hints for the UI
    compact_sentants =
      Enum.map(sentants, fn sentant ->
        %{
          id: Map.get(sentant, :id),
          name: Map.get(sentant, :name),
          events:
            Map.get(sentant, :events, [])
            |> Enum.map(fn event ->
              %{event: Map.get(event, :event)}
            end),
          signals: Map.get(sentant, :signals, [])
        }
      end)

    message = %{
      type: "sentant_all_response",
      version: @protocol_version,
      count: length(compact_sentants),
      data: compact_sentants
    }

    case Jason.encode(message) do
      {:ok, json} ->
        json = truncate_if_needed(json, @max_characteristic_size)
        binary_data = :binary.bin_to_list(json)

        Logger.debug("Writing #{byte_size(json)} bytes to query characteristic")

        result =
          AiReality2Transnet.Action.gatt_write_characteristic(
            handle,
            "00002a57-0000-1000-8000-00805f9b34fb",
            binary_data
          )

        case result do
          :ok ->
            Logger.debug("Successfully wrote query characteristic data")
            :ok

          :error ->
            Logger.error(
              "Failed to write query characteristic - gatt_write_characteristic returned :error"
            )

            :error

          other ->
            Logger.error(
              "Unexpected return value from gatt_write_characteristic: #{inspect(other)}"
            )

            :error
        end

      {:error, reason} ->
        Logger.error("Failed to encode Sentants data: #{inspect(reason)}")
        :error
    end
  end

  defp update_join_offer_characteristic(handle) do
    # Use GattProtocol to encode WiFi hotspot join offer
    json = AiReality2Transnet.GattProtocol.encode_join_offer()
    binary_data = :binary.bin_to_list(json)

    Logger.info("Writing #{byte_size(json)} bytes to join offer characteristic")

    result =
      AiReality2Transnet.Action.gatt_write_characteristic(
        handle,
        "00001235-0000-1000-8000-00805f9b34fb",
        binary_data
      )

    case result do
      :ok ->
        Logger.info("Successfully wrote join offer characteristic data")
        :ok

      :error ->
        Logger.error("Failed to write join offer characteristic")
        :error

      other ->
        Logger.error("Unexpected return from gatt_write_characteristic: #{inspect(other)}")
        :error
    end
  end

  defp encode_and_notify(handle, message) do
    case Jason.encode(message) do
      {:ok, json} ->
        json = truncate_if_needed(json, @max_characteristic_size)
        binary_data = :binary.bin_to_list(json)
        AiReality2Transnet.Action.gatt_notify(handle, binary_data)

      {:error, reason} ->
        Logger.error("Failed to encode message: #{inspect(reason)}")
        :error
    end
  end

  defp send_error_notification(handle, error_type, error_message) do
    message = %{
      type: "error",
      version: @protocol_version,
      error_type: error_type,
      message: error_message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    encode_and_notify(handle, message)
  end

  defp truncate_if_needed(json, max_size) when byte_size(json) > max_size do
    truncated = binary_part(json, 0, max_size - 30)
    truncated <> "...\",\"truncated\":true}"
  end

  defp truncate_if_needed(json, _max_size), do: json

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Peer Connection Helpers (DEPRECATED - Use WiFi Mesh HTTP)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # NOTE: These functions are deprecated. BLE is now for discovery only.
  # For Sentant queries, use WiFi Mesh HTTP via WifiServer module.
  #
  # Old flow (removed):
  #   BLE Beacon → GATT Connect → Read Sentants (512 byte limit!)
  #
  # New flow (current):
  #   BLE Beacon → Register with PeerManager → Upgrade to WiFi Mesh → HTTP Query
  #
  # To query remote sentants:
  #   {:ok, peer} = AiReality2Transnet.PeerManager.get_peer(node_id)
  #   {:ok, sentants} = AiReality2Transnet.WifiServer.query_peer_sentants(peer.ipv6_link_local)
end
