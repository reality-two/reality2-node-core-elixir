defmodule Reality2.Plugin do
# *********************************************************************************************************************************************
@moduledoc false
# The Plugin on a Sentant.
#
# **Author**
# - Dr. Roy C. Davies
# - [roycdavies.github.io](https://roycdavies.github.io/)
# *********************************************************************************************************************************************

    @doc false
    use GenServer, restart: :transient

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Supervisor Callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link({_sentant_name, id, _sentant_map}, plugin_map) do
      case Helpers.Map.get(plugin_map, "name") do
        nil ->
          {:error, :definition}
        plugin_name ->
          GenServer.start_link(__MODULE__, {plugin_name, id, plugin_map}, name: String.to_atom(id <> "|plugin|" <> plugin_name))
      end
    end

    @impl true
    def init({name, id, plugin_map}) do
      # If the plugin is internal, then start it
      init_plugin({name, id})

      {:ok, {name, id, plugin_map, %{}}}
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Public Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Synchronous Calls
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @impl true
    def handle_call(command, _from, {name, id, plugin_map, state}) do

      case Helpers.Map.get(plugin_map, "type") do
        "internal" ->
          # Internal Plugin
          case sendto(id, name, command) do
            {:ok, answer} ->
              {:reply, {:ok, answer}, {name, id, plugin_map, state}}
            :ok ->
              {:reply, {:ok, %{}}, {name, id, plugin_map, state}}
            {:error, error} ->
              {:reply, {:error, error}, {name, id, plugin_map, state}}
          end
        _ ->
          # External Plugin

          # Get the parameters
          parameters = Helpers.Map.get(command, "parameters", %{})

          # Get any passthrough
          passthrough = Helpers.Map.get(command, "passthrough", %{})

          # Get the headers
          headers = plugin_map
          |> Helpers.Map.get("headers", %{})
          |> replace_variable_in_map(parameters)
          |> Map.to_list()

          # Get the body
          body = plugin_map
          |> Helpers.Map.get("body", %{})
          |> replace_variable_in_map(parameters)
          |> Jason.encode!

          # Get the method
          method = Helpers.Map.get(plugin_map, "method", :post)

          # Get the url
          case Helpers.Map.get(plugin_map, "url") do
            nil -> {:reply, {:error, :url}, {name, id, plugin_map, state}}
            url ->
              case Finch.build(method, url, headers, body) |> Finch.request(Reality2.HTTPClient) do
                {:error, reason} -> {:reply, {:error, reason}, {name, id, plugin_map, state}}
                {:ok, result} ->
                  %Finch.Response{body: body} = result
                  body_json = Jason.decode!(body)

                  output = Helpers.Map.get(plugin_map, "output", %{})
                  output_pattern = Helpers.Map.get(output, "value", "")

                  case Helpers.Json.get_value(body_json, output_pattern) do
                    {:error, reason} -> {:reply, {:error, reason}, {name, id, plugin_map, state}}
                    {:ok, answer} ->
                      case Helpers.Map.get(output, "event") do
                        nil -> {:reply, {:ok, answer}, {name, id, plugin_map, state}}
                        event ->
                          # Send the event to the Sentant
                          output_key = Helpers.Map.get(output, "key", "result")
                         Reality2.Sentants.sendto(%{id: id}, %{event: event, parameters: Map.merge(parameters, %{output_key => answer}), passthrough: passthrough})
                      end
                      {:reply, {:ok, %{}}, {name, id, plugin_map, state}}
                  end
              end
          end
      end
    end
    def handle_call(_, _, state) do
      {:reply, {:error, :unknown_command}, state}
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Asynchronous Casts
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @impl true
    # Time to die.
    def handle_cast(:delete, {name, id, plugin_map, state}) do
      delete(id, name)
      {:noreply, {name, id, plugin_map, state}}
    end
    # Time to reinitialise.
    def handle_cast({:reinit, new_plugin_map}, {name, id, _plugin_map, state}) do
      init_plugin({name, id})
      {:noreply, {name, id, new_plugin_map, state}}
    end
    # Time to send a command to the plugin.
    def handle_cast(command, {name, id, plugin_map, state}) do
      case Helpers.Map.get(plugin_map, "type") do
        "internal" ->
          sendto(id, name, command)
        _ ->
          # External Plugin
          :ok
      end
      {:noreply, {name, id, plugin_map, state}}
    end
    # Ignore anything else.
    def handle_cast(_, state), do: {:noreply, state}
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Used for sending events in the future using Process.send_after
    @impl true
    def handle_info(command, {name, id, plugin_map, state}) do
      handle_cast(command, {name, id, plugin_map, state})
    end
    def handle_info(_, state), do: {:noreply, state}
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Terminate the instance of the Plugin in the App
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp delete(id, name) do

      app_name_atom = app_name_underscore_atom(name)

      # Check that there is an App with the name of the plugin
      case Enum.any?(Application.loaded_applications(), fn({app_name, _, _}) -> app_name == app_name_atom end) do
        true ->
          # Run the 'delete' function in the App referenced to by the plugin name, in the module named Main
          # This should be defined to delete the plugin.
          name
          |> app_main_module
          |> apply(:delete, [id])
        false ->
          {:error, :not_found}
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Helper Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # Return a module name for the App name, Main module,  with '.' removed and each section capitalised
    defp app_main_module(name) do
      name
      |> String.split(".")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")
      |> Module.concat(String.to_atom("Main"))
    end

    # Return an atom for the App name with '.' replaced by '_' and lower case
    defp app_name_underscore_atom(name) do
      name
      |> String.split(".")
      |> Enum.join("_")
      |> String.downcase
      |> String.to_atom
    end

    # if the plugin is internal, then create its instance in the App
    defp init_plugin({name, id}) do

      # In the definition file, the plugins have '.' between sections of the name, but in the code, we use '_' between sections
      app_name_atom = app_name_underscore_atom(name)

      # Check that there is an App with the name of the plugin
      case Enum.any?(Application.loaded_applications(), fn({app_name, _, _}) -> app_name == app_name_atom end) do
        true ->
          # Run the 'create' function in the App referenced to by the plugin name, in the module named Main
          # This should be defined to set up the plugin.  Each Sentant will get its own instance of the plugin.
          name
          |> app_main_module
          |> apply(:create, [id])
        false ->
          # Strictly speaking, not OK, but we don't want to stop the Sentant from starting.
          :ok
      end
    end

    # Send a command to the plugin
    def sendto(sentant_id, plugin_name, command_and_parameters) do
      try do
        plugin_name
        |> String.split(".")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join("")
        |> Module.safe_concat(String.to_atom("Main"))
        |> case do
          nil -> {:error, :plugin}
          module_name -> apply(module_name, :sendto, [sentant_id, command_and_parameters])
        end
      rescue _ ->
        {:error, :plugin}
      end
    end

    # Find places where a string contains a variable (starts with __ and ends with __), and replace it with the value from the variables map
    defp replace_variable_in_map(data, variables) when is_map(data) do
      Enum.map(data, fn {k, v} ->
        cond do
          is_binary(v) -> {k, replace_string(variables, v)}
          true -> {k, replace_variable_in_map(v, variables)}
        end
      end)
      |> Map.new
    end
    defp replace_variable_in_map(data, variables) when is_list(data), do: Enum.map(data, fn x -> replace_variable_in_map(x, variables) end)
    defp replace_variable_in_map(data, variables) when is_binary(data), do: replace_string(variables, data)
    defp replace_variable_in_map(data, _), do: data

    defp replace_string(map, string) do
      case Regex.named_captures(~r/^__(?<content>.+?)__$/, string) do
        %{"content" => content} ->
          Helpers.Map.get(map, content, string)
        _ -> string
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------
  end
