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
  require Logger
  alias Reality2.Helpers.R2Map, as: R2Map
  alias Reality2Web.SentantResolver.PathResolver
  alias Reality2Web.SentantResolver.RemoteForwarder

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Puplic Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get the details of a single Sentant by ID or name.
  # Includes node_id and node_name for attribution.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def get_sentant(_, args, _) do
    sentant_key =
      cond do
        Map.get(args, :name) -> %{name: Map.get(args, :name)}
        Map.get(args, :id) -> %{id: Map.get(args, :id)}
        true -> nil
      end

    case sentant_key do
      nil ->
        {:error, :name_or_id}

      key ->
        with {:ok, sentant} <- Reality2.Sentants.read(key, :definition) do
          {:ok, add_node_attribution(sentant)}
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
    if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
      case apply(Reality2Transnet.PeerManager, :get_all_peers, []) do
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
  # Path can be: name, UUID, node|sentant, or @sender (for replies)
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec send_event(any(), map(), any()) ::
          {:error, :event | :existance | :path | :invalid_event | :name}
  def send_event(_root, args, _info) do
    with {:ok, path} <- require_arg(args, :path),
         {:ok, event} <- require_arg(args, :event) do
      Logger.info("[SentantResolver] send_event called with path: #{path}")

      parameters = Map.get(args, :parameters, %{})
      passthrough = Map.get(args, :passthrough, %{})
      sender = build_sender(Map.get(args, :sender))

      parsed = PathResolver.parse_path(path)
      Logger.info("[SentantResolver] Parsed path: #{inspect(parsed)}")

      case parsed do
        {:remote, node_ref, sentant_ref} ->
          Logger.info("[SentantResolver] Routing to REMOTE node #{String.slice(node_ref, 0..7)}...")
          RemoteForwarder.send_event_to_remote(node_ref, sentant_ref, event, parameters, passthrough, sender)

        {:local, sentant_ref} ->
          Logger.info("[SentantResolver] Routing to LOCAL sentant #{String.slice(sentant_ref, 0..7)}...")
          send_event_to_local(sentant_ref, event, parameters, passthrough, sender)
      end
    end
  end

  defp require_arg(args, key) do
    case Map.get(args, key) do
      nil -> {:error, key}
      value -> {:ok, value}
    end
  end

  # SECURITY TODO: Sender spoofing prevention
  # The sender field in sentantSend mutations is currently trusted as-is from
  # the GraphQL client. A malicious client can forge sender identity, tricking
  # automations that use @sender for routing.
  # Plan:
  # 1. For external API calls (no sender provided), always populate sender
  #    from this node's identity (already done below).
  # 2. For forwarded cross-node calls, validate that the sender's node_id
  #    matches the source IP's registered peer identity in PeerManager.
  # 3. Consider signing sender info with the sending node's TrustGroup key so the
  #    recipient can verify authenticity.

  # Build sender info from provided input or create default from this node
  defp build_sender(nil) do
    # No sender provided - use this node as origin (external API call)
    %{
      sentant_id: nil,
      sentant_name: nil,
      node_id: Reality2.Bootstrap.get(:node_id),
      node_name: Reality2.Bootstrap.get(:node_name)
    }
  end

  defp build_sender(sender_input) when is_map(sender_input) do
    # Use provided sender, filling in node info if missing
    %{
      sentant_id: Map.get(sender_input, :sentant_id) || Map.get(sender_input, "sentant_id"),
      sentant_name: Map.get(sender_input, :sentant_name) || Map.get(sender_input, "sentant_name"),
      node_id: Map.get(sender_input, :node_id) || Map.get(sender_input, "node_id") || Reality2.Bootstrap.get(:node_id),
      node_name: Map.get(sender_input, :node_name) || Map.get(sender_input, "node_name") || Reality2.Bootstrap.get(:node_name)
    }
  end


  # Send event to a local sentant (sentant_ref can be UUID or name)
  defp send_event_to_local(sentant_ref, event, parameters, passthrough, sender) do
    # Determine if we have a UUID or a name
    sentant_key = if PathResolver.is_uuid?(sentant_ref), do: %{id: sentant_ref}, else: %{name: sentant_ref}

    case Reality2.Sentants.read(sentant_key, :definition) do
      {:ok, sentant} ->
        events = get_event_list(R2Map.get(sentant, :events, []))

        if Enum.member?(events, event) do
          case Reality2.Sentants.sendto(sentant_key, %{
                 event: event,
                 parameters: parameters,
                 passthrough: passthrough,
                 sender: sender
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


  defp get_event_list(events) do
    Enum.map(events, & &1.event)
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
