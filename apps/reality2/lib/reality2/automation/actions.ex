defmodule Reality2.Automation.Actions do
  # ********************************************************************************************************************************************
  @moduledoc false
  # Action handlers for Sentant automations (send, signal, set, test, debug).
  #
  # Extracted from Reality2.Automation to keep the GenServer module focused on
  # state machine transitions and lifecycle.
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)
  # ********************************************************************************************************************************************

  require Logger
  alias Reality2.Helpers.R2Map, as: R2Map
  alias Reality2.Helpers.JsonPath, as: JsonPath
  alias Reality2.Helpers.R2Process, as: R2Process

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Shared Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc false
  # Merge action_parameters with accumulated_parameters respecting the override flag, then interpret variables
  def merge_parameters(action_parameters, accumulated_parameters) do
    override = R2Map.get(action_parameters, :override, false)

    if override do
      Map.merge(accumulated_parameters, action_parameters)
    else
      Map.merge(action_parameters, accumulated_parameters)
    end
    |> Reality2.Automation.interpret()
  end

  # Resolve the 'to' field into a list of targets, handling @sender, "*", "*|name", "node|name", lists, etc.
  defp resolve_to_list(to_field, id, original_sender) do
    case to_field do
      nil -> [id]
      "@sender" -> [resolve_sender_path(original_sender)]
      str when is_binary(str) -> [str]
      list when is_list(list) ->
        Enum.map(list, fn
          "@sender" -> resolve_sender_path(original_sender)
          other -> other
        end)
      other -> [other]
    end
    |> Enum.reject(&is_nil/1)
  end

  # Resolve a target to a WFS-compatible identifier
  defp resolve_target(to) do
    cond do
      is_binary(to) and (String.contains?(to, "|") or to == "*") ->
        to
      is_binary(to) ->
        case Reality2.Metadata.get(:SentantIDs, to) do
          nil -> %{id: to}
          found_id -> %{id: found_id}
        end
      true ->
        to
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Send
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def send_action(
        id,
        sentant_name,
        action_parameters,
        accumulated_parameters,
        passthrough,
        _decryption_key,
        _data
      ) do
    combined_parameters = merge_parameters(action_parameters, accumulated_parameters)

    original_sender = R2Map.get(combined_parameters, "__sender__")

    # Build sender info for this Sentant (the one sending the event now)
    # This allows the recipient to reply back using @sender
    this_sender = %{
      sentant_id: id,
      sentant_name: sentant_name,
      node_id: Reality2.Bootstrap.get(:node_id),
      node_name: Reality2.Bootstrap.get(:node_name)
    }

    to_list = resolve_to_list(R2Map.get(combined_parameters, :to), id, original_sender)

    # Go through the list, sending the event to each one.
    for to <- to_list do
      name_or_id = resolve_target(to)

      # Get the event to send.
      event = R2Map.get(combined_parameters, :event, "event")
      event_parameters = R2Map.get(action_parameters, :parameters, %{})

      # Make sure there is no timer for this event already in process.  If so, cancel it before doing the new one.
      case R2Process.whereis(id <> "|timers|" <> event) do
        nil ->
          :ok

        timer ->
          Process.cancel_timer(timer)
          R2Process.deregister(id <> "|timers|" <> event)
      end

      # Clean parameters - remove __sender__ as it's passed separately
      clean_params = Map.merge(event_parameters, accumulated_parameters)
        |> Reality2.Automation.interpret()
        |> Map.delete("__sender__")
        |> Map.delete(:__sender__)

      # Send the event either immediately or after a delay.
      case R2Map.get(combined_parameters, :delay) do
        nil ->
          # Use WFS router for location-transparent routing (local or remote)
          send_via_wfs(name_or_id, %{
            event: event,
            parameters: clean_params,
            passthrough: passthrough,
            sender: this_sender
          })

        delay ->
          timer =
            Process.send_after(
              self(),
              {:send, name_or_id,
               %{
                 event: event,
                 parameters: clean_params,
                 passthrough: passthrough,
                 sender: this_sender
               }},
              delay
            )

          R2Process.register(id <> "|timers|" <> event, timer)
      end
    end

    # No side effects, so just return the parameters sent in
    accumulated_parameters |> Map.merge(%{result: :ok})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Send a signal on the Sentant's subscription channel
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def signal_action(
        id,
        _sentant_name,
        action_parameters,
        accumulated_parameters,
        passthrough,
        _decryption_key,
        _data
      ) do
    combined_parameters = merge_parameters(action_parameters, accumulated_parameters)

    # Get sender info for passing through to signal subscribers
    sender = R2Map.get(combined_parameters, "__sender__")

    # Send off a signal to any listening device
    case R2Map.get(combined_parameters, :event) do
      nil ->
        Logger.debug("[Automation] Signal action: no event in parameters")
        nil

      event ->
        case R2Process.whereis(id <> "|comms") do
          nil ->
            Logger.debug("[Automation] Signal action: comms process not found for #{id}")
            nil

          _pid ->
            event_parameters = R2Map.get(action_parameters, :parameters, %{})
            merged_params = Map.merge(event_parameters, accumulated_parameters) |> Reality2.Automation.interpret()
            # Remove __sender__ from params (it's passed separately)
            clean_params = Map.delete(merged_params, "__sender__")

            Logger.info("[Automation] Broadcasting signal '#{event}' with params: #{inspect(Map.keys(clean_params))}")

            Reality2.Signals.broadcast(
              id,
              event,
              clean_params,
              passthrough,
              sender
            )
        end
    end

    # No side effects, so just return the parameters sent in
    accumulated_parameters |> Map.merge(%{result: :ok})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Send debug info to the debug channel
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def debug_action(
        id,
        _sentant_name,
        _action_parameters,
        accumulated_parameters,
        passthrough,
        _decryption_key,
        _data
      ) do
    Reality2.Signals.broadcast(id, "debug", accumulated_parameters, passthrough)

    accumulated_parameters |> Map.merge(%{result: :ok})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Set a key / value in the accumulated parameters
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def set_action(
        _id,
        _sentant_name,
        action_parameters,
        accumulated_parameters,
        _passthrough,
        _decryption_key,
        data
      ) do
    combined_parameters = merge_parameters(action_parameters, accumulated_parameters)

    key = R2Map.get(combined_parameters, :key)

    # Get the value, and then process it to replace
    value = Reality2.Automation.replace_variable_in_map(R2Map.get(combined_parameters, :value), combined_parameters)

    cond do
      value == nil ->
        accumulated_parameters
        |> Reality2.Automation.interpret()
        |> R2Map.delete(key)
        |> Map.merge(%{result: :ok})

      is_map(value) && R2Map.get(value, :jsonpath) != nil ->
        %{"json_path" => jsonpath} =
          Reality2.Automation.replace_variable_in_map(
            %{"json_path" => R2Map.get(value, :jsonpath)},
            accumulated_parameters
          )

        case JsonPath.get_value(combined_parameters, jsonpath) do
          {:ok, value2} ->
            accumulated_parameters
            |> Reality2.Automation.interpret()
            |> Map.merge(%{key => value2})
            |> Map.merge(%{result: :ok})

          {:error, _} ->
            accumulated_parameters
            |> Reality2.Automation.interpret()
            |> Map.merge(%{result: %{error: :jsonpath_error}})
        end

      is_map(value) && R2Map.get(value, :expr) != nil ->
        expr = R2Map.get(value, :expr)

        result_value = if is_map(expr) do
          Reality2.Calculation.calculate(expr, combined_parameters)
        else
          RPN.convert(expr, combined_parameters)
        end

        accumulated_parameters
        |> Reality2.Automation.interpret()
        |> Map.merge(%{key => result_value})
        |> Map.merge(%{result: :ok})

      is_map(value) && R2Map.get(value, :data) != nil ->
        case R2Map.get(data, R2Map.get(value, :data)) do
          nil ->
            accumulated_parameters
            |> Reality2.Automation.interpret()
            |> Map.merge(%{result: %{error: :data_error}})

          value2 ->
            accumulated_parameters
            |> Reality2.Automation.interpret()
            |> Map.merge(%{key => value2})
            |> Map.merge(%{result: :ok})
        end

      true ->
        accumulated_parameters
        |> Reality2.Automation.interpret()
        |> Map.merge(%{key => value})
        |> Map.merge(%{result: :ok})
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Test a condition and send an event depending on the outcome
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def test_action(
        id,
        sentant_name,
        action_parameters,
        accumulated_parameters,
        passthrough,
        _decryption_key,
        _data
      ) do
    combined_parameters = merge_parameters(action_parameters, accumulated_parameters)

    test_expr = R2Map.get(combined_parameters, :if)

    result =
      if is_map(test_expr) do
        Reality2.Calculation.calculate(test_expr, combined_parameters)
      else
        RPN.convert(test_expr, combined_parameters)
      end

    # Test the condition to choose the event to send
    event =
      case result do
        true -> R2Map.get(combined_parameters, :then, "event")
        _ -> R2Map.get(combined_parameters, :else, "event")
      end

    original_sender = R2Map.get(combined_parameters, "__sender__")

    this_sender = %{
      sentant_id: id,
      sentant_name: sentant_name,
      node_id: Reality2.Bootstrap.get(:node_id),
      node_name: Reality2.Bootstrap.get(:node_name)
    }

    to_list = resolve_to_list(R2Map.get(combined_parameters, :to), id, original_sender)

    for to <- to_list do
      name_or_id = resolve_target(to)
      event_parameters = R2Map.get(action_parameters, :parameters, %{})

      clean_params = Map.merge(event_parameters, accumulated_parameters)
        |> Reality2.Automation.interpret()
        |> Map.delete("__sender__")
        |> Map.delete(:__sender__)

      send_via_wfs(name_or_id, %{
        event: event,
        parameters: clean_params,
        passthrough: passthrough,
        sender: this_sender
      })
    end

    accumulated_parameters |> Map.merge(%{result: :ok})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # WFS Router
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Helper function to send via WFS router with fallback to direct send
  @doc false
  def send_via_wfs(name_or_id, message_map) do
    # Try to use WFS router if available
    if Code.ensure_loaded?(AiReality2Wfs.Router) do
      # Extract identifier for WFS Router
      identifier = case name_or_id do
        %{id: id} -> id
        %{name: name} -> Reality2.Metadata.get(:SentantIDs, name) || name
        str when is_binary(str) -> str  # Pass path formats directly ("*", "*|name", "node|name")
      end

      # Suppress compile-time warning - WFS is an optional plugin
      router_module = AiReality2Wfs.Router
      sender = Map.get(message_map, :sender)
      case apply(router_module, :send_to_sentant, [
        identifier,
        message_map.event,
        message_map.parameters,
        message_map.passthrough,
        sender
      ]) do
        # Single target results
        {:ok, :local, _result} -> :ok
        {:ok, {:remote, _node_id}, _result} -> :ok
        # Broadcast results (for "*" and "*|name" formats)
        {:ok, %{local: _, remote: _}} -> :ok
        # Errors
        {:error, :not_found, _} ->
          # Fallback to direct send (only works for local targets)
          if is_map(name_or_id) do
            Reality2.Sentants.sendto(name_or_id, message_map)
          else
            Logger.warning("WFS routing failed: not_found for #{inspect(name_or_id)}")
          end
        {:error, :not_found} ->
          Logger.warning("WFS routing failed: not_found for #{inspect(name_or_id)}")
        {:error, reason} ->
          Logger.warning("WFS routing failed: #{inspect(reason)}")
      end
    else
      # WFS not available, use direct send (only works for local targets)
      if is_map(name_or_id) do
        Reality2.Sentants.sendto(name_or_id, message_map)
      else
        Logger.warning("WFS not available, cannot route #{inspect(name_or_id)}")
      end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Sender Resolution
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Resolve @sender to a WFS-compatible path
  # Returns "node_name|sentant_name" or "node_name" if no sentant specified
  @doc false
  def resolve_sender_path(nil) do
    Logger.warning("[Automation] @sender used but no sender info available in message")
    nil
  end

  def resolve_sender_path(sender) when is_map(sender) do
    node_name = Map.get(sender, :node_name) || Map.get(sender, "node_name")
    sentant_name = Map.get(sender, :sentant_name) || Map.get(sender, "sentant_name")
    sentant_id = Map.get(sender, :sentant_id) || Map.get(sender, "sentant_id")

    cond do
      # Prefer sentant_name for addressing (names are stable, UUIDs change on reload)
      sentant_name && node_name ->
        "#{node_name}|#{sentant_name}"

      # Fall back to sentant_id if no name
      sentant_id && node_name ->
        "#{node_name}|#{sentant_id}"

      # No sentant specified - just the node (for node-level events)
      node_name ->
        node_name

      true ->
        Logger.warning("[Automation] @sender has incomplete info: #{inspect(sender)}")
        nil
    end
  end

  def resolve_sender_path(other) do
    Logger.warning("[Automation] @sender has unexpected format: #{inspect(other)}")
    nil
  end
end
