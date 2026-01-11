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
                {:ok, sentant}

              {:error, reason} ->
                {:error, reason}
            end
        end

      name ->
        case Reality2.Sentants.read(%{name: name}, :definition) do
          {:ok, sentant} ->
            {:ok, sentant}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get all the Sentants on this Node.  TODO: Search criteria and privacy / ownership
  # When hosting a hotspot, also includes sentants registered by connected mesh clients.
  # This enables client-to-client discovery through the host.
  # Excludes the requesting peer's own sentants to prevent duplicates.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def all_sentants(_, _, %{context: context}) do
    {:ok, local_sentants} = Reality2.Sentants.read_all(:definition)

    # Get the requesting client's IP to filter out their own sentants
    requesting_ip = Map.get(context, :remote_ip)

    # If we're hosting, also include sentants from registered mesh clients
    # but exclude sentants from the requesting peer
    remote_sentants = get_registered_client_sentants(requesting_ip)

    all = local_sentants ++ remote_sentants
    {:ok, Enum.map(all, fn sentant -> sentant end)}
  end

  # Fallback for when context is not available
  def all_sentants(_, _, _) do
    {:ok, local_sentants} = Reality2.Sentants.read_all(:definition)
    remote_sentants = get_registered_client_sentants(nil)
    all = local_sentants ++ remote_sentants
    {:ok, Enum.map(all, fn sentant -> sentant end)}
  end

  # Get sentants from mesh clients that have registered with us (when we're hosting)
  # Optionally excludes sentants from a peer at the given IP address
  defp get_registered_client_sentants(exclude_ip) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case apply(AiReality2Transnet.PeerManager, :get_all_peers, []) do
        peers when is_map(peers) ->
          peers
          |> Enum.flat_map(fn {_peer_id, peer_info} ->
            peer_address = Map.get(peer_info, :address)

            # Only include sentants from peers connected via wifi_hotspot (registered clients)
            # AND exclude the requesting peer's own sentants (to prevent duplicates)
            if Map.get(peer_info, :transport) == :wifi_hotspot and
               (exclude_ip == nil or peer_address != exclude_ip) do
              peer_sentants = Map.get(peer_info, :sentants, [])
              _peer_node_name = Map.get(peer_info, :node_name, "Unknown")

              # Convert string-keyed maps to atom-keyed for GraphQL compatibility
              Enum.map(peer_sentants, fn sentant ->
                %{
                  id: Map.get(sentant, "id") || Map.get(sentant, :id),
                  name: Map.get(sentant, "name") || Map.get(sentant, :name),
                  description: Map.get(sentant, "description") || Map.get(sentant, :description) || "",
                  events: normalize_events(Map.get(sentant, "events") || Map.get(sentant, :events) || []),
                  signals: normalize_signals(Map.get(sentant, "signals") || Map.get(sentant, :signals) || [])
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

  # Normalize events to the expected format
  defp normalize_events(events) when is_list(events) do
    Enum.map(events, fn
      event when is_binary(event) -> %{event: event, parameters: []}
      %{"event" => name} = e -> %{event: name, parameters: Map.get(e, "parameters", [])}
      %{event: name} = e -> %{event: name, parameters: Map.get(e, :parameters, [])}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp normalize_events(_), do: []

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
                # Send back the sentant details
                {:ok, sentant}

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
                # Send back the sentant details
                {:ok, sentant}

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

            # Create a list of the sentants' details
            sentants =
              Enum.map(sentant_ids, fn id ->
                case Reality2.Sentants.read(%{id: id}, :definition) do
                  {:ok, sentant} ->
                    sentant

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
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec send_event(any(), map(), any()) ::
          {:error, :event | :existance | :id | :invalid_event | :name}
  def send_event(_root, args, _info) do
    # Get the Sentant ID
    case Map.get(args, :id) do
      nil ->
        {:error, :id}

      sentantid ->
        # Get the event
        case Map.get(args, :event) do
          nil ->
            {:error, :event}

          event ->
            # Get the parameters
            parameters = Map.get(args, :parameters, %{})
            passthrough = Map.get(args, :passthrough, %{})
            # Send the event to the Sentant
            # Check if this is a valid event that can be sent from outside, and if so, send it.
            case Reality2.Sentants.read(%{id: sentantid}, :definition) do
              {:ok, sentant} ->
                # sentant |> R2Map.get(:automations, []) |> find_events_in_automations(false)
                events = get_event_list(R2Map.get(sentant, :events, []))

                if Enum.member?(events, event) do
                  case Reality2.Sentants.sendto(%{id: sentantid}, %{
                         event: event,
                         parameters: parameters,
                         passthrough: passthrough
                       }) do
                    {:ok, _} ->
                      {:ok, sentant}

                    {:error, reason} ->
                      # Something went wrong
                      {:error, reason}
                  end
                else
                  {:error, :invalid_event}
                end

              {:error, reason} ->
                {:error, reason}
            end
        end
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
