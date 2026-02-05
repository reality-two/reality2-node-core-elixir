defmodule Reality2Transnet.Bluetooth do
  # *******************************************************************************************************************************************
  @moduledoc """
  Bluetooth module for Transient Networks. Handles BLE beacons, node discovery, and GATT server
  for Sentant access. Calls into the Rust NIFs detailed in Reality2Transnet.Action.

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

  # BLE Watchdog settings - detect and recover from stale discovery
  # Aggressive timeouts for wearable responsiveness
  @watchdog_interval_ms 15_000        # Check every 15 seconds
  @ble_stale_threshold_ms 45_000      # Consider stale after 45 seconds without peers

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
  Pauses BLE scanning to free the adapter for GATT client connections.
  Must call `resume_scanning/0` when done.
  """
  def pause_scanning do
    GenServer.call(__MODULE__, :pause_scanning)
  end

  @doc """
  Resumes BLE scanning after a pause.
  """
  def resume_scanning do
    GenServer.call(__MODULE__, :resume_scanning)
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

  @doc """
  Refresh the BLE beacon with current trust group identity.

  Call this after joining or leaving a trust group to update the beacon's
  compressed trust group ID so other nodes see the correct trust group membership.
  """
  def refresh_beacon do
    GenServer.call(__MODULE__, :refresh_beacon)
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
        bluetooth_available: false,
        # BLE watchdog state
        last_peer_seen: nil,
        has_ever_seen_peers: false,
        watchdog_restarts: 0
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
        # Schedule the BLE watchdog timer
        Process.send_after(self(), :ble_watchdog, @watchdog_interval_ms)
        # Schedule periodic cleanup of stale BLE join request mappings
        Process.send_after(self(), :cleanup_ble_requests, 600_000)
        Logger.info("#{log_prefix()} BLE watchdog started (check every #{div(@watchdog_interval_ms, 1000)}s)")
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
    if h = state[:r2_watch], do: Reality2Transnet.Action.stop_watching(h)
    if h = state[:r2_beacon], do: Reality2Transnet.Action.stop_broadcast(h)
    if h = state[:gatt_handle], do: Reality2Transnet.Action.stop_gatt_server(h)
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
  def handle_call(:pause_scanning, _from, state) do
    case Map.get(state, :r2_watch) do
      nil -> {:reply, :ok, state}
      handle ->
        Reality2Transnet.Action.pause_watching(handle)
        Logger.debug("#{log_prefix()} BLE scanning paused for GATT client operation")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:refresh_beacon, _from, state) do
    # Stop the old beacon if running
    case Map.get(state, :r2_beacon) do
      nil -> :ok
      old_handle ->
        Reality2Transnet.Action.stop_broadcast(old_handle)
        Logger.debug("#{log_prefix()} Stopped old beacon for refresh")
    end

    # Start a new beacon with current trust group identity
    node_id = Reality2.Bootstrap.get(:node_id)
    node_name = Reality2.Bootstrap.get(:node_name)
    adapter_name = Map.get(state, :adapter_name, "hci0")
    hosting_priority = get_hosting_priority()

    trust_group_compressed = get_trust_group_compressed_id_safe()

    case Reality2Transnet.Action.start_broadcast(
           @r2_company_id,
           node_id,
           trust_group_compressed,
           -59,
           node_name,
           hosting_priority,
           adapter_name
         ) do
      {:ok, h} ->
        trust_group_hex = Reality2Transnet.TrustGroup.compressed_id_to_hex(trust_group_compressed)
        Logger.info("#{log_prefix()} Beacon refreshed with trust group: #{trust_group_hex}")
        {:reply, :ok, Map.put(state, :r2_beacon, h)}

      {:error, reason} ->
        Logger.warning("#{log_prefix()} Beacon refresh failed: #{inspect(reason)}")
        {:reply, {:error, reason}, Map.delete(state, :r2_beacon)}
    end
  end

  @impl true
  def handle_call(:resume_scanning, _from, state) do
    case Map.get(state, :r2_watch) do
      nil -> {:reply, :ok, state}
      handle ->
        Reality2Transnet.Action.resume_watching(handle)
        Logger.debug("#{log_prefix()} BLE scanning resumed")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:send_to_peer, peer_id, sentant_id, event, params, passthrough}, _from, state) do
    # Use PeerManager to get peer info
    peer_result =
      if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
        Reality2Transnet.PeerManager.get_peer(peer_id)
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
          Reality2Transnet.Action.gatt_write_to_device(
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
    if Code.ensure_loaded?(Reality2Transnet.R2Mesh) do
      Reality2Transnet.R2Mesh.handle_incoming(encoded_message)
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
    # Update watchdog state - we're seeing peers, discovery is working
    state = state
      |> Map.put(:last_peer_seen, System.monotonic_time(:millisecond))
      |> Map.put(:has_ever_seen_peers, true)

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
    if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
      Reality2Transnet.PeerManager.register_peer(id, enriched_info)
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
    if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
      Reality2Transnet.PeerManager.remove_peer(id)
    end

    {:noreply, state}
  end

  # List of nodes found during a scan.
  def handle_info({:r2nodes, nodes}, state) do
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

    if Code.ensure_loaded?(Reality2Transnet.R2Mesh) do
      Reality2Transnet.R2Mesh.handle_incoming(mesh_data)
    end

    {:noreply, state}
  end

  # Trust Group Join GATT write - a remote node is requesting to join our trust group
  def handle_info({:gatt_write, "hive_join", data}, state) do
    Logger.info("#{log_prefix()} Trust group join GATT write received")

    raw = if is_list(data), do: :binary.list_to_bin(data), else: data

    case Reality2Transnet.GattProtocol.handle_trust_group_join_write(raw) do
      {:ok, %{action: :join_request} = request} ->
        node_id = request.node_id
        node_name = request.node_name
        node_public_key_b64 = request.node_public_key
        ephemeral_public_key_b64 = request.ephemeral_public_key
        _signature_b64 = request.signature

        Logger.info("#{log_prefix()} Trust group join request from #{node_name} (#{node_id})")

        # Verify the request signature to prove the requester holds the private key
        case verify_join_request_signature(request) do
          :ok ->
            # Submit with the actual Ed25519 public key (base64-encoded)
            case Reality2Transnet.JoinRequests.submit(node_name, node_public_key_b64) do
              {:error, :rate_limited} ->
                Logger.warning("#{log_prefix()} Trust group join rate limited for #{node_name}")
                write_join_ack(state, %{action: "join_request_ack", status: "rate_limited"})
                {:noreply, state}

              %{id: request_id} = join_request ->
                # Store mapping with the ephemeral key for encrypting the result
                ble_join_requests = Map.get(state, :ble_join_requests, %{})
                submitted_at = System.system_time(:second)
                ble_join_requests = Map.put(ble_join_requests, request_id, %{
                  node_id: node_id,
                  node_name: node_name,
                  ephemeral_public_key_b64: ephemeral_public_key_b64,
                  submitted_at: submitted_at
                })

                # Broadcast to notify key holder UI of new join request
                Phoenix.PubSub.broadcast(Reality2.PubSub, "trust_group:join_requests", {
                  :trust_group_join_request_received, request_id, %{
                    node_id: node_id,
                    node_name: node_name,
                    node_public_key: node_public_key_b64,
                    submitted_at: submitted_at,
                    source: :ble
                  }
                })

                write_join_ack(state, %{
                  action: "join_request_ack",
                  request_id: join_request.id,
                  status: "pending"
                })

                {:noreply, Map.put(state, :ble_join_requests, ble_join_requests)}
            end

          {:error, reason} ->
            Logger.warning("#{log_prefix()} Trust group join signature verification failed: #{reason}")
            write_join_ack(state, %{action: "join_request_ack", status: "invalid_signature"})
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("#{log_prefix()} Trust group join GATT write error: #{reason}")
        {:noreply, state}
    end
  end

  # PubSub: Trust group join request approved/denied - write result back to GATT
  def handle_info({:trust_group_join_result, request_id, result}, state) do
    ble_join_requests = Map.get(state, :ble_join_requests, %{})

    case Map.get(ble_join_requests, request_id) do
      nil ->
        # Not a BLE-originated request, ignore
        {:noreply, state}

      ble_request ->
        Logger.info("#{log_prefix()} Trust group join result for BLE request #{request_id}: #{result.status}")

        # Build the plaintext result payload
        # cert and trust_group_public_info must be JSON strings, not nested objects
        cert_value = case Map.get(result, :certificate) do
          nil -> nil
          cert when is_map(cert) -> Jason.encode!(cert)
          cert -> cert
        end
        trust_group_info_value = case Map.get(result, :trust_group_public_info) do
          nil -> nil
          info when is_map(info) -> Jason.encode!(info)
          info -> info
        end

        result_payload = %{
          action: "join_result",
          request_id: request_id,
          status: result.status,
          trust_group_id: Map.get(result, :trust_group_id),
          cert: cert_value,
          trust_group_public_info: trust_group_info_value,
          message: Map.get(result, :message)
        }
        Logger.debug("#{log_prefix()} Result payload to encrypt: #{inspect(result_payload)}")

        # Encrypt the result if we have the joiner's ephemeral public key
        response = case Map.get(ble_request, :ephemeral_public_key_b64) do
          nil ->
            # Fallback: send unencrypted (shouldn't happen with updated joiner)
            Reality2Transnet.GattProtocol.encode_trust_group_join(result_payload)

          eph_pub_b64 ->
            case Base.decode64(eph_pub_b64) do
              {:ok, recipient_x25519_pub} ->
                encrypted = Reality2Transnet.GattProtocol.encrypt_join_result(result_payload, recipient_x25519_pub)
                encoded = Reality2Transnet.GattProtocol.encode_trust_group_join(encrypted)
                Logger.debug("#{log_prefix()} Encrypted response size: #{byte_size(encoded)} bytes")
                encoded

              :error ->
                Logger.warning("#{log_prefix()} Invalid ephemeral key, sending unencrypted")
                Reality2Transnet.GattProtocol.encode_trust_group_join(result_payload)
            end
        end

        if handle = Map.get(state, :gatt_handle) do
          Reality2Transnet.Action.gatt_write_characteristic(
            handle,
            Reality2Transnet.GattProtocol.trust_group_join_uuid(),
            :binary.bin_to_list(response)
          )
        end

        # Clean up
        ble_join_requests = Map.delete(ble_join_requests, request_id)
        {:noreply, Map.put(state, :ble_join_requests, ble_join_requests)}
    end
  end

  # Periodic cleanup of stale BLE join request mappings
  def handle_info(:cleanup_ble_requests, state) do
    now = System.system_time(:second)
    ble_join_requests = Map.get(state, :ble_join_requests, %{})

    cleaned = Map.reject(ble_join_requests, fn {_id, req} ->
      (now - req.submitted_at) >= 600
    end)

    if map_size(ble_join_requests) != map_size(cleaned) do
      Logger.debug("#{log_prefix()} Cleaned #{map_size(ble_join_requests) - map_size(cleaned)} stale BLE join requests")
    end

    Process.send_after(self(), :cleanup_ble_requests, 600_000)
    {:noreply, Map.put(state, :ble_join_requests, cleaned)}
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

  # BLE Watchdog - detect and recover from stale discovery after standby/resume
  def handle_info(:ble_watchdog, state) do
    state = check_ble_health(state)
    # Schedule next watchdog check
    Process.send_after(self(), :ble_watchdog, @watchdog_interval_ms)
    {:noreply, state}
  end

  # Catchall
  def handle_info(msg, state) do
    Logger.debug("Unhandled Bluetooth message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - BLE Watchdog
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Check BLE discovery health and restart if stale
  defp check_ble_health(%{bluetooth_available: false} = state), do: state
  defp check_ble_health(%{has_ever_seen_peers: false} = state) do
    # Haven't seen any peers yet - this is normal if device is alone
    # Just log periodically for visibility
    Logger.debug("#{log_prefix()} BLE watchdog: no peers discovered yet (this is normal if alone)")
    state
  end
  defp check_ble_health(state) do
    last_seen = Map.get(state, :last_peer_seen)
    now = System.monotonic_time(:millisecond)
    time_since_peer = if last_seen, do: now - last_seen, else: nil

    cond do
      # Recently seen peers - all good
      time_since_peer && time_since_peer < @ble_stale_threshold_ms ->
        Logger.debug("#{log_prefix()} BLE watchdog: healthy (last peer #{div(time_since_peer, 1000)}s ago)")
        state

      # No peers seen for a while - check with PeerManager if we should have peers
      true ->
        check_and_maybe_restart_discovery(state, time_since_peer)
    end
  end

  # Check if we should expect to see peers and restart discovery if needed
  defp check_and_maybe_restart_discovery(state, time_since_peer) do
    # Get peer count from PeerManager
    peer_count = if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
      Reality2Transnet.PeerManager.get_all_peers() |> map_size()
    else
      0
    end

    if peer_count == 0 && time_since_peer && time_since_peer > @ble_stale_threshold_ms do
      # Had peers before but now gone and no new discoveries - likely stale
      Logger.warning("#{log_prefix()} BLE watchdog: discovery appears stale (#{div(time_since_peer, 1000)}s since last peer, 0 current peers)")
      restart_ble_discovery(state)
    else
      # Either we have peers or we're just in a quiet period
      Logger.debug("#{log_prefix()} BLE watchdog: #{peer_count} peers tracked, waiting for discoveries")
      state
    end
  end

  # Restart BLE discovery (r2_watch) to recover from stale NIF handles
  defp restart_ble_discovery(state) do
    restarts = Map.get(state, :watchdog_restarts, 0)
    Logger.warning("#{log_prefix()} BLE watchdog: restarting discovery (restart ##{restarts + 1})")

    # Stop the old watcher
    if handle = Map.get(state, :r2_watch) do
      try do
        Reality2Transnet.Action.stop_watching(handle)
      rescue
        _ -> Logger.debug("#{log_prefix()} stop_watching raised (handle may already be invalid)")
      catch
        _, _ -> Logger.debug("#{log_prefix()} stop_watching threw (handle may already be invalid)")
      end
    end

    # Start a new watcher
    adapter_name = Map.get(state, :adapter_name, "hci0")
    company_id = @r2_company_id
    lost_after_ms = 30_000

    case Reality2Transnet.Action.start_watching(self(), company_id, adapter_name, lost_after_ms) do
      {:ok, new_handle} ->
        Logger.info("#{log_prefix()} BLE discovery restarted successfully")
        state
        |> Map.put(:r2_watch, new_handle)
        |> Map.put(:watchdog_restarts, restarts + 1)
        |> Map.put(:last_peer_seen, nil)  # Reset so we don't immediately restart again

      {:error, reason} ->
        Logger.error("#{log_prefix()} BLE watchdog: failed to restart discovery: #{inspect(reason)}")
        # Try a full module restart on next failure
        if restarts >= 2 do
          Logger.error("#{log_prefix()} BLE watchdog: multiple restart failures, requesting supervisor restart")
          # Exit abnormally to trigger supervisor restart
          Process.exit(self(), :ble_watchdog_failed)
        end
        Map.put(state, :watchdog_restarts, restarts + 1)
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - starting various services
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_adapter_and_name({:ok, state}) do
    case Reality2Transnet.Action.list_adapters_seq() do
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

    # Get compressed trust group ID (4 bytes) for beacon - shows trust group membership to peers
    # Use safe call to handle case where TrustGroup hasn't started yet
    trust_group_compressed = get_trust_group_compressed_id_safe()

    case Reality2Transnet.Action.start_broadcast(
           @r2_company_id,
           node_id,
           trust_group_compressed,
           -59,
           node_name,
           hosting_priority,
           adapter_name
         ) do
      {:ok, h} ->
        trust_group_hex = Reality2Transnet.TrustGroup.compressed_id_to_hex(trust_group_compressed)
        Logger.info("Node ID: #{node_id} beacon started on #{adapter_name} (priority: #{hosting_priority}, trust group: #{trust_group_hex})")
        {:ok, Map.put(state, :r2_beacon, h)}

      {:error, reason} ->
        Logger.warning("start_beacon failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_beacon({:error, reason}), do: {:error, reason}

  # Safely get compressed trust group ID, handling case where TrustGroup isn't started yet
  defp get_trust_group_compressed_id_safe do
    # Check if TrustGroup process is registered before calling it
    case GenServer.whereis(Reality2Transnet.TrustGroup) do
      nil ->
        Logger.debug("#{log_prefix()} TrustGroup not yet started, using empty trust group ID")
        <<0, 0, 0, 0>>

      _pid ->
        case Reality2Transnet.TrustGroup.get_trust_group_compressed_id() do
          {:ok, compressed} -> compressed
          {:error, _} -> <<0, 0, 0, 0>>
        end
    end
  rescue
    _ ->
      Logger.debug("#{log_prefix()} TrustGroup call failed, using empty trust group ID")
      <<0, 0, 0, 0>>
  end

  # Get hosting priority from Wifi module if available, otherwise return basic priority
  defp get_hosting_priority do
    if Code.ensure_loaded?(Reality2Transnet.Wifi) &&
       function_exported?(Reality2Transnet.Wifi, :get_hosting_priority, 0) do
      Reality2Transnet.Wifi.get_hosting_priority()
    else
      # Basic priority - can host but no special capabilities
      10
    end
  end

  # Start the GATT server for Sentant access
  defp start_gatt_server({:ok, state}) do
    adapter_name = Map.get(state, :adapter_name, "hci0")

    case Reality2Transnet.Action.start_gatt_server(self(), adapter_name) do
      {:ok, handle} ->
        Logger.info("GATT Sentant Server started successfully")

        # Initialize the Query characteristic with current Sentants
        update_query_characteristic(handle)

        # Initialize the Join Offer characteristic with WiFi hotspot credentials
        update_join_offer_characteristic(handle)

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

    case Reality2Transnet.Action.start_watching(self(), company_id, adapter_name, lost_after_ms) do
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
    # Subscribe to trust group join results so we can relay them over GATT
    Phoenix.PubSub.subscribe(Reality2.PubSub, "trust_group:join_results")
    Logger.debug("Subscribed to sentant:signals and trust_group:join_results PubSub topics")
    {:ok, state}
  end

  defp subscribe_to_pubsub({:error, reason}), do: {:error, reason}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Beacon and Watch Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # List the Bluetooth adapters on this device.
  defp list_adapters(state) do
    Reality2Transnet.Action.list_adapters(self())
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

    Reality2Transnet.Action.scan_nodes(self(), timeout)
    {:noreply, state}
  end

  defp reset_nodes(state) do
    Reality2Transnet.Action.reset_nodes(state.r2_watch)
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
    {:ok, sentants} = Reality2.Sentants.read_all(:definition)
    Logger.debug("Fetched all sentants: #{inspect(sentants, pretty: false, limit: 500)}")
    sentants
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
          Reality2Transnet.Action.gatt_write_characteristic(
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
    # Get hosting config and encode WiFi hotspot join offer
    config = case Reality2Transnet.ConnectionManager.get_hosting_config() do
      {:ok, c} -> c
      _ -> nil
    end
    json = Reality2Transnet.GattProtocol.encode_join_offer(config)
    binary_data = :binary.bin_to_list(json)

    Logger.info("Writing #{byte_size(json)} bytes to join offer characteristic")

    result =
      Reality2Transnet.Action.gatt_write_characteristic(
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
        Reality2Transnet.Action.gatt_notify(handle, binary_data)

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
  # Trust Group Join Security Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Verify the Ed25519 signature on a join request to prove key ownership
  defp verify_join_request_signature(%{
    node_id: node_id,
    node_name: node_name,
    node_public_key: node_public_key_b64,
    ephemeral_public_key: ephemeral_public_key_b64,
    signature: signature_b64
  }) when is_binary(node_public_key_b64) and is_binary(signature_b64) do
    with {:ok, public_key} <- Base.decode64(node_public_key_b64),
         {:ok, signature} <- Base.decode64(signature_b64) do
      # Reconstruct the canonical signed message
      message = Reality2Transnet.GattProtocol.join_request_signable(
        node_id, node_name, node_public_key_b64, ephemeral_public_key_b64
      )

      if :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519]) do
        :ok
      else
        {:error, "signature_mismatch"}
      end
    else
      :error -> {:error, "invalid_base64"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "signature_verification_exception"}
  end

  defp verify_join_request_signature(_), do: {:error, "missing_signature_fields"}

  # Write a join ack/error to the GATT characteristic
  defp write_join_ack(state, payload) do
    ack = Reality2Transnet.GattProtocol.encode_trust_group_join(payload)

    if handle = Map.get(state, :gatt_handle) do
      Reality2Transnet.Action.gatt_write_characteristic(
        handle,
        Reality2Transnet.GattProtocol.trust_group_join_uuid(),
        :binary.bin_to_list(ack)
      )
    end
  end

end
