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

  # Default Company ID for R2 manufacturer data.
  # TODO: Replace with an assigned company ID.
  @r2_company_id 0xFFFF
  @max_characteristic_size 512
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
    GenServer.call(__MODULE__, {:send_to_peer, peer_node_id, sentant_id, event, parameters, passthrough})
  end

  @doc """
  Get list of connected peer nodes.

  ## Returns
  - `%{node_id => %{address, sentants, connected_at}}`
  """
  def get_connected_peers do
    GenServer.call(__MODULE__, :get_connected_peers)
  end

  @doc """
  Get a specific peer's information.

  ## Returns
  - `{:ok, peer_info}` - Peer found
  - `{:error, :not_found}` - Peer not connected
  """
  def get_peer(peer_node_id) do
    GenServer.call(__MODULE__, {:get_peer, peer_node_id})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(state) do
    # Find the bluetooth adapter (taking the first one)
    # TODO: Handle multiple adapters and/or set adapter to use as an Environment variable

    {:ok, state}
    |> get_adapter_and_name()
    |> start_beacon()
    |> start_gatt_server()
    |> start_watch()
    |> subscribe_to_pubsub()
  end

  @impl true
  def terminate(_reason, state) do
    # Stop watcher + beacon + GATT server using the stored keys
    IO.puts("Terminating Bluetooth service")
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
  def handle_call(:get_connected_peers, _from, state) do
    {:reply, Map.get(state, :connected_peers, %{}), state}
  end

  @impl true
  def handle_call({:get_peer, peer_id}, _from, state) do
    case Map.get(state.connected_peers, peer_id) do
      nil -> {:reply, {:error, :not_found}, state}
      peer_info -> {:reply, {:ok, peer_info}, state}
    end
  end

  @impl true
  def handle_call({:send_to_peer, peer_id, sentant_id, event, params, passthrough}, _from, state) do
    case Map.get(state.connected_peers, peer_id) do
      nil ->
        {:reply, {:error, :peer_not_connected}, state}

      peer_info ->
        mutation = %{
          id: sentant_id,
          event: event,
          parameters: params,
          passthrough: passthrough
        }

        mutation_json = Jason.encode!(mutation)
        data_uuid = "00002a58-0000-1000-8000-00805f9b34fb"

        result = AiReality2Transnet.Action.gatt_write_to_device(
          peer_info.address,
          data_uuid,
          mutation_json
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
        Logger.debug("Broadcast signal from Sentant #{sentant_id}: #{signal}")
        new_state = %{state | signals_broadcast: state.signals_broadcast + 1}
        {:noreply, new_state}

      :error ->
        Logger.error("Failed to broadcast signal")
        {:noreply, state}
    end
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
    Logger.info("R2 Node discovered: #{id}")

    # Extract BLE address from info
    address = Map.get(info, :address)

    # Notify all Sentants about the discovery
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        activity: "r2_node_found",
        id: id,
        info: info
      }
    })

    # Automatically connect as GATT client and read peer's sentants
    case connect_to_peer(address, id) do
      {:ok, peer_info} ->
        Logger.info("Successfully connected to peer #{id}, discovered #{length(peer_info.sentants)} sentants")

        # Notify Sentants about peer's sentants
        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "peer_sentants_discovered",
            peer_id: id,
            peer_address: address,
            sentants: peer_info.sentants
          }
        })

        # Add to connected peers
        new_peers = Map.put(state.connected_peers, id, peer_info)
        {:noreply, %{state | connected_peers: new_peers}}

      {:error, reason} ->
        Logger.warning("Failed to connect to peer #{id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Notice that a Reality2 node is now out of range.
  def handle_info({:r2node_lost, id}, state) do
    Logger.info("R2 Node lost: #{id}")

    # Notify all Sentants about the loss
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{activity: "r2_node_lost", id: id}
    })

    # Remove from connected peers
    new_peers = Map.delete(state.connected_peers, id)
    {:noreply, %{state | connected_peers: new_peers}}
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

  # GATT errors
  def handle_info({:error, reason}, state) do
    Logger.error("GATT error: #{reason}")
    {:noreply, state}
  end

  # PubSub message: Sentant signal received (mirrors GraphQL awaitSignal subscription)
  def handle_info({:sentant_signal, signal_data}, state) do
    %{id: id, event: event, parameters: parameters, passthrough: passthrough} = signal_data
    Logger.debug("Sentant signal received: #{id} - #{event}")

    # Broadcast to GATT clients via notification characteristic
    broadcast_signal(id, event, event, parameters, passthrough)

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
  defp start_beacon({:ok, state}) do
    node_id = Reality2.Bootstrap.get(:node_id)
    adapter_name = Map.get(state, :adapter_name, "hci0")

    case AiReality2Transnet.Action.start_broadcast(
           @r2_company_id,
           node_id,
           1,
           2,
           -59,
           adapter_name
         ) do
      {:ok, h} ->
        IO.puts("|-- Node ID: #{node_id} beacon started on #{adapter_name}")
        {:ok, Map.put(state, :r2_beacon, h)}

      {:error, reason} ->
        IO.puts("|-- start_beacon failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_beacon({:error, reason}), do: {:error, reason}

  # Start the GATT server for Sentant access
  defp start_gatt_server({:ok, state}) do
    adapter_name = Map.get(state, :adapter_name, "hci0")

    case AiReality2Transnet.Action.start_gatt_server(self(), adapter_name) do
      {:ok, handle} ->
        IO.puts("|-- GATT Sentant Server started successfully")

        # Initialize the Query characteristic with current Sentants
        update_query_characteristic(handle)

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
        IO.puts("|-- Failed to start GATT Sentant Server: #{reason}")
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
        IO.puts("|-- R2 watch started on #{adapter_name}")
        {:ok, Map.put(state, :r2_watch, h)}

      {:error, reason} ->
        IO.puts("|-- Failed to start R2 watch: #{reason}")
        {:error, reason}
    end
  end

  defp start_watch({:error, reason}), do: {:error, reason}

  # Subscribe to PubSub for Sentant signals
  defp subscribe_to_pubsub({:ok, state}) do
    # Subscribe to sentant signals from Reality2.PubSub (shared across all apps)
    Phoenix.PubSub.subscribe(Reality2.PubSub, "sentant:signals")
    IO.puts("|-- Subscribed to sentant:signals PubSub topic")
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

    IO.inspect(sentants_map)

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

  defp update_query_characteristic(handle) do
    sentants = fetch_all_sentants()

    message = %{
      type: "sentant_all_response",
      version: @protocol_version,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      count: length(sentants),
      data: sentants
    }

    case Jason.encode(message) do
      {:ok, json} ->
        json = truncate_if_needed(json, @max_characteristic_size)
        binary_data = :binary.bin_to_list(json)

        AiReality2Transnet.Action.gatt_write_characteristic(
          handle,
          "00002a57-0000-1000-8000-00805f9b34fb",
          binary_data
        )

      {:error, reason} ->
        Logger.error("Failed to encode Sentants data: #{inspect(reason)}")
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
  # Peer Connection Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Connect to a peer node as a GATT client and read its sentants
  defp connect_to_peer(address, node_id) do
    with {:ok, _services} <- AiReality2Transnet.Action.gatt_connect(address),
         {:ok, sentants_data} <- read_peer_sentants(address),
         {:ok, sentants_response} <- Jason.decode(sentants_data) do

      # Extract sentants array from response
      sentants = Map.get(sentants_response, "data", [])

      # Build peer info structure
      peer_info = %{
        address: address,
        node_id: node_id,
        sentants: sentants,
        sentant_count: length(sentants),
        connected_at: DateTime.utc_now()
      }

      {:ok, peer_info}
    else
      {:error, reason} = error ->
        Logger.debug("Peer connection failed at some step: #{inspect(reason)}")
        error

      other ->
        Logger.debug("Unexpected peer connection result: #{inspect(other)}")
        {:error, :connection_failed}
    end
  end

  # Read the query characteristic (sentantAll) from a peer node
  defp read_peer_sentants(address) do
    query_uuid = "00002a57-0000-1000-8000-00805f9b34fb"

    case AiReality2Transnet.Action.gatt_read_characteristic(address, query_uuid) do
      {:ok, data} when is_list(data) ->
        # Convert list of bytes to string
        binary_data = :binary.list_to_bin(data)
        {:ok, binary_data}

      {:ok, data} when is_binary(data) ->
        {:ok, data}

      {:error, reason} = error ->
        Logger.debug("Failed to read peer sentants: #{inspect(reason)}")
        error

      other ->
        Logger.debug("Unexpected read result: #{inspect(other)}")
        {:error, :read_failed}
    end
  end
end
