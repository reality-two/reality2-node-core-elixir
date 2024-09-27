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
  alias Reality2.Helpers.Crypto, as: Crypto
  alias :mnesia, as: Mnesia

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link({sentant_name, id, sentant_map}, automation_map) do
    case R2Map.get(automation_map, :name) do
      nil ->
        {:error, :definition}
      automation_name ->
        keys = R2Map.get(sentant_map, "keys", %{})
        GenServer.start_link(__MODULE__, {automation_name, id, sentant_name, automation_map, keys})
        |> R2Process.register(id <> "|automation|" <> automation_name)
    end
  end

  @impl true
  def init({name, id, sentant_name, automation_map, keys}) do
    {:ok, {name, id, sentant_name, automation_map, keys, "start"}}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Synchronous Calls
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def handle_call(:state, _from, {name, id, sentant_name, automation_map, keys, state}) do
    {:reply, {name, state}, {name, id, sentant_name, automation_map, keys, state}}
  end

  def handle_call(_, _, {name, id, sentant_name, automation_map, keys, state}) do
    {:reply, {:error, :unknown_command}, {name, id, sentant_name, automation_map, keys, state}}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Asynchronous Casts
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def handle_cast(args, {name, id, sentant_name, automation_map, keys, state}) do

    parameters = R2Map.get(args, :parameters, %{})
    passthrough = R2Map.get(args, :passthrough, %{})

    # Get the data from the Sentant Database (if there is any)
    data = get_data(id, R2Map.get(keys, "decryption_key"))

    case R2Map.get(args, :event) do
      nil -> {:noreply, {name, id, sentant_name, automation_map, keys, state}}
      event ->
        case R2Map.get(automation_map, "transitions") do
          nil ->
            {:noreply, {name, id, sentant_name, automation_map, keys, state}}
          transitions ->
            new_state =
              Enum.reduce_while(transitions, state,
                fn transition_map, acc_state ->
                  case check_transition(id, sentant_name, transition_map, event, parameters, passthrough, data, keys, acc_state) do
                    {:no_match, the_state} ->
                      {:cont, the_state}
                    {:ok, the_state} ->
                      {:halt, the_state}
                  end
                end
              )
            {:noreply, {name, id, sentant_name, automation_map, keys, new_state}}
        end
    end
  end

  # Used for sending events in the future using Process.send_after
  @impl true
  def handle_info({:send, name_or_id, %{event: event} = details}, {name, id, sentant_name, automation_map, keys, state}) do
    Reality2.Sentants.sendto(name_or_id, details)
    R2Process.deregister(id <> "|timers|" <> event)
    {:noreply, {name, id, sentant_name, automation_map, keys, state}}
  end
  def handle_info(_, {name, id, sentant_name, automation_map, keys, state}) do
    {:noreply, {name, id, sentant_name, automation_map, keys, state}}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get the data from the Data Table in Mnesia
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp get_data(id, decryption_key) do
    do_read = fn id ->
      Mnesia.read({:data, id})
    end

    # Get the data from the Sentant Database (if there is any) and add to the sentant_map
    case Mnesia.transaction(do_read, [id]) do
      {:atomic, [{:data, ^id, stored_data}]} ->
        try do
          data_string = case decryption_key do
            nil -> stored_data
            _ -> Crypto.decrypt(Base.decode64!(stored_data), decryption_key)
          end
          case Jason.decode(data_string) do
            {:ok, data} -> data
            _ -> %{}
          end
        rescue
          _ -> %{}
        end
      _ ->
        %{}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Check the Transition Map to see if it matches the current state and event
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp check_transition(id, sentant_name, transition_map, event, parameters, passthrough, data, keys, state) do
    case R2Map.get(transition_map, :from, "*") do
      "*" -> check_event(id, sentant_name, transition_map, event, parameters, passthrough, data, keys, state)
      ^state -> check_event(id, sentant_name, transition_map, event, parameters, passthrough, data, keys, state)
      _ -> {:no_match, state}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Check the Event Map to see if it matches the current event, and do appropiate actions and state change if it does
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp check_event(id, sentant_name, transition_map, event, parameters, passthrough, data, keys, state) do
    case R2Map.get(transition_map, :event) do
      nil ->
        {:no_match, state}
      ^event ->
        case R2Map.get(transition_map, :to, "*") do
          "*" ->
            do_actions(id, sentant_name, transition_map, parameters, passthrough, keys, data)
            {:ok, state}
          to ->
            do_actions(id, sentant_name, transition_map, parameters, passthrough, keys, data)
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
  defp do_actions(id, sentant_name, transition_map, parameters, passthrough, keys, data) do
    case R2Map.get(transition_map, :actions) do
      nil ->
        parameters # No actions, so result is just the parameters
      actions ->
        # Do each action in turn, accumulating the results
        # Parameters comes in from 'outside' and then accumulates through each action that is done
        # So, the result of do_action becomes the accumulated_parameters to the next action
        Enum.reduce(actions, parameters, fn action_map, accumulated_parameters ->
          do_action(id, sentant_name, action_map, accumulated_parameters, passthrough, keys, data)
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
  defp do_action(id, sentant_name, action_map, accumulated_parameters, passthrough, keys, data) do
    action_parameters = R2Map.get(action_map, :parameters, %{})

    # Both the functions below return a map that becomes the accumulater parameters of the next action
    case R2Map.get(action_map, :plugin) do
      nil ->
        R2Map.get(action_map, :command)
        |> do_inbuilt_action(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)
      plugin ->
        R2Map.get(action_map, :command)
        |> do_plugin_action(plugin, id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Do a Plugin Action
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp do_plugin_action(action, plugin, id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data) do
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
        accumulated_parameters
        |> Map.merge(%{result: %{error: :plugin_error}})
      pid ->
        # Call the plugin on the Sentant, which in turn will call the appropriate internal App or external plugin
        case GenServer.call(pid, %{command: action, parameters: combined_parameters, passthrough: passthrough, data: data, keys: keys, name: sentant_name}) do
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
        IO.puts("Waiting for Plugin: " <> name <> " to start, count is: " <> Integer.to_string(count))
        Process.sleep(100)
        test_and_wait(name, count - 1)
      pid -> pid
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Do an Inbuilt Action
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp do_inbuilt_action(action, id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data) do
    case action do
      "send" -> send(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)
      "debug" -> debug(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)
      "set" -> set(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)
      "signal" -> signal(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)
      "test" -> test(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)
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
  defp send(id, _sentant_name, action_parameters, accumulated_parameters, passthrough, _decryption_key, _data) do

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
  defp signal(id, _sentant_name, action_parameters, accumulated_parameters, passthrough, _decryption_key, _data) do
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
  defp debug(id, _sentant_name, _action_parameters, accumulated_parameters, passthrough, _decryption_key, _data) do
    apply(Reality2Web.SentantResolver, :send_signal, [id, "debug", accumulated_parameters, passthrough])
    # Reality2Web.SentantResolver.send_signal(id, "debug", accumulated_parameters, passthrough)

    accumulated_parameters |> Map.merge(%{result: :ok})
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------




  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Set a key / value in the accumulated parameters
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp set(_id, _sentant_name, action_parameters, accumulated_parameters, _passthrough, _decryption_key, data) do
    override = R2Map.get(action_parameters, :override, false)
    combined_parameters = if (override) do
      Map.merge(accumulated_parameters, action_parameters)
    else
      Map.merge(action_parameters, accumulated_parameters)
    end
    |> interpret()

    IO.puts("SET: #{inspect(combined_parameters)}")

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
          case R2Map.get(value, :expr) do
            expr ->
              if is_map(expr) do
                IO.puts("EXPRESSION : #{inspect(expr)}")
                value3 = Reality2.Calculation.calculate(expr, combined_parameters)
                accumulated_parameters
                |> interpret()
                |> Map.merge(%{key => value3})
                |> Map.merge(%{result: :ok})
              else
                IO.puts("EXPRESSION RPN: #{inspect(expr)}")
                case RPN.convert(expr, combined_parameters) do
                  value2 ->
                    accumulated_parameters
                    |> interpret()
                    |> Map.merge(%{key => value2})
                    |> Map.merge(%{result: :ok})
                end
              end
          end
        else
          if (is_map(value) && R2Map.get(value, :data) != nil) do
            case R2Map.get(data, R2Map.get(value, :data)) do
              nil ->
                accumulated_parameters
                |> interpret()
                |> Map.merge(%{result: %{error: :data_error}})
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
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Test a condition and send an event depending on the outcome
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp test(id, _sentant_name, action_parameters, accumulated_parameters, passthrough, _decryption_key, _data) do
    override = R2Map.get(action_parameters, :override, false)
    combined_parameters = if (override) do
      Map.merge(accumulated_parameters, action_parameters)
    else
      Map.merge(action_parameters, accumulated_parameters)
    end
    |> interpret()

    # Test the condition to choose the event to send
    event = case RPN.convert(R2Map.get(combined_parameters, :if), combined_parameters) do
      true -> R2Map.get(combined_parameters, :then, "event")
      _ -> R2Map.get(combined_parameters, :else, "event")
    end

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
