defmodule AiReality2Transnet.Transports.WiFiTransport do
  @moduledoc """
  WiFi transport adapter implementing the Transport behaviour.

  Provides high-bandwidth mesh communication over WiFi hotspot connections.
  Used for large data transfers, full sentant exchange, and GraphQL queries.

  ## Characteristics

  | Property | Value |
  |----------|-------|
  | Range | ~50m |
  | Max Payload | 1MB |
  | Latency | Low |
  | Power | Medium |
  | Best For | Data exchange, GraphQL, large messages |

  ## Connection Modes

  - **Hotspot Mode**: Node acts as WiFi AP, others connect as clients
  - **Client Mode**: Node connects to another node's hotspot

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  @behaviour AiReality2Transnet.Transport

  require Logger

  # WiFi can handle much larger payloads
  @max_payload_size 1_000_000  # 1MB

  # Short timeout for ConnectionManager calls to avoid blocking MeshRouter
  # If ConnectionManager is busy, we report as disconnected rather than crash
  @connection_status_timeout 500

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Transport Behaviour Implementation
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def transport_type, do: :wifi_hotspot

  @impl true
  def available? do
    Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) and
      Process.whereis(AiReality2Transnet.ConnectionManager) != nil and
      is_connected_or_hosting?()
  end

  @impl true
  def max_payload_size, do: @max_payload_size

  @impl true
  def capabilities do
    %{
      broadcast: true,        # Can push to connected clients
      unicast: true,          # HTTP to specific peer
      bidirectional: true,    # Full HTTP communication
      reliable: true,         # TCP-based
      max_payload: @max_payload_size
    }
  end

  @impl true
  def broadcast(message) do
    if available?() do
      case get_connection_state() do
        :hosting_ap ->
          # We're hosting - push to all connected clients
          push_to_clients(message)

        :connected_as_client ->
          # We're a client - send to host for relay
          send_to_host(message)

        _ ->
          {:error, :not_connected}
      end
    else
      {:error, :not_available}
    end
  end

  @impl true
  def send_to(peer_id, message) do
    if available?() do
      case get_peer_ip(peer_id) do
        {:ok, peer_ip} ->
          send_http_message(peer_ip, message)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_available}
    end
  end

  @impl true
  def handle_incoming(raw_data) do
    case decode_message(raw_data) do
      {:ok, message} ->
        AiReality2Transnet.MeshRouter.handle_incoming(message, :wifi_hotspot)
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  @impl true
  def get_stats do
    if Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) do
      try do
        case GenServer.call(AiReality2Transnet.ConnectionManager, :get_health_metrics, @connection_status_timeout) do
          {:ok, metrics} ->
            %{
              available: available?(),
              connections_made: Map.get(metrics, :connections_made, 0),
              connected_clients: Map.get(metrics, :connected_clients_count, 0),
              connection_state: Map.get(metrics, :connection_state)
            }

          _ ->
            %{available: false}
        end
      catch
        :exit, _ -> %{available: false}
      end
    else
      %{available: false}
    end
  end

  @impl true
  def get_peers do
    if Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) do
      try do
        case GenServer.call(AiReality2Transnet.ConnectionManager, :get_status, @connection_status_timeout) do
          {:ok, status} ->
            clients = Map.get(status, :connected_clients, [])
            Enum.map(clients, fn c -> c.node_id end)

          _ ->
            []
        end
      catch
        :exit, _ -> []
      end
    else
      []
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Connection State
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp is_connected_or_hosting? do
    case get_connection_state() do
      :hosting_ap -> true
      :connected_as_client -> true
      _ -> false
    end
  end

  defp get_connection_state do
    # First check if the process is alive
    case Process.whereis(AiReality2Transnet.ConnectionManager) do
      nil ->
        :disconnected

      pid when is_pid(pid) ->
        try do
          case GenServer.call(AiReality2Transnet.ConnectionManager, :get_status, @connection_status_timeout) do
            {:ok, %{state: state}} -> state
            _ -> :disconnected
          end
        catch
          :exit, {:timeout, _} ->
            # ConnectionManager is busy - report as disconnected to avoid cascading failures
            Logger.debug("[WiFiTransport] ConnectionManager timeout, reporting disconnected")
            :disconnected

          :exit, _ ->
            :disconnected
        end
    end
  rescue
    _ -> :disconnected
  end

  defp get_peer_ip(peer_id) do
    # Check if peer is a connected client - use safe call with timeout
    case safe_get_connection_status() do
      {:ok, %{connected_clients: clients, host_ip: host_ip, host_peer_id: host_peer_id}} ->
        case Enum.find(clients || [], fn c -> c.node_id == peer_id end) do
          nil ->
            # Check if it's our host
            if host_peer_id == peer_id and not is_nil(host_ip) do
              {:ok, host_ip}
            else
              {:error, :peer_not_found}
            end

          client ->
            {:ok, client.ip}
        end

      _ ->
        {:error, :not_connected}
    end
  end

  # Safe wrapper for get_connection_status with short timeout
  defp safe_get_connection_status do
    try do
      GenServer.call(AiReality2Transnet.ConnectionManager, :get_status, @connection_status_timeout)
    catch
      :exit, _ -> {:error, :timeout}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Message Sending
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp push_to_clients(message) do
    case safe_get_connection_status() do
      {:ok, %{connected_clients: clients}} when is_list(clients) ->
        Enum.each(clients, fn client ->
          Task.start(fn ->
            send_http_message(client.ip, message)
          end)
        end)
        :ok

      _ ->
        {:error, :no_clients}
    end
  end

  defp send_to_host(message) do
    case safe_get_connection_status() do
      {:ok, %{host_ip: host_ip}} when not is_nil(host_ip) ->
        send_http_message(host_ip, message)

      _ ->
        {:error, :not_connected_to_host}
    end
  end

  defp send_http_message(peer_ip, message) do
    url = "https://#{peer_ip}:4005/mesh/message"
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(message)

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 10_000) do
      {:ok, %Finch.Response{status: 200}} ->
        :ok

      {:ok, %Finch.Response{status: status}} ->
        {:error, "http_#{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Encoding/Decoding
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp decode_message(raw_data) when is_binary(raw_data) do
    case Jason.decode(raw_data) do
      {:ok, %{"msg_id" => id, "ttl" => ttl, "type" => type, "src_node_id" => src, "payload" => payload}} ->
        {:ok, %{
          msg_id: id,
          ttl: ttl,
          type: parse_message_type(type),
          src_node_id: src,
          payload: payload
        }}

      _ ->
        {:error, :invalid_format}
    end
  rescue
    _ -> {:error, :decode_error}
  end

  defp decode_message(_), do: {:error, :invalid_format}

  defp parse_message_type("event"), do: :event
  defp parse_message_type("signal"), do: :signal
  defp parse_message_type("presence"), do: :presence
  defp parse_message_type("data"), do: :data
  defp parse_message_type(_), do: :event
end
