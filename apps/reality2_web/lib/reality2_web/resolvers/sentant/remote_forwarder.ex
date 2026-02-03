defmodule Reality2Web.SentantResolver.RemoteForwarder do
  @moduledoc false
  # Handles forwarding events to remote sentants via HTTP/GraphQL.
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)

  require Logger

  # Send event to a remote sentant via HTTP
  @doc false
  def send_event_to_remote(node_id, sentant_id, event, parameters, passthrough, sender) do
    # Look up the peer's IP address from PeerManager
    if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
      case apply(Reality2Transnet.PeerManager, :get_peer, [node_id]) do
        {:ok, peer} ->
          peer_address = Map.get(peer, :address)
          peer_name = Map.get(peer, :node_name, "Unknown")

          # Determine the best IP to use for HTTP communication
          case get_http_address_for_peer(peer_address) do
            {:ok, ip_address} ->
              Logger.info("[SentantResolver] Forwarding event '#{event}' to remote sentant #{String.slice(sentant_id, 0..7)}... on #{peer_name} (#{ip_address})")
              forward_event_via_http(ip_address, sentant_id, event, parameters, passthrough, sender)

            {:error, reason} ->
              Logger.warning("[SentantResolver] Cannot reach peer #{peer_name}: #{reason}")
              {:error, :peer_not_directly_reachable}
          end

        {:error, _} ->
          Logger.warning("[SentantResolver] Peer #{String.slice(node_id, 0..7)}... not found in PeerManager")
          {:error, :peer_not_found}
      end
    else
      {:error, :transnet_not_loaded}
    end
  end

  # Determine the HTTP address to use for a peer
  # Returns {:ok, ip_address} or {:error, reason}
  defp get_http_address_for_peer(peer_address) do
    cond do
      # Already an IP address
      is_ip_address?(peer_address) ->
        {:ok, peer_address}

      # "via_host" means route through host (not directly reachable)
      peer_address == "via_host" ->
        {:error, "peer connected via host"}

      # Likely a BLE MAC address - try to use gateway IP if we're connected to a hotspot
      true ->
        # Try to get gateway IP from ConnectionManager (we're likely connected to their hotspot)
        if Code.ensure_loaded?(Reality2Transnet.ConnectionManager) do
          case apply(Reality2Transnet.ConnectionManager, :get_gateway_ip, []) do
            {:ok, gateway_ip} ->
              {:ok, gateway_ip}
            _ ->
              {:error, "no IP address available (peer has BLE MAC: #{peer_address})"}
          end
        else
          {:error, "no IP address available"}
        end
    end
  end

  # Check if a string looks like an IP address
  defp is_ip_address?(str) when is_binary(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, _} -> true
      _ -> false
    end
  end
  defp is_ip_address?(_), do: false

  # Forward event to remote node via HTTPS GraphQL endpoint
  @doc false
  def forward_event_via_http(peer_ip, sentant_id, event, parameters, passthrough, sender) do
    url = "https://#{peer_ip}:4005/reality2"

    query = """
    mutation SendEvent($path: String!, $event: String!, $parameters: Json, $passthrough: Json, $sender: SenderInput) {
      sentantSend(path: $path, event: $event, parameters: $parameters, passthrough: $passthrough, sender: $sender) {
        id
        name
      }
    }
    """

    # Parameters and passthrough need to be JSON strings for the Json scalar type
    params_json = if is_map(parameters), do: Jason.encode!(parameters), else: parameters
    passthrough_json = if is_map(passthrough), do: Jason.encode!(passthrough), else: passthrough

    # Convert sender to GraphQL input format
    sender_input = if sender do
      %{
        sentantId: Map.get(sender, :sentant_id),
        sentantName: Map.get(sender, :sentant_name),
        nodeId: Map.get(sender, :node_id),
        nodeName: Map.get(sender, :node_name)
      }
    else
      nil
    end

    body = Jason.encode!(%{
      query: query,
      variables: %{
        path: sentant_id,
        event: event,
        parameters: params_json,
        passthrough: passthrough_json,
        sender: sender_input
      }
    })

    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"sentantSend" => sentant_data}}} when not is_nil(sentant_data) ->
            Logger.info("[SentantResolver] Successfully forwarded event to remote sentant")
            # Return a minimal response indicating success
            {:ok, %{id: sentant_id, name: Map.get(sentant_data, "name", "remote")}}

          {:ok, %{"errors" => errors}} ->
            error_msg = errors |> Enum.map(& &1["message"]) |> Enum.join(", ")
            Logger.warning("[SentantResolver] Remote node returned error: #{error_msg}")
            {:error, :remote_error}

          _ ->
            {:error, :invalid_response}
        end

      {:ok, %Finch.Response{status: status}} ->
        Logger.warning("[SentantResolver] Remote node returned HTTP #{status}")
        {:error, :http_error}

      {:error, reason} ->
        Logger.warning("[SentantResolver] Failed to reach remote node: #{inspect(reason)}")
        {:error, :connection_failed}
    end
  end
end
