defmodule Reality2.Automation do
  # ********************************************************************************************************************************************
  @moduledoc false
  # The Automation on a Sentant, managed as a Finite State Machine.
  #
  # Action handlers (send, signal, set, test, debug) are in Reality2.Automation.Actions.
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)
  # ********************************************************************************************************************************************

  @doc false
  use GenServer, restart: :transient
  require Logger
  alias Reality2.Helpers.R2Map, as: R2Map
  alias Reality2.Helpers.R2Process, as: R2Process
  alias Reality2.Helpers.Crypto, as: Crypto
  alias Reality2.Automation.Actions
  alias :mnesia, as: Mnesia

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link({sentant_name, id, sentant_map}, automation_map) do
    case R2Map.get(automation_map, :name) do
      nil ->
        {:error, :definition}

      automation_name ->
        keys = R2Map.get(sentant_map, "keys", %{})

        GenServer.start_link(
          __MODULE__,
          {automation_name, id, sentant_name, automation_map, keys}
        )
        |> R2Process.register(id <> "|automation|" <> automation_name)
    end
  end

  @impl true
  def init({name, id, sentant_name, automation_map, keys}) do
    {:ok, {name, id, sentant_name, automation_map, keys, "start"}}
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Synchronous Calls
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def handle_call(:state, _from, {name, id, sentant_name, automation_map, keys, state}) do
    {:reply, {name, state}, {name, id, sentant_name, automation_map, keys, state}}
  end

  def handle_call(_, _, {name, id, sentant_name, automation_map, keys, state}) do
    {:reply, {:error, :unknown_command}, {name, id, sentant_name, automation_map, keys, state}}
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Asynchronous Casts
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def handle_cast(args, {name, id, sentant_name, automation_map, keys, state}) do
    parameters = R2Map.get(args, :parameters, %{})
    passthrough = R2Map.get(args, :passthrough, %{})
    sender = R2Map.get(args, :sender)

    # Add sender as __sender__ to parameters so it's available for variable interpolation
    # This enables actions to use __sender__ in their parameters
    parameters_with_sender = if sender do
      Map.put(parameters, "__sender__", sender)
    else
      parameters
    end

    # Get the data from the Sentant Database (if there is any), decrypted with TrustGroup key
    data = get_data(id)

    case R2Map.get(args, :event) do
      nil ->
        {:noreply, {name, id, sentant_name, automation_map, keys, state}}

      event ->
        # Debug: log when automation receives __internal events
        if event == "__internal" do
          Logger.info("[Automation:#{sentant_name}] Received __internal event with parameters: #{inspect(parameters)}")
        end

        case R2Map.get(automation_map, "transitions") do
          nil ->
            {:noreply, {name, id, sentant_name, automation_map, keys, state}}

          transitions ->
            new_state =
              Enum.reduce_while(transitions, state, fn transition_map, acc_state ->
                case check_transition(
                       id,
                       sentant_name,
                       transition_map,
                       event,
                       parameters_with_sender,
                       passthrough,
                       data,
                       keys,
                       acc_state
                     ) do
                  {:no_match, the_state} ->
                    {:cont, the_state}

                  {:ok, the_state} ->
                    {:halt, the_state}
                end
              end)

            {:noreply, {name, id, sentant_name, automation_map, keys, new_state}}
        end
    end
  end

  # Used for sending events in the future using Process.send_after
  @impl true
  def handle_info(
        {:send, name_or_id, %{event: event} = details},
        {name, id, sentant_name, automation_map, keys, state}
      ) do
    # Use PNS router for location-transparent routing
    Actions.send_via_wfs(name_or_id, details)
    R2Process.deregister(id <> "|timers|" <> event)
    {:noreply, {name, id, sentant_name, automation_map, keys, state}}
  end

  def handle_info(_, {name, id, sentant_name, automation_map, keys, state}) do
    {:noreply, {name, id, sentant_name, automation_map, keys, state}}
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Get the data from the Data Table in Mnesia (decrypted with TrustGroup key)
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp get_data(id) do
    do_read = fn id ->
      Mnesia.read({:data, id})
    end

    # Get the data from the Sentant Database (if there is any) and add to the sentant_map
    case Mnesia.transaction(do_read, [id]) do
      {:atomic, [{:data, ^id, stored_data}]} ->
        try do
          # Try TrustGroup-based decryption first
          data_string =
            case Base.decode64(stored_data) do
              {:ok, encrypted_data} ->
                case Crypto.decrypt(encrypted_data, "sentant:data:#{id}") do
                  {:ok, decrypted} -> decrypted
                  _ -> stored_data  # Fallback: assume unencrypted
                end

              :error ->
                stored_data  # Not base64 encoded, assume unencrypted
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

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Check the Transition Map to see if it matches the current state and event
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp check_transition(
         id,
         sentant_name,
         transition_map,
         event,
         parameters,
         passthrough,
         data,
         keys,
         state
       ) do
    case R2Map.get(transition_map, :from, "*") do
      "*" ->
        check_event(
          id,
          sentant_name,
          transition_map,
          event,
          parameters,
          passthrough,
          data,
          keys,
          state
        )

      ^state ->
        check_event(
          id,
          sentant_name,
          transition_map,
          event,
          parameters,
          passthrough,
          data,
          keys,
          state
        )

      _ ->
        {:no_match, state}
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Check the Event Map to see if it matches the current event, and do appropiate actions and state change if it does
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp check_event(
         id,
         sentant_name,
         transition_map,
         event,
         parameters,
         passthrough,
         data,
         keys,
         state
       ) do
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

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Do the Actions in the Transition Map when the Transition triggers
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp do_actions(id, sentant_name, transition_map, parameters, passthrough, keys, data) do
    case R2Map.get(transition_map, :actions) do
      nil ->
        # No actions, so result is just the parameters
        parameters

      actions ->
        # Do each action in turn, accumulating the results
        # Parameters comes in from 'outside' and then accumulates through each action that is done
        # So, the result of do_action becomes the accumulated_parameters to the next action
        Enum.reduce(actions, parameters, fn action_map, accumulated_parameters ->
          do_action(id, sentant_name, action_map, accumulated_parameters, passthrough, keys, data)
        end)
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Do a single Action
  # An Action might be like:
  # %{  "command" => "send",
  #     "parameters" =>
  #         %{  "delay" => 1000,
  #             "event" => "turn_on",
  #             "to" => "Light Bulb"
  #         }
  # }
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp do_action(id, sentant_name, action_map, accumulated_parameters, passthrough, keys, data) do
    action_parameters = R2Map.get(action_map, :parameters, %{})

    # Both the functions below return a map that becomes the accumulater parameters of the next action
    case R2Map.get(action_map, :plugin) do
      nil ->
        R2Map.get(action_map, :command)
        |> do_inbuilt_action(
          id,
          sentant_name,
          action_parameters,
          accumulated_parameters,
          passthrough,
          keys,
          data
        )

      plugin ->
        R2Map.get(action_map, :command)
        |> do_plugin_action(
          plugin,
          id,
          sentant_name,
          action_parameters,
          accumulated_parameters,
          passthrough,
          keys,
          data
        )
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Do a Plugin Action
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp do_plugin_action(
         action,
         plugin,
         id,
         sentant_name,
         action_parameters,
         accumulated_parameters,
         passthrough,
         keys,
         data
       ) do
    combined_parameters = Actions.merge_parameters(action_parameters, accumulated_parameters)

    # When the sentant begins, there is a small possibiity that the plugin has not yet started.
    case test_and_wait(id <> "|plugin|" <> plugin, 5) do
      nil ->
        accumulated_parameters
        |> Map.merge(%{result: %{error: :plugin_error}})

      pid ->
        # Call the plugin on the Sentant, which in turn will call the appropriate internal App or external plugin
        case GenServer.call(pid, %{
               command: action,
               parameters: combined_parameters,
               passthrough: passthrough,
               data: data,
               keys: keys,
               name: sentant_name
             }) do
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
        Logger.debug("Waiting for plugin: #{name} to start, count is: #{count}")
        Process.sleep(100)
        test_and_wait(name, count - 1)

      pid ->
        pid
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Do an Inbuilt Action — delegates to Reality2.Automation.Actions
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp do_inbuilt_action(action, id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data) do
    case action do
      "send" ->
        Actions.send_action(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)

      "debug" ->
        Actions.debug_action(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)

      "set" ->
        Actions.set_action(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)

      "signal" ->
        Actions.signal_action(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)

      "test" ->
        Actions.test_action(id, sentant_name, action_parameters, accumulated_parameters, passthrough, keys, data)

      _ ->
        accumulated_parameters |> Map.merge(%{result: :invalid_command})
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Replace variables, ie __variable__ with the value of the variable
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  def interpret(parameter_map) do
    replace_variable_in_map(parameter_map, parameter_map)
  end

  def replace_variable_in_map(data, variables) when is_map(data) do
    Enum.map(data, fn {k, v} ->
      cond do
        is_binary(v) -> {k, replace_variables(v, variables)}
        true -> {k, replace_variable_in_map(v, variables)}
      end
    end)
    |> Map.new()
  end

  def replace_variable_in_map(data, variables) when is_list(data),
    do: Enum.map(data, fn x -> replace_variable_in_map(x, variables) end)

  def replace_variable_in_map(data, variables) when is_binary(data),
    do: to_number(replace_variables(data, variables))

  def replace_variable_in_map(data, _), do: data

  defp replace_variables(data, variable_map) do
    # Matches variables enclosed in double underscores
    pattern = ~r/__(.+?)__/

    Regex.replace(pattern, data, fn match ->
      variable_name = String.trim(match, "__")
      # If the variable exists, replace it with the value, otherwise, just leave it as it is.
      data = R2Map.get(variable_map, variable_name, "__" <> variable_name <> "__")

      cond do
        is_map(data) -> Jason.encode!(data)
        true -> to_string(data)
      end
    end)
  end

  def to_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} ->
        number

      _ ->
        case Float.parse(value) do
          {number, ""} -> number
          _ -> value
        end
    end
  end

  def to_number(value), do: value

  # ---------------------------------------------------------------------------------------------------------------------------------------------
end
