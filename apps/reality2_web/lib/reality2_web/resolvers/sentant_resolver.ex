defmodule Reality2Web.SentantResolver do
  # *******************************************************************************************************************************************
  @moduledoc false
  # Resolvers for the GraphQL Schema for Sentants and Swarms.
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)
  # *******************************************************************************************************************************************

  # alias Absinthe.PubSub
  alias Reality2.Helpers.R2Map, as: R2Map

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Puplic Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get the details of a single Sentant by ID or name.
  # Includes node_id and node_name for attribution.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def get_sentant(_, args, _) do
    case Map.get(args, :name) do
      nil ->
        case Map.get(args, :id) do
          nil ->
            {:error, :name_or_id}

          sentantid ->
            case Reality2.Sentants.read(%{id: sentantid}, :definition) do
              {:ok, sentant} ->
                {:ok, add_node_attribution(sentant)}

              {:error, reason} ->
                {:error, reason}
            end
        end

      name ->
        case Reality2.Sentants.read(%{name: name}, :definition) do
          {:ok, sentant} ->
            {:ok, add_node_attribution(sentant)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Add node_id and node_name to a sentant for attribution
  defp add_node_attribution(sentant) do
    Map.merge(sentant, %{
      node_id: Reality2.Bootstrap.get(:node_id),
      node_name: Reality2.Bootstrap.get(:node_name)
    })
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get all the Sentants on this Node.  TODO: Search criteria and privacy / ownership
  # When hosting a hotspot, also includes sentants registered by connected mesh clients.
  # This enables client-to-client discovery through the host.
  # Excludes the requesting peer's own sentants to prevent duplicates.
  # Each sentant includes node_id and node_name for attribution.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def all_sentants(_, _, %{context: context}) do
    {:ok, local_sentants} = Reality2.Sentants.read_all(:definition)

    # Get this node's identity for attribution
    this_node_id = Reality2.Bootstrap.get(:node_id)
    this_node_name = Reality2.Bootstrap.get(:node_name)

    # Add node attribution to local sentants
    local_with_node = Enum.map(local_sentants, fn sentant ->
      Map.merge(sentant, %{
        node_id: this_node_id,
        node_name: this_node_name
      })
    end)

    # Get the requesting client's IP to filter out their own sentants
    requesting_ip = Map.get(context, :remote_ip)

    # If we're hosting, also include sentants from registered mesh clients
    # but exclude sentants from the requesting peer
    remote_sentants = get_registered_client_sentants(requesting_ip)

    {:ok, local_with_node ++ remote_sentants}
  end

  # Fallback for when context is not available
  def all_sentants(_, _, _) do
    {:ok, local_sentants} = Reality2.Sentants.read_all(:definition)

    # Get this node's identity for attribution
    this_node_id = Reality2.Bootstrap.get(:node_id)
    this_node_name = Reality2.Bootstrap.get(:node_name)

    # Add node attribution to local sentants
    local_with_node = Enum.map(local_sentants, fn sentant ->
      Map.merge(sentant, %{
        node_id: this_node_id,
        node_name: this_node_name
      })
    end)

    remote_sentants = get_registered_client_sentants(nil)
    {:ok, local_with_node ++ remote_sentants}
  end

  # Get sentants from mesh clients that have registered with us (when we're hosting)
  # Optionally excludes sentants from a peer at the given IP address
  # Includes node_id and node_name for each sentant's origin node
  defp get_registered_client_sentants(exclude_ip) do
    require Logger

    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case apply(AiReality2Transnet.PeerManager, :get_all_peers, []) do
        peers when is_map(peers) ->
          # Debug: log all peers and their transport status
          Logger.info("[SentantResolver] get_registered_client_sentants called, exclude_ip: #{inspect(exclude_ip)}")
          Logger.info("[SentantResolver] Found #{map_size(peers)} peers in PeerManager")
          Enum.each(peers, fn {peer_id, peer_info} ->
            transport = Map.get(peer_info, :transport)
            sentant_count = length(Map.get(peer_info, :sentants, []))
            node_name = Map.get(peer_info, :node_name, "?")
            Logger.info("[SentantResolver] Peer #{node_name} (#{String.slice(peer_id, 0..7)}...): transport=#{inspect(transport)}, sentants=#{sentant_count}")
          end)

          peers
          |> Enum.flat_map(fn {peer_id, peer_info} ->
            peer_address = Map.get(peer_info, :address)

            # Only include sentants from peers connected via wifi_hotspot (registered clients)
            # AND exclude the requesting peer's own sentants (to prevent duplicates)
            if Map.get(peer_info, :transport) == :wifi_hotspot and
               (exclude_ip == nil or peer_address != exclude_ip) do
              peer_sentants = Map.get(peer_info, :sentants, [])
              peer_node_name = Map.get(peer_info, :node_name, "Unknown")

              # Convert string-keyed maps to atom-keyed for GraphQL compatibility
              # Include node attribution from the peer
              Enum.map(peer_sentants, fn sentant ->
                %{
                  id: Map.get(sentant, "id") || Map.get(sentant, :id),
                  name: Map.get(sentant, "name") || Map.get(sentant, :name),
                  description: Map.get(sentant, "description") || Map.get(sentant, :description) || "",
                  events: normalize_events(Map.get(sentant, "events") || Map.get(sentant, :events) || []),
                  signals: normalize_signals(Map.get(sentant, "signals") || Map.get(sentant, :signals) || []),
                  # Node attribution from the peer
                  node_id: peer_id,
                  node_name: peer_node_name
                }
              end)
            else
              []
            end
          end)

        _ ->
          []
      end
    else
      []
    end
  end

  # Normalize events to the expected format with parameters as a map
  defp normalize_events(events) when is_list(events) do
    Enum.map(events, fn
      event when is_binary(event) -> %{event: event, parameters: %{}}
      %{"event" => name} = e -> %{event: name, parameters: normalize_parameters(Map.get(e, "parameters"))}
      %{event: name} = e -> %{event: name, parameters: normalize_parameters(Map.get(e, :parameters))}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp normalize_events(_), do: []

  # Ensure parameters is a map (not a list or nil)
  defp normalize_parameters(params) when is_map(params), do: params
  defp normalize_parameters(_), do: %{}

  # Normalize signals to expected format
  defp normalize_signals(signals) when is_list(signals) do
    Enum.map(signals, fn
      signal when is_binary(signal) -> signal
      %{"signal" => name} -> name
      %{signal: name} -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp normalize_signals(_), do: []

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Load a Sentant from the definition.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def load_sentant(_root, args, %{context: context}) do
    # Local or remote IP?
    local = Map.get(context, :local?, false)

    case Map.get(args, :definition) do
      nil ->
        # There was no definition
        {:error, :definition}

      definition ->
        # Decode the definition from encoded uri
        decoded = URI.decode(definition)

        # Create the Sentant (or update it if it already exists and the ID is given)
        case Reality2.Sentants.create(decoded, local) do
          # Success, so get the Sentant details to send back
          {:ok, sentantid} ->
            # Read the sentant details from the Sentant
            case Reality2.Sentants.read(%{id: sentantid}, :definition) do
              {:ok, sentant} ->
                # Send back the sentant details with node attribution
                {:ok, add_node_attribution(sentant)}

              {:error, reason} ->
                # Something went wrong
                {:error, reason}
            end

          {:error, {_, reason}} ->
            {:error, reason}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Unload (delete) a Sentant by ID.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def unload_sentant(_root, args, %{context: context}) do
    # Local or remote IP?
    local = Map.get(context, :local?, false)

    # Delete a sentant
    case Map.get(args, :id) do
      nil ->
        {:error, :id}

      sentantid ->
        # Get the details of the Sentant before it is deleted
        case Reality2.Sentants.read(%{id: sentantid}, :definition) do
          {:ok, sentant} ->
            case Reality2.Sentants.delete(%{id: sentantid}, local) do
              {:ok, _} ->
                # Send back the sentant details with node attribution
                {:ok, add_node_attribution(sentant)}

              {:error, reason} ->
                # Something went wrong
                {:error, reason}
            end

          {:error, reason} ->
            # Something went wrong
            {:error, reason}
        end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Load a Swarm of Sentants from the definition.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec load_swarm(any(), map(), any()) :: {:error, :definition}

  def load_swarm(_root, args, %{context: context}) do
    # Local or remote IP?
    local = Map.get(context, :local?, false)

    # Create a new swarm
    case Map.get(args, :definition) do
      nil ->
        {:error, :definition}

      definition ->
        # Decode the definition from encoded uri
        decoded = URI.decode(definition)

        # Create the Swarm
        case Reality2.Swarm.create(decoded, local) do
          {:error, reason} ->
            {:error, reason}

          {:ok, swarm} ->
            name = R2Map.get(swarm, "name", "")
            description = R2Map.get(swarm, "description", "")
            sentant_ids = R2Map.get(swarm, "sentants", [])

            # Create a list of the sentants' details with node attribution
            sentants =
              Enum.map(sentant_ids, fn id ->
                case Reality2.Sentants.read(%{id: id}, :definition) do
                  {:ok, sentant} ->
                    add_node_attribution(sentant)

                  {:error, _reason} ->
                    # Something went wrong
                    false
                end
              end)
              |> Enum.filter(fn x -> x end)

            {:ok, %{name: name, description: description, sentants: sentants}}
        end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Send an event to a Sentant
  # Path can be: name, UUID, or node|sentant (using names or UUIDs in either position)
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec send_event(any(), map(), any()) ::
          {:error, :event | :existance | :path | :invalid_event | :name}
  def send_event(_root, args, _info) do
    require Logger

    # Get the path (can be name, UUID, or node|sentant format)
    case Map.get(args, :path) do
      nil ->
        {:error, :path}

      path ->
        Logger.info("[SentantResolver] send_event called with path: #{path}")

        # Get the event
        case Map.get(args, :event) do
          nil ->
            {:error, :event}

          event ->
            parameters = Map.get(args, :parameters, %{})
            passthrough = Map.get(args, :passthrough, %{})

            # Parse the path to determine if local or remote
            parsed = parse_path(path)
            Logger.info("[SentantResolver] Parsed path: #{inspect(parsed)}")

            case parsed do
              {:remote, node_ref, sentant_ref} ->
                Logger.info("[SentantResolver] Routing to REMOTE node #{String.slice(node_ref, 0..7)}...")
                send_event_to_remote(node_ref, sentant_ref, event, parameters, passthrough)

              {:local, sentant_ref} ->
                Logger.info("[SentantResolver] Routing to LOCAL sentant #{String.slice(sentant_ref, 0..7)}...")
                send_event_to_local(sentant_ref, event, parameters, passthrough)
            end
        end
    end
  end

  # Parse path to determine if local or remote
  # Accepts: UUID, name, node|sentant (using names or UUIDs in either position)
  # Returns {:remote, node_ref, sentant_ref} or {:local, sentant_ref}
  defp parse_path(path) do
    require Logger
    local_node_id = Reality2.Bootstrap.get(:node_id)

    case String.split(path, "|", parts: 2) do
      [node_ref, sentant_ref] ->
        # Resolve node reference to ID (could be UUID or name)
        resolved_node_id = resolve_node_ref(node_ref)

        if resolved_node_id == local_node_id do
          # Local node - resolve sentant ref
          {:local, resolve_sentant_ref(sentant_ref)}
        else
          # Remote node
          {:remote, resolved_node_id || node_ref, sentant_ref}
        end

      [sentant_ref] ->
        # No separator - local sentant (could be UUID or name)
        {:local, sentant_ref}
    end
  end

  # Resolve a node reference (UUID or name) to node ID
  defp resolve_node_ref(ref) do
    local_node_id = Reality2.Bootstrap.get(:node_id)
    local_node_name = Reality2.Bootstrap.get(:node_name)

    cond do
      ref == local_node_id -> local_node_id
      ref == local_node_name -> local_node_id
      is_uuid?(ref) -> ref
      true ->
        # Try to look up by name in PeerManager
        if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
          case apply(AiReality2Transnet.PeerManager, :get_peer_by_name, [ref]) do
            {:ok, peer} -> Map.get(peer, :node_id)
            _ -> nil
          end
        else
          nil
        end
    end
  end

  # Resolve a sentant reference (UUID or name) to sentant ID
  defp resolve_sentant_ref(ref) do
    if is_uuid?(ref) do
      ref
    else
      # Try to look up by name locally
      case Reality2.Metadata.get(:SentantIDs, ref) do
        nil -> ref  # Return as-is, let downstream handle it
        id -> id
      end
    end
  end

  # Check if a string looks like a UUID
  defp is_uuid?(str) do
    case UUID.info(str) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # Send event to a local sentant (sentant_ref can be UUID or name)
  defp send_event_to_local(sentant_ref, event, parameters, passthrough) do
    # Determine if we have a UUID or a name
    sentant_key = if is_uuid?(sentant_ref), do: %{id: sentant_ref}, else: %{name: sentant_ref}

    case Reality2.Sentants.read(sentant_key, :definition) do
      {:ok, sentant} ->
        events = get_event_list(R2Map.get(sentant, :events, []))

        if Enum.member?(events, event) do
          case Reality2.Sentants.sendto(sentant_key, %{
                 event: event,
                 parameters: parameters,
                 passthrough: passthrough
               }) do
            {:ok, _} ->
              {:ok, add_node_attribution(sentant)}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, :invalid_event}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Send event to a remote sentant via HTTP
  defp send_event_to_remote(node_id, sentant_id, event, parameters, passthrough) do
    require Logger

    # Look up the peer's IP address from PeerManager
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case apply(AiReality2Transnet.PeerManager, :get_peer, [node_id]) do
        {:ok, peer} ->
          peer_address = Map.get(peer, :address)
          peer_name = Map.get(peer, :node_name, "Unknown")

          # Determine the best IP to use for HTTP communication
          case get_http_address_for_peer(peer_address) do
            {:ok, ip_address} ->
              Logger.info("[SentantResolver] Forwarding event '#{event}' to remote sentant #{String.slice(sentant_id, 0..7)}... on #{peer_name} (#{ip_address})")
              forward_event_via_http(ip_address, sentant_id, event, parameters, passthrough)

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
        if Code.ensure_loaded?(AiReality2Transnet.ConnectionManager) do
          case apply(AiReality2Transnet.ConnectionManager, :get_gateway_ip, []) do
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
  defp forward_event_via_http(peer_ip, sentant_id, event, parameters, passthrough) do
    require Logger

    url = "https://#{peer_ip}:4005/reality2"

    query = """
    mutation SendEvent($id: String!, $event: String!, $parameters: Json, $passthrough: Json) {
      sentantSend(id: $id, event: $event, parameters: $parameters, passthrough: $passthrough) {
        id
        name
      }
    }
    """

    # Parameters and passthrough need to be JSON strings for the Json scalar type
    params_json = if is_map(parameters), do: Jason.encode!(parameters), else: parameters
    passthrough_json = if is_map(passthrough), do: Jason.encode!(passthrough), else: passthrough

    body = Jason.encode!(%{
      query: query,
      variables: %{
        id: sentant_id,
        event: event,
        parameters: params_json,
        passthrough: passthrough_json
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

  defp get_event_list([]), do: []

  defp get_event_list([%{event: event, parameters: _params} | rest]) do
    [event | get_event_list(rest)]
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec check_subscribe_allowed(Reality2.Types.uuid(), any()) :: boolean()
  def check_subscribe_allowed(sentantid, signal) do
    case Reality2.Sentants.read(%{id: sentantid}, :definition) do
      {:ok, sentant} ->
        ((sentant |> R2Map.get(:signals, [])) ++ ["debug"]) |> Enum.member?(signal)

      _ ->
        false
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Send a signal from a Sentant. Delegates to Reality2.Signals.broadcast/4.

  This function is kept for backwards compatibility but the core logic
  now lives in the Reality2 core app to avoid tight coupling.
  """
  @spec send_signal(Reality2.Types.uuid(), any(), any(), any()) :: false | :ok
  def send_signal(id, event, parameters, passthrough) do
    Reality2.Signals.broadcast(id, event, parameters, passthrough)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
end
