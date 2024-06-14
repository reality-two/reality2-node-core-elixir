defmodule Reality2.Automation do
# ********************************************************************************************************************************************
@moduledoc false
# The Automation on a Sentant, managed as a Finite State Machine.
#
# **Author**
# - Dr. Roy C. Davies
# - [roycdavies.github.io](https://roycdavies.github.io/)
# ********************************************************************************************************************************************

  @doc false
  use GenServer, restart: :transient
  alias Reality2.Helpers.R2Map, as: R2Map
  alias Reality2.Helpers.JsonPath, as: JsonPath
  alias Reality2.Helpers.R2Process, as: R2Process

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link({_sentant_name, id, _sentant_map}, automation_map) do
    case R2Map.get(automation_map, :name) do
      nil ->
        {:error, :definition}
      automation_name ->
        GenServer.start_link(__MODULE__, {automation_name, id, automation_map})
        |> R2Process.register(id <> "|automation|" <> automation_name)
    end
  end

  @impl true
  def init({name, id, automation_map}) do
    {:ok, {name, id, automation_map, "start"}}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Synchronous Calls
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def handle_call(:state, _from, {name, id, automation_map, state}) do
    {:reply, {name, state}, {name, id, automation_map, state}}
  end

  def handle_call(_, _, {name, id, automation_map, state}) do
    {:reply, {:error, :unknown_command}, {name, id, automation_map, state}}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Asynchronous Casts
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def handle_cast(args, {name, id, automation_map, state}) do

    parameters = R2Map.get(args, :parameters, %{})
    passthrough = R2Map.get(args, :passthrough, %{})

    case R2Map.get(args, :event) do
      nil -> {:noreply, {name, id, automation_map, state}}
      event ->
        case R2Map.get(automation_map, "transitions") do
          nil ->
            {:noreply, {name, id, automation_map, state}}
          transitions ->
            new_state =
              Enum.reduce_while(transitions, state,
                fn transition_map, acc_state ->
                  case check_transition(id, transition_map, event, parameters, passthrough, acc_state) do
                    {:no_match, the_state} ->
                      {:cont, the_state}
                    {:ok, the_state} ->
                      {:halt, the_state}
                  end
                end
              )
            {:noreply, {name, id, automation_map, new_state}}
        end
    end
  end

  # Used for sending events in the future using Process.send_after
  @impl true
  def handle_info({:send, name_or_id, %{event: event} = details}, {name, id, automation_map, state}) do
    Reality2.Sentants.sendto(name_or_id, details)
    R2Process.deregister(id <> "|timers|" <> event)
    {:noreply, {name, id, automation_map, state}}
  end
  def handle_info(_, {name, id, automation_map, state}) do
    {:noreply, {name, id, automation_map, state}}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Check the Transition Map to see if it matches the current state and event
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp check_transition(id, transition_map, event, parameters, passthrough, state) do
    case R2Map.get(transition_map, :from, "*") do
      "*" -> check_event(id, transition_map, event, parameters, passthrough, state)
      ^state -> check_event(id, transition_map, event, parameters, passthrough, state)
      _ -> {:no_match, state}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Check the Event Map to see if it matches the current event, and do appropiate actions and state change if it does
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp check_event(id, transition_map, event, parameters, passthrough, state) do
    case R2Map.get(transition_map, :event) do
      nil ->
        {:no_match, state}
      ^event ->
        case R2Map.get(transition_map, :to, "*") do
          "*" ->
            do_actions(id, transition_map, parameters, passthrough)
            {:ok, state}
          to ->
            do_actions(id, transition_map, parameters, passthrough)
            {:ok, to}
        end
      _ ->
        {:no_match, state}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Do the Actions in the Transition Map when the Transition triggers
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp do_actions(id, transition_map, parameters, passthrough) do
    case R2Map.get(transition_map, :actions) do
      nil ->
        parameters # No actions, so result is just the parameters
      actions ->
        # Do each action in turn, accumulating the results
        # Parameters comes in from 'outside' and then accumulates through each action that is done
        # So, the result of do_action becomes the accumulated_parameters to the next action
        Enum.reduce(actions, parameters, fn action_map, accumulated_parameters ->
          do_action(id, action_map, accumulated_parameters, passthrough)
        end)
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Do a single Action
  # An Action might be like:
  # %{  "command" => "send",
  #     "parameters" =>
  #         %{  "delay" => 1000,
  #             "event" => "turn_on",
  #             "to" => "Light Bulb"
  #         }
  # }
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp do_action(id, action_map, accumulated_parameters, passthrough) do
    action_parameters = R2Map.get(action_map, :parameters, %{})

    # Both the functions below return a map that becomes the accumulater parameters of the next action
    case R2Map.get(action_map, :plugin) do
      nil ->
        R2Map.get(action_map, :command)
        |> do_inbuilt_action(id, action_parameters, accumulated_parameters, passthrough)
      plugin ->
        R2Map.get(action_map, :command)
        |> do_plugin_action(plugin, id, action_parameters, accumulated_parameters, passthrough)
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Do a Plugin Action
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp do_plugin_action(action, plugin, id, action_parameters, accumulated_parameters, passthrough) do
    override = R2Map.get(action_parameters, :override, false)
    combined_parameters = if (override) do
      Map.merge(accumulated_parameters, action_parameters)
    else
      Map.merge(action_parameters, accumulated_parameters)
    end
    |> interpret()

    # When the sentant begins, there is a small possibiity that the plugin has not yet started.
    case test_and_wait(id <> "|plugin|" <> plugin, 5) do
      nil ->
        IO.puts("Plugin not yet started: #{plugin}")
        accumulated_parameters
        |> Map.merge(%{result: %{error: :plugin_error}})
      pid ->
        IO.puts("Calling Plugin: #{plugin}")
        # Call the plugin on the Sentant, which in turn will call the appropriate internal App or external plugin
        case GenServer.call(pid, %{command: action, parameters: combined_parameters, passthrough: passthrough}) do
          {:ok, result} ->
            accumulated_parameters
            |> Map.merge(result)
            |> Map.merge(%{result: :ok})
          {:error, reason} ->
            accumulated_parameters
            |> Map.merge(%{result: %{error: reason}})
        end
    end
  end

  defp test_and_wait(_, 0), do: nil
  defp test_and_wait(name, count) do
    case R2Process.whereis(name) do
      nil ->
        Process.sleep(100)
        test_and_wait(name, count - 1)
      pid -> pid
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Do an Inbuilt Action
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp do_inbuilt_action(action, id, action_parameters, accumulated_parameters, passthrough) do
    case action do
      "send" -> send(id, action_parameters, accumulated_parameters, passthrough)
      "debug" -> debug(id, action_parameters, accumulated_parameters, passthrough)
      "set" -> set(id, action_parameters, accumulated_parameters, passthrough)
      "signal" -> signal(id, action_parameters, accumulated_parameters, passthrough)
      _ -> accumulated_parameters |> Map.merge(%{result: :invalid_command})
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Send
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp send(id, action_parameters, accumulated_parameters, passthrough) do

    override = R2Map.get(action_parameters, :override, false)
    combined_parameters = if (override) do
      Map.merge(accumulated_parameters, action_parameters)
    else
      Map.merge(action_parameters, accumulated_parameters)
    end
    |> interpret()

    # Get the 'to' parameter, if it exists.  If not, return an empty list.
    to_field = R2Map.get(combined_parameters, :to, [id])

    # If the 'to' parameter was not a list, turn it into one with a single element.
    to_list = case is_list(to_field) do
      true -> to_field
      false -> [to_field]
    end

    # Go through the list, sending the event to each one.
    for to <- to_list do

      # Create a map with either the name or the ID of the Sentant to send the event to.
      name_or_id = case Reality2.Metadata.get(:SentantIDs, to) do
        nil ->
          %{id: to}  # Not a Name for a Sentant on this Node, so send to the Sentant with that ID.
        id ->
          %{id: id}    # Must have been a name.
      end

      # Get the event to send.
      event = R2Map.get(combined_parameters, :event, "event")
      event_parameters = R2Map.get(action_parameters, :parameters, %{})

      # Make sure there is no timer for this event already in process.  If so, cancel it before doing the new one.
      case R2Process.whereis(id <> "|timers|" <> event) do
        nil -> :ok
        timer ->
          Process.cancel_timer(timer)
          R2Process.deregister(id <> "|timers|" <> event)
      end

      # Send the event either immediately or after a delay.
      case R2Map.get(combined_parameters, :delay) do
        nil ->
          Reality2.Sentants.sendto(name_or_id, %{event: event, parameters: Map.merge(event_parameters, accumulated_parameters) |> interpret(), passthrough: passthrough})
        delay ->
          timer = Process.send_after(self(), {:send, name_or_id, %{event: event, parameters: Map.merge(event_parameters, accumulated_parameters) |> interpret(), passthrough: passthrough}}, delay)
          R2Process.register(id <> "|timers|" <> event, timer)
      end

    end

    # No side effects, so just return the parameters sent in
    accumulated_parameters |> Map.merge(%{result: :ok})
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Send a signal on the Sentant's subscription channel
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp signal(id, action_parameters, accumulated_parameters, passthrough) do
    override = R2Map.get(action_parameters, :override, false)
    combined_parameters = if (override) do
      Map.merge(accumulated_parameters, action_parameters)
    else
      Map.merge(action_parameters, accumulated_parameters)
    end
    |> interpret()

    # Send off a signal to any listening device
    case R2Map.get(combined_parameters, :event) do
      nil -> nil
      event ->
        case R2Process.whereis(id <> "|comms") do
          nil ->
            nil
          _pid ->
            event_parameters = R2Map.get(action_parameters, :parameters, %{})
            apply(Reality2Web.SentantResolver, :send_signal, [id, event, Map.merge(event_parameters, accumulated_parameters) |> interpret(), passthrough])
            # Reality2Web.SentantResolver.send_signal(id, event, Map.merge(event_parameters, accumulated_parameters) |> interpret(), passthrough)
        end
    end

    # No side effects, so just return the parameters sent in
    accumulated_parameters |> Map.merge(%{result: :ok})
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Send debug info to the debug channel
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp debug(id, _action_parameters, accumulated_parameters, passthrough) do
    apply(Reality2Web.SentantResolver, :send_signal, [id, "debug", accumulated_parameters, passthrough])
    # Reality2Web.SentantResolver.send_signal(id, "debug", accumulated_parameters, passthrough)

    accumulated_parameters |> Map.merge(%{result: :ok})
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Set a key / value in the accumulated parameters
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp set(_id, action_parameters, accumulated_parameters, _passthrough) do
    override = R2Map.get(action_parameters, :override, false)
    combined_parameters = if (override) do
      Map.merge(accumulated_parameters, action_parameters)
    else
      Map.merge(action_parameters, accumulated_parameters)
    end
    |> interpret()

    key = R2Map.get(combined_parameters, :key)

    # Get the value, and then process it to replace
    value = replace_variable_in_map(R2Map.get(combined_parameters, :value), combined_parameters)

    if value == nil do
      accumulated_parameters
      |> interpret()
      |> R2Map.delete(key)
      |> Map.merge(%{result: :ok})
    else
      # If the value includes %{jsonpath: "the path"} then extract the element from the combined parameters rather than the facevalue"
      if (is_map(value) && R2Map.get(value, :jsonpath) != nil) do
        case JsonPath.get_value(combined_parameters, R2Map.get(value, :jsonpath)) do
          {:ok, value2} ->
            accumulated_parameters
            |> interpret()
            |> Map.merge(%{key => value2})
            |> Map.merge(%{result: :ok})
          {:error, _} ->
            accumulated_parameters
            |> interpret()
            |> Map.merge(%{result: %{error: :jsonpath_error}})
        end
      else
        if (is_map(value) && R2Map.get(value, :expr) != nil) do
          case RPN.convert(R2Map.get(value, :expr), combined_parameters) do
            value2 ->
              accumulated_parameters
              |> interpret()
              |> Map.merge(%{key => value2})
              |> Map.merge(%{result: :ok})
          end
        else
          accumulated_parameters
          |> interpret()
          |> Map.merge(%{key => value})
          |> Map.merge(%{result: :ok})
        end
      end
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Replace variables, ie __variable__ with the value of the variable
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp interpret(parameter_map) do
    replace_variable_in_map(parameter_map, parameter_map)
  end
  defp replace_variable_in_map(data, variables) when is_map(data) do
    Enum.map(data, fn {k, v} ->
      cond do
        is_binary(v) -> {k, replace_variables(v, variables)}
        true -> {k, replace_variable_in_map(v, variables)}
      end
    end)
    |> Map.new
  end
  defp replace_variable_in_map(data, variables) when is_list(data), do: Enum.map(data, fn x -> replace_variable_in_map(x, variables) end)
  defp replace_variable_in_map(data, variables) when is_binary(data), do: to_number(replace_variables(data, variables))
  defp replace_variable_in_map(data, _), do: data

  defp replace_variables(data, variable_map) do
    pattern = ~r/__(.+?)__/  # Matches variables enclosed in double underscores

    Regex.replace(pattern, data, fn match ->
      variable_name = String.trim(match, "__")
      # If the variable exists, replace it with the value, otherwise, just leave it as it is.
      to_string(R2Map.get(variable_map, variable_name, "__" <> variable_name <> "__"))
    end)
  end

  def to_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ ->
        case Float.parse(value) do
          {number, ""} -> number
          _ -> value
        end
    end
  end
  def to_number(value), do: value
  # -----------------------------------------------------------------------------------------------------------------------------------------
end
