defmodule AiReality2Transnet.Bluetooth do
  # *******************************************************************************************************************************************
  @moduledoc """
  Bluetooth transport for Reality2 Transient Networks.

  **Hotspot Architecture Protocol**
  1. **Beacon (AltBeacon)**: Discovery and capability advertisement
     - Broadcasts node capabilities (can_host_ap, is_fixed_anchor, etc.)
     - Encodes real-time status (client_count, upstream_quality)
     - Scans for peer beacons
  2. **GATT**: Bootstrap exchange for WiFi hotspot connection
     - Node info characteristic (minimal metadata)
     - Join offer characteristic (SSID, PSK, rendezvous IP)
  3. **WiFi Hotspot**: WPA2-PSK access point or client connection
  4. **GraphQL (port 4005)**: sentantAll exchange and sentant control

  This module:
  - Broadcasts and watches Reality2 beacons with capability flags
  - Hosts GATT server for bootstrap exchange (join offers)
  - Registers discovered peers with `AiReality2Transnet.PeerManager`
  - Handles local Sentant commands via GenServer.cast

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  alias Reality2.Sentants, as: Sentants
  alias Reality2.Helpers.R2Map, as: R2Map
  use GenServer, restart: :transient
  require Logger
  import Bitwise

  # Protocol version
  @protocol_version "1.0"

  # Configuration helpers - load at runtime for better testability
  defp r2_company_id, do: Application.get_env(:ai_reality2_transnet, :r2_company_id, 0xFFFF)

  defp max_characteristic_size,
    do: Application.get_env(:ai_reality2_transnet, :max_characteristic_size, 4096)

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Broadcast a signal to GATT clients via notification characteristic.

  ## Parameters
  - sentant_id: The ID of the sentant broadcasting the signal
  - signal: The signal name
  - event: The event name
  - parameters: Event parameters
  - passthrough: Optional passthrough data
  """
  def broadcast_signal(sentant_id, signal, event, parameters, passthrough \\ nil) do
    GenServer.cast(
      __MODULE__,
      {:broadcast_signal, sentant_id, signal, event, parameters, passthrough}
    )
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
        connected_peers: %{}
      })

    {:ok, initial_state}
    |> get_adapter_and_name()
    |> start_beacon()
    |> start_gatt_server()
    |> start_watch()
    |> subscribe_to_pubsub()
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
  def handle_call(
        {:send_to_peer, _peer_id, _sentant_id, _event, _params, _passthrough},
        _from,
        state
      ) do
    {:reply, {:error, :use_wifi_hotspot}, state}
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
    # Broadcasts optional bootstrap notifications
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

  # Handle broadcast_signal when GATT server is not initialized
  def handle_cast(
        {:broadcast_signal, sentant_id, _signal, _event, _parameters, _passthrough},
        state
      ) do
    Logger.warning("Cannot broadcast signal from #{sentant_id}: GATT server not initialized")
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_info (return values from Rust NIFs and GATT events)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true

  # GATT Server Events
  def handle_info(:gatt_server_started, state) do
    Logger.info("GATT Bootstrap Server is ready and discoverable")
    {:noreply, state}
  end

  # GATT bootstrap refresh (Write)
  # A write to the "command" characteristic triggers a refresh of bootstrap characteristics.
  def handle_info({:gatt_write, "command", _data}, state) do
    Logger.debug("GATT bootstrap refresh requested")
    update_query_characteristic(state.gatt_handle)
    update_join_offer_characteristic(state.gatt_handle)
    new_state = %{state | queries_processed: state.queries_processed + 1}
    {:noreply, new_state}
  end

  # GATT network command (Write)
  # Clients write a small JSON command to coordinate hotspot join/leave.
  def handle_info({:gatt_write, "data", data}, state) do
    Logger.info("GATT network command received")

    case AiReality2Transnet.GattProtocol.handle_network_command_write(data) do
      :ok ->
        # Connection state may have changed; refresh join offer.
        update_join_offer_characteristic(state.gatt_handle)
        {:noreply, state}

      {:error, reason} ->
        send_error_notification(state.gatt_handle, "hotspot_command_failed", to_string(reason))
        {:noreply, state}
    end
  end

  # The details of a Reality2 node that has been found nearby.
  def handle_info({:r2node_found, id, info}, state) do
    Logger.info("R2 Node discovered: #{id}")

    # Extract BLE address from info
    address = Map.get(info, :address)

    # Try to decode capabilities from beacon major/minor fields if present
    # Otherwise use defaults (all R2 nodes can potentially host WiFi)
    capabilities = case {Map.get(info, :major), Map.get(info, :minor)} do
      {major, minor} when is_integer(major) and is_integer(minor) ->
        # Decode from beacon data
        flags = decode_beacon_flags(major)
        status = decode_beacon_status(minor)
        Map.merge(flags, status) |> Map.put(:wifi_hotspot, flags.can_host_ap)

      _ ->
        # Default capabilities - assume peer can host WiFi
        %{
          wifi_hotspot: true,
          can_host_ap: true,
          bluetooth: true,
          supports_handover: true
        }
    end

    # Merge capabilities into info for registration
    info_with_caps = Map.put(info, :capabilities, capabilities)

    # Notify all Sentants about the discovery
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        activity: "r2_node_found",
        id: id,
        info: info,
        address: address
      }
    })

    # Register peer with PeerManager including capabilities
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      AiReality2Transnet.PeerManager.register_peer(id, info_with_caps)
      Logger.info("Peer #{String.slice(id, 0..7)}... registered with capabilities: #{inspect(capabilities)}")

      # Still try GATT for more detailed info (node_name, sentant_count, etc.)
      if address do
        fetch_peer_capabilities(address, id, state)
      end
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

  # GATT errors (non-critical - we use default capabilities from beacon)
  def handle_info({:error, reason}, state) do
    Logger.debug("[Bluetooth] GATT error (non-critical): #{reason}")
    {:noreply, state}
  end

  # PubSub message: Sentant signal received
  def handle_info({:sentant_signal, signal_data}, state) do
    %{id: id, event: event, parameters: parameters, passthrough: passthrough} = signal_data
    Logger.debug("Sentant signal received: #{id} - #{event}")

    # Broadcast to GATT clients via notification characteristic
    broadcast_signal(id, event, event, parameters, passthrough)

    {:noreply, state}
  end

  # GATT connection established (with address)
  def handle_info({:gatt_connected, address}, state) when is_binary(address) do
    Logger.debug("[Bluetooth] GATT connected to #{address}")
    # Service discovery should follow automatically in the NIF
    {:noreply, state}
  end

  # GATT connection established (without address - older NIF format)
  def handle_info(:gatt_connected, state) do
    Logger.debug("[Bluetooth] GATT connected (address unknown)")
    {:noreply, state}
  end

  # GATT services discovered - now we can read characteristics
  def handle_info({:gatt_services_discovered, address, _services}, state) do
    Logger.debug("[Bluetooth] GATT services discovered for #{address}")

    # Look up which node_id this address corresponds to
    case Process.get({:pending_gatt_connect, address}) do
      nil ->
        Logger.warning("[Bluetooth] Services discovered for unknown address: #{address}")
        {:noreply, state}

      node_id ->
        # Don't delete yet - we still need it for the read response
        Process.put({:pending_gatt_read, address}, node_id)
        Process.delete({:pending_gatt_connect, address})

        # Now read the node_info characteristic
        adapter_name = Map.get(state, :adapter_name, "hci0")
        read_peer_node_info(address, node_id, adapter_name)
        {:noreply, state}
    end
  end

  # Handle older format without address
  def handle_info({:gatt_services_discovered, services}, state) when is_list(services) do
    Logger.debug("[Bluetooth] GATT services discovered (no address): #{length(services)} services")
    {:noreply, state}
  end

  # GATT client read response - capability fetch completed
  def handle_info({:gatt_read, address, value}, state) when is_list(value) do
    # Convert byte list to binary string
    json_data = :binary.list_to_bin(value)

    # Look up which node_id this address corresponds to
    case Process.get({:pending_gatt_read, address}) do
      nil ->
        Logger.warning("[Bluetooth] Received GATT read response for unknown address: #{address}")
        {:noreply, state}

      node_id ->
        Process.delete({:pending_gatt_read, address})
        handle_gatt_node_info_response(node_id, json_data)
        {:noreply, state}
    end
  end

  def handle_info({:gatt_read, value}, state) when is_list(value) do
    # Older format without address - try to handle gracefully
    Logger.debug("[Bluetooth] Received GATT read (no address): #{byte_size(:binary.list_to_bin(value))} bytes")
    {:noreply, state}
  end

  def handle_info({:gatt_read_error, address, reason}, state) do
    Logger.warning("[Bluetooth] GATT read failed for #{address}: #{inspect(reason)}")
    Process.delete({:pending_gatt_read, address})
    {:noreply, state}
  end

  def handle_info({:gatt_read_error, reason}, state) do
    Logger.warning("[Bluetooth] GATT read failed: #{inspect(reason)}")
    {:noreply, state}
  end

  # GATT connection failed
  def handle_info({:gatt_connect_error, address, reason}, state) do
    Logger.warning("[Bluetooth] GATT connect failed for #{address}: #{inspect(reason)}")
    Process.delete({:pending_gatt_connect, address})
    {:noreply, state}
  end

  def handle_info({:gatt_error, reason}, state) do
    Logger.warning("[Bluetooth] GATT error: #{inspect(reason)}")
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
    node_name = Reality2.Bootstrap.get(:node_name, "R2Node")
    adapter_name = Map.get(state, :adapter_name, "hci0")

    # Encode capabilities into major/minor fields
    # Major field encodes role flags
    major = encode_beacon_flags()
    # Minor field encodes client count and quality
    minor = encode_beacon_status()

    case AiReality2Transnet.Action.start_broadcast(
           r2_company_id(),
           node_id,
           major,
           minor,
           -59,
           node_name,
           adapter_name
         ) do
      {:ok, h} ->
        Logger.info("#{node_name} (#{node_id}) beacon started on #{adapter_name}")
        {:ok, Map.put(state, :r2_beacon, h)}

      {:error, reason} ->
        Logger.warning("start_beacon failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_beacon({:error, reason}), do: {:error, reason}

  # Start the GATT server for Sentant access
  defp start_gatt_server({:ok, state}) do
    adapter_name = Map.get(state, :adapter_name, "hci0")

    case AiReality2Transnet.Action.start_gatt_server(self(), adapter_name) do
      {:ok, handle} ->
        Logger.info("GATT Sentant Server started successfully")

        # Initialize the Node Info characteristic (minimal bootstrap)
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
    company_id = r2_company_id()
    # Time before a node is considered "lost" - configurable via app env
    lost_after_ms = Application.get_env(:ai_reality2_transnet, :node_lost_timeout_ms, 60_000)

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
  # GATT Server - Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp update_query_characteristic(handle) do
    # Legacy name retained: this characteristic now carries *minimal node info*.
    # Full Sentant directory and all higher-level interactions occur over Wi-Fi mesh.
    node_id = Reality2.Bootstrap.get(:node_id)
    json = AiReality2Transnet.GattProtocol.encode_node_info(node_id)
    binary_data = :binary.bin_to_list(json)

    # Prefer the dedicated node-info characteristic UUID; fall back to the legacy query UUID if needed.
    preferred_uuid = AiReality2Transnet.GattProtocol.node_info_uuid()
    legacy_uuid = "00002a57-0000-1000-8000-00805f9b34fb"

    case AiReality2Transnet.Action.gatt_write_characteristic(handle, preferred_uuid, binary_data) do
      :ok ->
        :ok

      _ ->
        Logger.warning(
          "Failed to write node_info to #{preferred_uuid}; falling back to legacy UUID #{legacy_uuid}"
        )

        AiReality2Transnet.Action.gatt_write_characteristic(handle, legacy_uuid, binary_data)
    end
  end

  defp update_join_offer_characteristic(handle) do
    # Use GattProtocol to encode hotspot join offer
    json = AiReality2Transnet.GattProtocol.encode_join_offer()
    binary_data = :binary.bin_to_list(json)

    Logger.info("Writing #{byte_size(json)} bytes to join offer characteristic")

    result =
      AiReality2Transnet.Action.gatt_write_characteristic(
        handle,
        # Same UUID, different meaning now
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
        json = truncate_if_needed(json, max_characteristic_size())
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
  # GATT Client - Fetch Peer Capabilities
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Process the GATT node_info response and update peer capabilities
  defp handle_gatt_node_info_response(node_id, json_data) do
    case AiReality2Transnet.GattProtocol.decode_node_info(json_data) do
      {:ok, node_info} ->
        Logger.info("[Bluetooth] Received capabilities for peer #{String.slice(node_id, 0..7)}...")

        # Extract capabilities from the decoded info
        capabilities = Map.get(node_info, :capabilities, %{})

        # Update peer with capabilities (enables WiFi negotiation)
        if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
          AiReality2Transnet.PeerManager.update_peer_capabilities(node_id, capabilities)

          # Also update node_name if available
          if node_name = node_info[:node_name] do
            # Re-register with node_name to update the mapping
            AiReality2Transnet.PeerManager.register_peer(node_id, %{node_name: node_name})
          end

          Logger.info("[Bluetooth] Peer #{String.slice(node_id, 0..7)}... capabilities: #{inspect(capabilities)}")
        end

        :ok

      {:error, reason} ->
        Logger.warning("[Bluetooth] Failed to decode node_info from peer #{String.slice(node_id, 0..7)}...: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Initiates a GATT connection to fetch peer capabilities after beacon discovery.
  # Flow: connect -> service discovery -> read characteristic
  defp fetch_peer_capabilities(address, node_id, state) do
    adapter_name = Map.get(state, :adapter_name, "hci0")

    Logger.debug("[Bluetooth] Connecting to peer #{String.slice(node_id, 0..7)}... at #{address}")

    # Store pending connection so we can match response to node_id
    Process.put({:pending_gatt_connect, address}, node_id)

    case AiReality2Transnet.Action.gatt_connect(self(), address, adapter_name) do
      :ok ->
        Logger.debug("[Bluetooth] GATT connect initiated for #{address}")
        :ok

      {:error, reason} ->
        Logger.warning("[Bluetooth] Failed to initiate GATT connect for #{address}: #{inspect(reason)}")
        Process.delete({:pending_gatt_connect, address})
        {:error, reason}
    end
  end

  # After GATT connection and service discovery, read the node_info characteristic
  defp read_peer_node_info(address, node_id, adapter_name) do
    node_info_uuid = AiReality2Transnet.GattProtocol.node_info_uuid()

    Logger.debug("[Bluetooth] Reading node_info from peer #{String.slice(node_id, 0..7)}... at #{address}")

    # Store pending read so we can match response to node_id
    Process.put({:pending_gatt_read, address}, node_id)

    case AiReality2Transnet.Action.gatt_read_characteristic(self(), address, node_info_uuid, adapter_name) do
      :ok ->
        Logger.debug("[Bluetooth] GATT read initiated for #{address}")
        :ok

      {:error, reason} ->
        Logger.warning("[Bluetooth] Failed to initiate GATT read for #{address}: #{inspect(reason)}")
        Process.delete({:pending_gatt_read, address})
        {:error, reason}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Beacon Encoding/Decoding - Role Flags and Status
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Encodes node capabilities into beacon major field (16-bit).
  #
  # Bit layout:
  # - Bit 0: can_host_ap (currently hosting hotspot)
  # - Bit 1: is_fixed_anchor (POS/fixed device)
  # - Bit 2: has_upstream (connected to upstream)
  # - Bit 3: supports_handover
  # - Bits 4-15: Reserved
  #
  # Returns: Integer 0-65535 for beacon major field
  defp encode_beacon_flags do
    flags = 0
    flags = if can_host_ap?(), do: flags ||| 0x0001, else: flags
    flags = if is_fixed_anchor?(), do: flags ||| 0x0002, else: flags
    flags = if has_upstream?(), do: flags ||| 0x0004, else: flags
    # Always support handover
    flags = flags ||| 0x0008
    flags
  end

  # Encodes node status into beacon minor field (16-bit).
  #
  # Layout:
  # - Byte 0 (bits 0-7): client_count (0-255)
  # - Byte 1 (bits 8-15): upstream_quality (0-100, scaled to 0-255)
  #
  # Returns: Integer 0-65535 for beacon minor field
  defp encode_beacon_status do
    client_count = get_client_count()
    upstream_quality = get_upstream_quality()

    # Pack into 16 bits: [quality:8][client_count:8]
    quality_byte = div(upstream_quality * 255, 100)
    quality_byte <<< 8 ||| client_count
  end

  @doc """
  Decodes beacon major field into capabilities map.

  ## Parameters
  - major: 16-bit integer from beacon

  ## Returns
  Map with capability flags
  """
  def decode_beacon_flags(major) when is_integer(major) do
    %{
      can_host_ap: (major &&& 0x0001) != 0,
      is_fixed_anchor: (major &&& 0x0002) != 0,
      has_upstream: (major &&& 0x0004) != 0,
      supports_handover: (major &&& 0x0008) != 0
    }
  end

  @doc """
  Decodes beacon minor field into status map.

  ## Parameters
  - minor: 16-bit integer from beacon

  ## Returns
  Map with status information
  """
  def decode_beacon_status(minor) when is_integer(minor) do
    client_count = minor &&& 0xFF
    quality_raw = minor >>> 8 &&& 0xFF
    upstream_quality = div(quality_raw * 100, 255)

    %{
      client_count: client_count,
      upstream_quality: upstream_quality
    }
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Node Capability Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Check if this node can/is hosting a hotspot
  defp can_host_ap? do
    case AiReality2Transnet.ConnectionManager.get_hosting_config() do
      {:ok, config} -> config.active
      _ -> false
    end
  end

  # Check if this is a fixed anchor node
  defp is_fixed_anchor? do
    # Check environment variable or config
    case Application.get_env(:ai_reality2_transnet, :node_role) do
      :fixed_anchor -> true
      :pos -> true
      _ -> false
    end
  end

  # Check if node has upstream connectivity
  defp has_upstream? do
    case AiReality2Transnet.ConnectionManager.get_connection_status() do
      {:ok, status} -> status.state == :connected_as_client
      _ -> false
    end
  end

  # Get current client count if hosting
  defp get_client_count do
    case AiReality2Transnet.ConnectionManager.get_hosting_config() do
      {:ok, _config} ->
        # Get WiFi interface
        case AiReality2Transnet.Wifi.list_adapters() do
          {:ok, [adapter | _]} ->
            case AiReality2Transnet.Wifi.get_connected_clients(adapter.interface) do
              {:ok, clients} -> min(length(clients), 255)
              _ -> 0
            end

          _ ->
            0
        end

      _ ->
        0
    end
  end

  # Get upstream quality score (0-100)
  defp get_upstream_quality do
    case AiReality2Transnet.ConnectionManager.get_connection_status() do
      {:ok, status} when status.state == :connected_as_client ->
        # Convert signal strength to quality (0-100)
        # -45 dBm (excellent) → 100
        # -85 dBm (poor) → 0
        case status.signal_strength do
          nil ->
            50

          signal ->
            quality = 100 - abs(signal + 45) * 2.5
            round(max(0, min(100, quality)))
        end

      _ ->
        # Not connected, but might have wired/LTE
        # TODO: Check for wired/LTE connection
        0
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Architecture Notes: BLE Discovery + WiFi Data Exchange
  # -----------------------------------------------------------------------------------------------------------------------------------------
  #
  # BLE is used for discovery only (beacons + GATT bootstrap).
  # Data exchange happens over WiFi hotspot connections using Reality2Web GraphQL.
  #
  # Discovery flow:
  #   1. BLE Beacon → Discovered by peer
  #   2. GATT Bootstrap → Exchange node info + join offer
  #   3. WiFi Connect → Client connects to host's hotspot
  #   4. GraphQL Query → Retrieve sentantAll via HTTP (port 4005)
  #
  # To query remote sentants from PNS or other code:
  #   {:ok, peer} = AiReality2Transnet.PeerManager.get_peer(node_id)
  #   # Use GraphQL to query: http://<peer_ip>:4005/reality2
end
