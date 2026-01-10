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
end
