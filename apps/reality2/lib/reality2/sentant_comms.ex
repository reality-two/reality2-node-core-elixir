defmodule Reality2.Sentant.Comms do
# *******************************************************************************************************************************************
@moduledoc false
# Manage the communications to and from the Sentant and Automations.
#
# **Author**
# - Dr. Roy C. Davies
# - [roycdavies.github.io](https://roycdavies.github.io/)
# *******************************************************************************************************************************************
  use GenServer
  # alias Absinthe.Subscription
  alias Reality2.Helpers.R2Process, as: R2Process
  alias Reality2.Helpers.R2Map, as: R2Map
  # alias :mnesia, as: Mnesia

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def start_link({name, id, sentant_map}) do
    GenServer.start_link(__MODULE__, {name, id, sentant_map})
    |> R2Process.register(id <> "|comms")
  end

  @impl true
  def init({_name, id, sentant_map}) do
    {:ok, {id, sentant_map}}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Synchronous Calls
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Return the current definition of the Sentant
  @impl true
  def handle_call(:definition, _from, {id, sentant_map}) do
    {:reply, sentant_map |> convert_map_keys |> convert_for_output, {id, sentant_map}}
  end

  # Return the states of all the Automations on the Sentant
  def handle_call(command_and_parameters, _from, {id, sentant_map}) do

    result = R2Process.pid(id <> "|automations")
    |> DynamicSupervisor.which_children()
    |> Enum.map( fn {_, pid_or_restarting, _, _} ->
      # Send the message to each child
      case pid_or_restarting do
        :restarting ->
          # Ignore
          :ok
        pid ->
          if (Application.get_env(:reality2, :build_env) != :prod) do
            IO.puts("SentantComms: Sending command to automation: " <> inspect(pid) <> " : " <> inspect(command_and_parameters))
          end
          GenServer.call(pid, command_and_parameters)
      end
    end)

    {:reply, result, {id, sentant_map}}
  end

  def handle_call(_, _, state) do
    {:reply, :ok, state}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Asynchronous Casts
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def handle_cast(command_and_parameters, {id, sentant_map}) do

    R2Process.pid(id <> "|automations")
    |> DynamicSupervisor.which_children()
    |> Enum.each( fn {_, pid_or_restarting, _, _} ->
      # Send the message to each child
      case pid_or_restarting do
        :restarting ->
          # Ignore
          :ok
        pid ->
          # Send to each automation
          if (Application.get_env(:reality2, :build_env) != :prod) do
            IO.puts("SentantComms: Sending command to automation: " <> inspect(pid) <> " : " <> inspect(command_and_parameters))
          end
          GenServer.cast(pid, command_and_parameters)
      end
    end)

    {:noreply, {id, sentant_map}}
  end

  def handle_cast(_, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(command_and_parameters, {id, sentant_map}) do
    handle_cast(command_and_parameters, {id, sentant_map})
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Convert map keys to atoms
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp convert_map_keys(data) when is_map(data) do
    Enum.map(data, fn {k, v} ->
      cond do
        is_binary(k) -> {String.to_atom(k), convert_map_keys(v)}
        true -> {k, convert_map_keys(v)}
      end
    end)
    |> Map.new
  end
  defp convert_map_keys(data) when is_list(data), do: Enum.map(data, fn x -> convert_map_keys(x) end)
  defp convert_map_keys(data), do: data
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Tweak the raw Sentant data to remove private elements
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp convert_for_output(data) when is_map(data) do
    automations = data |> R2Map.get(:automations, [])
    events = automations |> find_events_in_automations
    signals = automations |> find_signals_in_automations

    data
    |> Map.drop([:automations, :plugins])
    |> Map.put(:events, events)
    |> Map.put(:signals, signals)
  end
  defp convert_for_output(data) when is_list(data), do: Enum.map(data, fn x -> convert_for_output(x) end)
  defp convert_for_output(data), do: data

  defp find_events_in_automations(automations) do
    Enum.map(automations, fn(automation) -> automation |> R2Map.get(:transitions, []) |> find_events end) |> List.flatten |> Enum.uniq
  end
  defp find_events([]), do: []
  defp find_events([transition | rest]) do
    # Only include the event if it is marked as public = true
    case R2Map.get(transition, :public, false) do
      true ->
          [%{event: R2Map.get(transition, :event), parameters: R2Map.get(transition, :parameters, %{})} | find_events(rest)]

      _ -> find_events(rest)
    end
  end

  defp find_signals_in_automations(automations) do
    Enum.map(automations, fn(automation) -> automation |> R2Map.get(:transitions, []) |> find_signals end) |> List.flatten |> Enum.uniq
  end
  defp find_signals([]), do: []
  defp find_signals([transition | rest]) do
    case R2Map.get(transition, :actions, []) do
      [] -> find_signals(rest)
      actions ->
        signals = Enum.map(actions, fn(action) -> get_signal_from_action(action) end) |> List.flatten
        signals ++ find_signals(rest)
    end
  end
  defp get_signal_from_action(action) do
    case R2Map.get(action, :command) do
      "signal" ->
        case R2Map.get(action, :parameters) do
          nil -> []
          parameters ->
            case R2Map.get(action, :public, false) or R2Map.get(parameters, :public, false) do
              false -> []
              true -> [R2Map.get(parameters, :event, [])]
            end
        end
      _ -> []
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------

end
