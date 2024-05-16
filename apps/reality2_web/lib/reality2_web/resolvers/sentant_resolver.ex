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
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def all_sentants(_, _, _) do
    case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} ->
        {:ok, Enum.map(sentants, fn sentant -> sentant end)}
      {:error, reason} ->
        {:error, reason}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Load a Sentant from the definition.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def load_sentant(_root, args, _info) do
    case Map.get(args, :definition) do
      nil ->
        # There was no definition
        {:error, :definition}
      definition ->
        # Decode the definition from encoded uri
        decoded = URI.decode(definition)

        # Create the Sentant (or update it if it already exists and the ID is given)
        case Reality2.Sentants.create(decoded) do
          # Success, so get the Sentant details to send back
          {:ok, sentantid} ->
            # Read the sentant detals from the Sentant
            case Reality2.Sentants.read(%{id: sentantid}, :definition) do
              {:ok, sentant} ->
                # Send back the sentant details
                {:ok, sentant}
              {:error, reason} ->
                # Something went wrong
                {:error, reason}
            end
          {:error, {error_code, reason}} -> {:error, Atom.to_string(error_code) <> ":" <> reason}
          {:error, reason} -> {:error, reason}
        end
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Unload (delete) a Sentant by ID.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def unload_sentant(_root, args, _info) do

    # Delete a sentant
    case Map.get(args, :id) do
      nil ->
        {:error, :id}
      sentantid ->
        # Get the details of the Sentant before it is deleted
        case Reality2.Sentants.read(%{id: sentantid}, :definition) do
          {:ok, sentant} ->
            case Reality2.Sentants.delete(%{id: sentantid}) do
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
  def load_swarm(_root, args, _info) do
    # Create a new swarm
    case Map.get(args, :definition) do
      nil ->
        {:error, :definition}
      definition ->
        # Decode the definition from encoded uri
        decoded = URI.decode(definition)

        # Create the Swarm
        case Reality2.Swarm.create(decoded) do
          {:error, {error_code, reason}} -> {:error, Atom.to_string(error_code) <> ":" <> reason}
          {:error, reason} -> {:error, reason}
          {:ok, swarm} ->
            name = Helpers.Map.get(swarm, "name", "")
            description = Helpers.Map.get(swarm, "description", "")
            sentant_ids = Helpers.Map.get(swarm, "sentants", [])

            # Create a list of the sentants' details
            sentants = Enum.map(sentant_ids, fn id ->
              case Reality2.Sentants.read(%{id: id}, :definition) do
                {:ok, sentant} ->
                  sentant
                {:error, _reason} ->
                  # Something went wrong
                  false
              end
            end) |> Enum.filter(fn x -> x end)

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
                events = get_event_list(Helpers.Map.get(sentant, :events, [])) #sentant |> Helpers.Map.get(:automations, []) |> find_events_in_automations(false)
                if Enum.member?(events, event) do
                  case Reality2.Sentants.sendto(%{id: sentantid}, %{event: event, parameters: parameters, passthrough: passthrough}) do
                    {:ok, _} ->
                      {:ok, sentant}
                    {:error, reason} ->
                      # Something went wrong
                      {:error, reason}
                  end
                else
                  {:error, :invalid_event}
                end
              {:error, reason} -> {:error, reason}
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
        ((sentant |> Helpers.Map.get(:signals, [])) ++ ["debug"]) |> Enum.member?(signal)
      _ -> false
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec send_signal(Reality2.Types.uuid(), any(), any(), any()) :: false | :ok
  def send_signal(id, event, parameters, passthrough) do
    case Reality2.Sentants.read(%{id: id}, :definition) do
      {:ok, sentant} ->
        the_sentant = sentant
        subscription_data = %{
          sentant: the_sentant,
          event: event,
          parameters: parameters,
          passthrough: passthrough
        }
        Absinthe.Subscription.publish(Reality2Web.Endpoint, subscription_data, await_signal: id <> "|" <> event)
      {:error, _reason} ->
        # Something went wrong
        false
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
end
