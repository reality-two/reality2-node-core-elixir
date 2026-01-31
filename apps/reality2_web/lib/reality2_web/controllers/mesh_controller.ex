defmodule Reality2Web.MeshController do
  @moduledoc """
  Controller for WiFi mesh network endpoints.

  These endpoints are used by transient network peers to query node information
  and Sentant capabilities over the WiFi mesh network.

  All responses contain only public information - Sentants are designed to be
  opaque, exposing their interface (events, signals) but hiding internal state.
  """

  use Reality2Web, :controller

  # SECURITY TODO: Mesh endpoint authentication
  # These endpoints currently accept unauthenticated requests from any client.
  # Plan:
  # 1. Add a shared-secret HMAC plug that validates a signature header on all
  #    POST endpoints (/register, /peer_update, /message).
  # 2. The secret is derived from the Hive identity — only nodes in the same
  #    Hive can communicate. Use HiveIdentity.derive_data_key("mesh:auth") to
  #    produce a per-Hive HMAC key.
  # 3. Each request must include an X-Mesh-Signature header containing
  #    HMAC-SHA256(request_body, shared_key). Replay protection via msg_id or
  #    timestamp window.
  # 4. GET endpoints (/info, /sentants) can remain public since they expose
  #    only the public sentant interface.

  @doc """
  GET /mesh/sentants - List all Sentants with public information only.

  Returns node_id, sentant count, and list of Sentants with their
  public interface (name, events, signals).
  """
  def sentants(conn, _params) do
    node_id = Reality2.Bootstrap.get(:node_id)
    sentants = get_public_sentant_info()

    response = %{
      node_id: node_id,
      sentant_count: length(sentants),
      sentants: sentants,
      timestamp: System.system_time(:millisecond)
    }

    json(conn, response)
  end

  @doc """
  POST /mesh/register - Register a remote node and its sentants.

  Called by clients after connecting to register their sentants with the host.
  This enables bidirectional sentant discovery.

  ## Request Body
  ```json
  {
    "node_id": "uuid-string",
    "node_name": "R2Node_XXXX",
    "sentants": [
      {"id": "uuid", "name": "SentantName", "description": "...", "events": [], "signals": []}
    ]
  }
  ```

  ## Response
  ```json
  {
    "status": "ok",
    "registered_sentants": 2,
    "host_node_id": "uuid-string"
  }
  ```
  """
  def register(conn, params) do
    require Logger

    node_id = Map.get(params, "node_id")
    node_name = Map.get(params, "node_name")
    sentants = Map.get(params, "sentants", [])
    client_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    Logger.info("[MeshController] Registering remote node: #{node_name} (#{String.slice(node_id || "", 0..7)}...) with #{length(sentants)} sentants from #{client_ip}")

    # Log sentant names for debugging
    sentant_names = Enum.map(sentants, fn s -> Map.get(s, "name") || Map.get(s, :name) || "?" end)
    Logger.debug("[MeshController] Sentants being registered: #{inspect(sentant_names)}")

    if node_id do
      # Check if this is an existing peer (update) or new peer
      is_existing_peer = if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
        case apply(AiReality2Transnet.PeerManager, :get_peer, [node_id]) do
          {:ok, existing_peer} ->
            # Get previous sentant count for comparison
            previous_count = length(Map.get(existing_peer, :sentants, []))
            {true, previous_count}
          _ ->
            {false, 0}
        end
      else
        {false, 0}
      end

      # Register the peer if not already known
      if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
        # Use synchronous call to ensure peer is registered before updating sentants
        apply(AiReality2Transnet.PeerManager, :register_peer, [node_id, %{
          node_name: node_name,
          address: client_ip
        }])

        # Small delay to ensure registration completes (casts are async)
        Process.sleep(50)

        # Update peer's sentants
        apply(AiReality2Transnet.PeerManager, :update_peer_sentants, [node_id, sentants])

        # Update peer's transport to wifi_hotspot
        apply(AiReality2Transnet.PeerManager, :update_peer_transport, [node_id, :wifi_hotspot])

        # Log final state for debugging
        Process.sleep(50)
        case apply(AiReality2Transnet.PeerManager, :get_peer, [node_id]) do
          {:ok, peer} ->
            stored_count = length(Map.get(peer, :sentants, []))
            Logger.info("[MeshController] Peer #{node_name} now has #{stored_count} sentants stored")
          {:error, _} ->
            Logger.warning("[MeshController] Could not verify peer registration for #{node_name}")
        end
      end

      # Register client with ConnectionManager so host can push updates
      if Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) do
        apply(AiReality2Transnet.ConnectionManager, :register_connected_client, [node_id, node_name, client_ip])
      end

      # Update WFS routing table with client's sentants
      update_wfs_routes_for_peer(node_id, node_name, client_ip, sentants)

      # Notify other connected clients to refresh their sentant lists
      # This enables client-to-client discovery through the host
      notify_other_clients_of_new_registration(node_id, node_name, sentants)

      # Emit __internal event for local monitor sentant to trigger webapp refresh
      # Differentiate between new peer and existing peer updating sentants
      {existing, previous_count} = is_existing_peer
      event_name = if existing, do: "mesh_peer_sentants_changed", else: "mesh_peer_connected"

      Logger.info("[MeshController] *** EMITTING EVENT: #{event_name} for peer #{node_name} (#{length(sentants)} sentants) ***")

      Reality2.Sentants.sendto_all(%{
        event: "__internal",
        parameters: %{
          mesh_event: event_name,  # Use mesh_event to avoid collision with signal action's 'event' parameter
          peer_id: node_id,
          peer_name: node_name || "Unknown",
          sentant_count: length(sentants),
          previous_count: previous_count
        }
      })

      Logger.info("[MeshController] *** EVENT SENT via sendto_all ***")

      # Build confirmation response with stored sentant IDs
      # This allows client to verify all sentants were registered
      stored_sentants = get_stored_sentants_for_peer(node_id)
      stored_ids = Enum.map(stored_sentants, fn s ->
        Map.get(s, "id") || Map.get(s, :id)
      end) |> Enum.reject(&is_nil/1)

      response = %{
        status: "ok",
        registered_sentants: length(sentants),
        stored_sentant_ids: stored_ids,
        host_node_id: Reality2.Bootstrap.get(:node_id),
        host_node_name: Reality2.Bootstrap.get(:node_name)
      }

      json(conn, response)
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "node_id is required"})
    end
  end

  @doc """
  POST /mesh/peer_update - Receive notification that a new peer has registered with the host.

  Called by the host when another client registers, enabling client-to-client discovery.
  The client can either use the pushed sentants directly or trigger a full refresh.

  ## Request Body
  ```json
  {
    "type": "peer_registered",
    "peer_node_id": "uuid-string",
    "peer_node_name": "R2Node_XXXX",
    "sentants": [...],
    "timestamp": 1234567890
  }
  ```
  """
  def peer_update(conn, params) do
    require Logger

    peer_node_id = Map.get(params, "peer_node_id")
    peer_node_name = Map.get(params, "peer_node_name")
    sentants = Map.get(params, "sentants", [])

    Logger.info("[MeshController] Received peer update: #{peer_node_name} (#{String.slice(peer_node_id || "", 0..7)}...) with #{length(sentants)} sentants")

    if peer_node_id do
      # Register the new peer directly from the push notification
      if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
        # Register peer (they're connected to the same host as us)
        apply(AiReality2Transnet.PeerManager, :register_peer, [peer_node_id, %{
          node_name: peer_node_name,
          address: "via_host"  # We don't have direct IP, route through host
        }])

        Process.sleep(50)

        # Store their sentants
        apply(AiReality2Transnet.PeerManager, :update_peer_sentants, [peer_node_id, sentants])
      end

      # Refresh WFS topology
      if Code.ensure_loaded?(AiReality2Wfs.Router) do
        apply(AiReality2Wfs.Router, :refresh_topology, [])
      end

      json(conn, %{status: "ok", received_sentants: length(sentants)})
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "peer_node_id is required"})
    end
  end

  @doc """
  POST /mesh/message - Receive a mesh message from a peer via WiFi transport.

  This endpoint receives mesh-routed messages (events, signals, presence)
  from peers connected over the WiFi hotspot network.
  """
  def message(conn, params) do
    require Logger

    msg_id = Map.get(params, "msg_id")
    ttl = Map.get(params, "ttl", 5)
    type_str = Map.get(params, "type", "event")
    src_node_id = Map.get(params, "src_node_id")
    payload = Map.get(params, "payload", "{}")

    type = parse_message_type(type_str)

    message = %{
      msg_id: msg_id,
      ttl: ttl,
      type: type,
      src_node_id: src_node_id,
      payload: payload
    }

    Logger.debug("[MeshController] Received mesh message: type=#{type}, from=#{String.slice(src_node_id || "", 0..7)}...")

    if Code.ensure_loaded?(AiReality2Transnet.MeshRouter) do
      apply(AiReality2Transnet.MeshRouter, :handle_incoming, [message, :wifi_hotspot])
    end

    json(conn, %{status: "ok"})
  end

  @doc """
  GET /mesh/info - Query node information and capabilities.

  Returns node_id, version, capabilities (bluetooth, wifi_mesh, sentant count),
  and current mesh network status.
  """
  def info(conn, _params) do
    node_id = Reality2.Bootstrap.get(:node_id)
    mesh_info = get_mesh_info()

    response = %{
      node_id: node_id,
      version: Application.spec(:reality2, :vsn) |> to_string(),
      capabilities: %{
        bluetooth: bluetooth_available?(),
        wifi_mesh: wifi_available?(),
        sentants: Reality2.Metadata.all(:SentantIDs) |> map_size()
      },
      mesh_info: mesh_info,
      timestamp: System.system_time(:millisecond)
    }

    json(conn, response)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp get_public_sentant_info do
    case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} ->
        Enum.map(sentants, fn sentant ->
          %{
            id: Map.get(sentant, :id),
            name: Map.get(sentant, :name),
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

  defp get_mesh_info do
    if wifi_available?() do
      # Use apply/3 to avoid compile-time warning for cross-app module reference
      case apply(AiReality2Transnet.ConnectionManager, :get_connection_status, []) do
        {:ok, status} ->
          %{
            active: status.state in [:connected_as_client, :hosting_ap],
            state: status.state,
            hosting: Map.get(status, :hosting, false),
            ssid: Map.get(status, :ssid)
          }
        _ ->
          %{active: false}
      end
    else
      %{active: false}
    end
  rescue
    _ -> %{active: false}
  end

  defp bluetooth_available? do
    Code.ensure_loaded?(AiReality2Transnet.Bluetooth) &&
      Process.whereis(AiReality2Transnet.Bluetooth) != nil
  end

  defp wifi_available? do
    Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) &&
      Process.whereis(AiReality2Transnet.ConnectionManager) != nil
  end

  # Get stored sentants for a peer from PeerManager (for confirmation)
  defp get_stored_sentants_for_peer(peer_node_id) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case apply(AiReality2Transnet.PeerManager, :get_peer, [peer_node_id]) do
        {:ok, peer} -> Map.get(peer, :sentants, [])
        _ -> []
      end
    else
      []
    end
  end

  defp update_wfs_routes_for_peer(peer_node_id, peer_node_name, peer_ip, peer_sentants) do
    require Logger

    # Update WFS routing table with peer's sentants
    Enum.each(peer_sentants, fn sentant ->
      sentant_name = Map.get(sentant, "name") || Map.get(sentant, :name)
      sentant_id = Map.get(sentant, "id") || Map.get(sentant, :id)

      if sentant_name do
        wfs_key = "#{peer_node_id}|#{sentant_name}"

        Reality2.Metadata.set(:WFS_Routes, wfs_key, %{
          peer_node_id: peer_node_id,
          peer_node_name: peer_node_name,
          peer_ip: peer_ip,
          sentant_name: sentant_name,
          sentant_id: sentant_id,
          discovered_at: System.system_time(:millisecond)
        })

        Logger.debug("[MeshController] WFS route added: #{peer_node_name}|#{sentant_name} -> #{peer_ip}")
      end
    end)

    # Notify WFS Router of topology change
    if Code.ensure_loaded?(AiReality2Wfs.Router) do
      apply(AiReality2Wfs.Router, :refresh_topology, [])
    end

    Logger.info("[MeshController] WFS routing table updated with #{length(peer_sentants)} entries from #{peer_node_name}")
  end

  # Notify other connected clients that a new node has registered
  # This pushes the new sentants to existing clients so they can discover each other
  defp notify_other_clients_of_new_registration(new_node_id, new_node_name, new_sentants) do
    require Logger

    if Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) do
      case apply(AiReality2Transnet.ConnectionManager, :get_connection_status, []) do
        {:ok, %{connected_clients: clients}} when is_list(clients) and length(clients) > 0 ->
          # Filter out the newly registering client
          other_clients = Enum.reject(clients, fn c -> c.node_id == new_node_id end)

          if length(other_clients) > 0 do
            Logger.info("[MeshController] Notifying #{length(other_clients)} other client(s) of new registration from #{new_node_name}")

            # Build the notification payload
            notification = %{
              type: "peer_registered",
              peer_node_id: new_node_id,
              peer_node_name: new_node_name,
              sentants: new_sentants,
              timestamp: System.system_time(:millisecond)
            }

            # Push to each connected client (async)
            Enum.each(other_clients, fn client ->
              Task.start(fn ->
                push_registration_notification(client.ip, notification)
              end)
            end)
          end

        _ ->
          # Not hosting or no clients
          :ok
      end
    end
  rescue
    e ->
      require Logger
      Logger.warning("[MeshController] Failed to notify clients: #{Exception.message(e)}")
  end

  defp parse_message_type("event"), do: :event
  defp parse_message_type("signal"), do: :signal
  defp parse_message_type("presence"), do: :presence
  defp parse_message_type("data"), do: :data
  defp parse_message_type(_), do: :event

  defp push_registration_notification(client_ip, notification) do
    require Logger

    url = "https://#{client_ip}:4005/mesh/peer_update"
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(notification)

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200}} ->
        Logger.debug("[MeshController] Successfully notified client #{client_ip} of new peer")

      {:ok, %Finch.Response{status: status}} ->
        Logger.debug("[MeshController] Client #{client_ip} returned status #{status} for peer update")

      {:error, reason} ->
        Logger.debug("[MeshController] Failed to notify client #{client_ip}: #{inspect(reason)}")
    end
  end
end
