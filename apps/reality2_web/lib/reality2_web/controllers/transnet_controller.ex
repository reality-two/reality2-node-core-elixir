defmodule Reality2Web.TransnetController do
  @moduledoc """
  Controller for transient network status endpoint.

  Provides node and network connection information for transient network peers.
  Sentant queries should use the GraphQL `/reality2` endpoint.
  """

  use Reality2Web, :controller

  # Suppress compile-time warning for cross-app dependency (runtime check handles availability)
  @compile {:no_warn_undefined, AiReality2Transnet.ConnectionManager}

  @doc """
  GET /transnet/info - Query node information and capabilities.

  Returns node_id, node_name, version, capabilities (bluetooth, wifi, sentant count),
  and current network connection status.
  """
  def info(conn, _params) do
    node_id = Reality2.Bootstrap.get(:node_id)
    node_name = Reality2.Bootstrap.get(:node_name)
    network_info = get_network_info()

    response = %{
      node_id: node_id,
      node_name: node_name,
      version: Application.spec(:reality2, :vsn) |> to_string(),
      capabilities: %{
        bluetooth: bluetooth_available?(),
        wifi: wifi_available?(),
        sentants: Reality2.Metadata.all(:SentantIDs) |> map_size()
      },
      network_info: network_info,
      timestamp: System.system_time(:millisecond)
    }

    json(conn, response)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp get_network_info do
    if connection_manager_available?() do
      case AiReality2Transnet.ConnectionManager.get_connection_status() do
        {:ok, status} ->
          %{
            state: status.state,
            hosting: status.hosting,
            host_peer_id: status.host_peer_id,
            connected_clients_count: status.connected_clients_count
          }

        _ ->
          %{state: :unavailable}
      end
    else
      %{state: :unavailable}
    end
  rescue
    _ -> %{state: :unavailable}
  end

  defp bluetooth_available? do
    Code.ensure_loaded?(AiReality2Transnet.Bluetooth) &&
      Process.whereis(AiReality2Transnet.Bluetooth) != nil
  end

  defp wifi_available? do
    connection_manager_available?()
  end

  defp connection_manager_available? do
    Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) &&
      Process.whereis(AiReality2Transnet.ConnectionManager) != nil
  end
end
