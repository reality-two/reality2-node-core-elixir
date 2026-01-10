defmodule Reality2Web.MeshController do
  @moduledoc """
  Controller for WiFi mesh network endpoints.

  These endpoints are used by transient network peers to query node information
  and Sentant capabilities over the WiFi mesh network.

  All responses contain only public information - Sentants are designed to be
  opaque, exposing their interface (events, signals) but hiding internal state.
  """

  use Reality2Web, :controller

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

    Logger.info("[MeshController] Registering remote node: #{node_name} (#{String.slice(node_id || "", 0..7)}...) with #{length(sentants)} sentants")

    if node_id do
      # Register the peer if not already known
      if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
        apply(AiReality2Transnet.PeerManager, :register_peer, [node_id, %{
          node_name: node_name,
          address: client_ip
        }])

        # Update peer's sentants
        apply(AiReality2Transnet.PeerManager, :update_peer_sentants, [node_id, sentants])

        # Update peer's transport to wifi_hotspot
        apply(AiReality2Transnet.PeerManager, :update_peer_transport, [node_id, :wifi_hotspot])
      end

      # Update PNS routing table with client's sentants
      update_pns_routes_for_peer(node_id, node_name, client_ip, sentants)

      response = %{
        status: "ok",
        registered_sentants: length(sentants),
        host_node_id: Reality2.Bootstrap.get(:node_id)
      }

      json(conn, response)
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "node_id is required"})
    end
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
            events: get_event_names(Map.get(sentant, :events, [])),
            signals: get_signal_names(Map.get(sentant, :signals, []))
          }
        end)

      _ ->
        []
    end
  end

  defp get_event_names(events) when is_list(events) do
    Enum.map(events, fn
      %{event: name} -> name
      %{name: name} -> name
      %{"event" => name} -> name
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_event_names(_), do: []

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

  defp update_pns_routes_for_peer(peer_node_id, peer_node_name, peer_ip, peer_sentants) do
    require Logger

    # Update PNS routing table with peer's sentants
    Enum.each(peer_sentants, fn sentant ->
      sentant_name = Map.get(sentant, "name") || Map.get(sentant, :name)
      sentant_id = Map.get(sentant, "id") || Map.get(sentant, :id)

      if sentant_name do
        pns_key = "#{peer_node_id}|#{sentant_name}"

        Reality2.Metadata.set(:PNS_Routes, pns_key, %{
          peer_node_id: peer_node_id,
          peer_node_name: peer_node_name,
          peer_ip: peer_ip,
          sentant_name: sentant_name,
          sentant_id: sentant_id,
          discovered_at: System.system_time(:millisecond)
        })

        Logger.debug("[MeshController] PNS route added: #{peer_node_name}|#{sentant_name} -> #{peer_ip}")
      end
    end)

    # Notify PNS Router of topology change
    if Code.ensure_loaded?(AiReality2Pns.Router) do
      apply(AiReality2Pns.Router, :refresh_topology, [])
    end

    Logger.info("[MeshController] PNS routing table updated with #{length(peer_sentants)} entries from #{peer_node_name}")
  end
end
