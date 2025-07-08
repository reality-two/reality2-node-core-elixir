defmodule Reality2.Sentants do
# *******************************************************************************************************************************************
@moduledoc """
  Module for creating and managing Sentants, and the DynamicSupervisor that manages them.

  When a Sentant is created, it is given a unique ID, and a name.  The name is unique on the node, but not in the world.
  Upon creation, the Sentant is sent the init event, which is handled by the Sentant's Automations.

  If a Sentant with the same name or ID already exists on the Node, then it is not created again, but redefined and restarted.

  Sentants are immutable, so they cannot be changed once created.  To change a Sentant, it must be reloaded.
  However, some data in plugins may change (such as `Reality2.AiReality2Vars`), and this is handled by the plugin itself.
  Further, the state(s) of the Sentant Automations can change.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
"""
# *******************************************************************************************************************************************
  @doc false
  use DynamicSupervisor
  alias Reality2.Types
  alias Reality2.Helpers.R2Process, as: R2Process
  alias Reality2.Helpers.R2Map, as: R2Map

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc false
  def start_child(init_arg) do
    DynamicSupervisor.start_child(__MODULE__, child_spec(init_arg))
  end

  @impl true
  def init(init_arg) do
    DynamicSupervisor.init( strategy: :one_for_one, extra_arguments: [init_arg] )
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Types
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @typedoc """
  Each Sentant can be referred to by either its name or its ID.  The name of a Sentant is unique on the node, but not in the world.
  This is used in pathing.
  """
  @type sentant_name_or_uuid :: %{:id => Types.uuid()} | %{:name => String.t()}

  @typedoc """
  The definition of a Sentant is a string containing the definition of the Sentant in YAML format.  See the definition of `YAML.Sentant`.
  """
  @opaque sentant_definition :: String.t()
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec create((definition :: sentant_definition()) | (definition_map :: Types.sentant()) | String.t()) ::
    {:ok, String.t()}
    | {:error, :definition}
  @doc """
  Create a new Sentant and return the result of the operation with the pid of the new Sentant, or an appropriate error.

  **Parameters**
  - `definition` - A string containing the definition of the Sentant to be created in YAML format.
  - (or) 'definition_map' - A map as created from a YAML, TOML or JSON definition.

  **Returns**
  - `{:ok, id}` - The Sentant was created.
  - `{:error, :definition}` if the definition is invalid.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def create(sentant_definition) do
    case convert_input(sentant_definition) do
      {:ok, definition_map} ->
        sentant_map = remove_sentant_parent_from_definition_map(definition_map)
        case Reality2.Types.validate(sentant_map, Reality2.Types.sentant()) do
          :ok ->
            create_from_map(add_defaults(sentant_map))
          {:error, error} ->
            {:error, error}
        end
      _ ->
        {:error, :definition}
    end
  end

  defp create_from_map(sentant_map) do
    case sentant_name(sentant_map) do
      {:ok, name} ->
        case sentant_id(sentant_map) do
          {:ok, _, id} ->
            case Reality2.Metadata.get(:SentantIDs, name) do
              nil ->
                case DynamicSupervisor.start_child(
                  {:via, PartitionSupervisor, {Reality2.Sentants, choose_supervisor()}},
                  {Reality2.Sentant, {name, id, sentant_map}}
                ) do
                    {:ok, _pid} ->
                      Reality2.Metadata.set :SentantNames, id, name
                      Reality2.Metadata.set :SentantIDs, name, id

                      add_plugins_to_sentant(id, sentant_map)
                      add_automations_to_sentant(id, sentant_map)

                      sendto_all(%{event: "__internal", parameters: %{id: id, name: name, activity: "created"}})
                      {:ok, id}
                    error -> error
                end
              existing_id ->
                # Remove automations from Sentant
                terminate_all_children(R2Process.pid(existing_id <> "|automations"))
                # Remove plugins from Sentant
                remove_plugins_from_sentant(existing_id)

                # Add the updated automations and plugins to the Sentant
                add_plugins_to_sentant(existing_id, sentant_map)
                add_automations_to_sentant(existing_id, sentant_map)

                sendto_all(%{event: "__internal", parameters: %{id: id, name: name, activity: "created"}})
                {:ok, existing_id}
            end
          error -> error
        end
      error -> error
    end
  end

  defp add_automations_to_sentant(id, sentant_map) do
    case R2Map.get(sentant_map, "automations") do
      nil ->
        :ok
      automations ->
        case is_list(automations) do
          true ->
            Enum.each(automations, fn automation_map -> Reality2.Automations.create(id, automation_map) end)
          false ->
            :ok
        end
    end
  end

  defp add_plugins_to_sentant(id, sentant_map) do
    # Add the default plugins
    case System.get_env("PLUGINS") do
      nil -> []
      value ->
        String.split(value, ",")
        |> Enum.map(&String.trim/1)
    end
    |> Enum.each(fn plugin -> Reality2.Plugins.create(id, %{"name" => plugin, "type" => "internal"}) end)

    case R2Map.get(sentant_map, "plugins") do
      nil ->
        :ok
      plugins ->
        case is_list(plugins) do
          true ->
            Enum.each(plugins, fn plugin_map -> Reality2.Plugins.create(id, plugin_map) end)
          false ->
            :ok
        end
    end
  end

  defp terminate_all_children(supervisor) do
    children = DynamicSupervisor.which_children(supervisor)

    Enum.each(children, fn {_, child_pid, _, _} ->
      DynamicSupervisor.terminate_child(supervisor, child_pid)
    end)
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec read(name_or_uuid :: sentant_name_or_uuid(), command :: :state | :definition) ::
    {:ok, map()}
    | {:error, :name}
    | {:error, :existance}
    | {:error, :id}
  @doc """
  Read something from an existing Sentant - determined by the command.  The result will depend on the command.

  - Parameters
    - `name_or_uuid` - The name or ID of the Sentant to be read from as a map containing either a `:name` or `:id` key.
    - `command` - The command to be executed on the Sentant, which must be either `:state` or `:definition`.

  - Returns
    - `{:ok, definition}` - The Sentant was read.
    - `{:error, :existance}` if the Sentant with that ID or name does not exist on this node.
    - `{:error, :invalid}` if the parameter is invalid.

  - Example
  ```elixir
  case Reality2.Sentants.read(%{:name => "my_sentant"}, :definition) do
    {:ok, definition} ->
      # Do something with the definition
    {:error, :existance} ->
      # Sentant does not exist
    {:error, :invalid} ->
      # Invalid parameter
  end

  Reality2.Sentants.read(%{id: "123e4567-e89b-12d3-a456-426614174000"}, :state)
  ```
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def read(name_or_uuid, command)
  def read(%{:name => name}, command) do
    case Reality2.Metadata.get :SentantIDs, name do
      nil ->
        {:error, :name}
      uuid ->
        read(%{:id => uuid}, command)
    end
  end

  def read(%{:id => uuid}, command) do
    case wait_until_alive(uuid <> "|comms", 10) do
      {:error} ->
        {:error, :id}
      {:ok, pid} ->
        result = GenServer.call(pid, command)
        {:ok, result}
    end
  end

  def read(_, _), do: {:error, :existance}
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec read_all(command :: :state | :definition) ::
    {:ok, list()}
  @doc """
  Read something from all Sentants - determined by the command.  The result will depend on the command.

  - Parameters
    - `command` - The command to be executed on each Sentant, which must be either `:state` or `:definition`.

  - Returns
    - `{:ok, list}` - The Sentant was read, and the list contains the responses.

  - Example
  ```elixir
  case Reality2.Sentants.read_all(:definition) do
    {:ok, list} ->
      # Do something with the list
    {:error, :invalid} ->
      # Invalid parameter
  end
  ```
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def read_all(command) do
    {:ok, get_all_sentant_comms() |> Enum.map( fn (pid) -> GenServer.call(pid, command) end )}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec delete(name_or_uuid :: sentant_name_or_uuid()) ::
    {:ok, Types.uuid()}
    | {:error, :name}
    | {:error, :existance}
    | {:error, :id}
  @doc """
  Delete a Sentant and return the result of the operation with the pid of the deleted Sentant, or an appropriate error.

  - Parameters
    - `name_or_uuid` - The name or ID of the Sentant to be deleted as a map containing either a `:name` or `:id` key.

  - Returns
    - `{:ok, id}` - The Sentant was deleted.
    - `{:error, :name}` if the Sentant with that name does not exist on this node.
    - `{:error, :id}` if the Sentant with that ID does not exist on this node.
    - `{:error, :existance}` if the Sentant with that ID or name does not exist on this node.

  - Example
  ```elixir
  Reality2.Sentants.delete(%{:name => "my_sentant"})
  ```
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def delete(name_or_uuid)
  def delete(%{:name => name}) do
    case Reality2.Metadata.get(:SentantIDs, name) do
      nil ->
        {:error, :name}
      id ->
        delete(%{:id => id})
    end
  end

  def delete(%{:id => id}) do
    case R2Process.whereis(id) do
      nil ->
        {:error, :id}
      pid ->
        # Remove the Apps associated with plugins from the Sentant
        remove_plugins_from_sentant(id)
        # TODO: Close any websockets for this Sentant

        # Remove the Sentant processes.  Potentially, if this fails, the sentant could be left running, but with no plugin processes in the Apps.
        case Supervisor.stop(pid, :shutdown) do
          :ok ->
            case Reality2.Metadata.get(:SentantNames, id) do
              nil ->
                {:error, :existance}
              name ->
                Reality2.Metadata.delete(:SentantNames, id)
                Reality2.Metadata.delete(:SentantIDs, name)
                sendto_all(%{event: "__internal", parameters: %{id: id, name: name, activity: "deleted"}})
                {:ok, id}
            end
        end
      end
  end

  def delete(_), do: {:error, :existance}


  defp remove_plugins_from_sentant(id) do
    # Get the children of the plugins supervisor

    R2Process.pid(id <> "|plugins")
    |> Supervisor.which_children()
    |> Enum.map( fn {_, pid_or_restarting, _, _} ->
      # Send the message to each child
      case pid_or_restarting do
        :restarting ->
          # Ignore
          :ok
        pid ->
          GenServer.call(pid, :delete)
      end
    end)
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec sendto(name_or_uuid :: sentant_name_or_uuid(), message :: map()) ::
    {:ok}
    | {:error, :name}
    | {:error, :existance}
    | {:error, :id}
  @doc """
  Send a message to the named Sentant if it exists and return the result of the operation, or an appropriate error. This is an asynchronous operation.

  - Parameters
    - `name_or_uuid` - The name or ID of the Sentant to have the message sent to as a map containing either a `:name` or `:id` key.
    - `message` - The message to be sent, which must contain a `:command` string and optionally a `:parameters` map, and a `:passthrough` map.

  - Returns
    - `{:ok}` - The message was sent.
    - `{:error, :name}` if the Sentant with that name does not exist on this node.
    - `{:error, :id}` if the Sentant with that ID does not exist on this node.
    - `{:error, :existance}` if the Sentant with that ID or name does not exist on this node.

  - Example
  ```elixir
  Reality2.Sentants.sendto(%{:name => "my_sentant"}, %{event: "turn_on", delay: 1000})
  ```
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def sendto(name_or_uuid, message_map)
  def sendto(%{:name => name}, message_map) do
    case Reality2.Metadata.get(:SentantIDs, name) do
      nil ->
        {:error, :name}
      id ->
        sendto(%{:id => id}, message_map)
    end
  end

  def sendto(%{:id => id}, message_map) do
    case wait_until_alive(id <> "|comms", 10) do
      {:error} ->
        {:error, :id}
      {:ok, pid} ->
        GenServer.cast(pid, message_map)
        {:ok, pid}
    end
  end

  def sendto(_, _), do: {:error, :existance}
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec sendto_all(message :: map()) ::
    {:ok, integer()}
  @doc """
  Send a message to all Sentants.  This is an asynchronous operation, so the result is always `{:ok, num_sentants}`.

  - Parameters
    - `message` - The message to be sent, which must contain a `:command` string and optionally a `:parameters` map, and a `:passthrough` map.

  - Returns
    - `{:ok, num_sentants}` - The number of Sentants that the message was sent to.

  - Example
  ```elixir
  Reality2.Sentants.sendto_all(%{event: "turn_on"})
  ```
  """
  def sendto_all(message_map) do
    sentants = get_all_sentant_comms()
    Enum.each(sentants, fn pid -> GenServer.cast(pid, message_map) end)

    {:ok, length(sentants)}
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Returns the supervisor index of the Supervisor with the fewest child processes.
  defp choose_supervisor() do
    Reality2.Sentants
    |> PartitionSupervisor.which_children
    |> count_processes
    |> choose_minimum
  end


  # Returns a list of tuples containing the Supervisor index and the number of child processes on that Supervisor.
  defp count_processes([]), do: []
  defp count_processes([{id, pid, _, _} | tail]) do
    %{active: num_children} = DynamicSupervisor.count_children(pid)
    [{id, num_children} | count_processes(tail)]
  end


  # Returns the index of the Supervisor with the fewest child processes.
  defp choose_minimum([]), do: 0
  defp choose_minimum(list), do: Enum.min_by(list, &elem(&1, 1)) |> elem(0)


  # Get the ID of the Sentant from the definition map.
  # Can accept either a string or an atom as the ID, and either with the 'sentant' key or not.
  # Each Sentant has a unique UUID.  This is checked to ensure that the Sentant is unique in the world, and it's running status is set accordingly to
  # either `:main` or `:shadow`.  If the UUID is not checked (for example, if the node is offline), then it is set to `:unchecked`.
  defp sentant_id(%{"id" => id}), do: sentant_id(%{id: id})
  defp sentant_id(%{id: id}) do
    # TODO: Check that the Sentant identified by the ID is unique in the world and if not, detemine which should be the main and which shadows.
    # Should return either that the sentant is the main one, a shadow one, or that it is unchecked.
    case UUID.info(id) do
      {:ok, _} ->
        {:ok, :unchecked, id}
      _ ->
        {:error, :id}
    end
  end
  defp sentant_id(_), do: {:ok, :main, UUID.uuid1} # No ID given, so assume a new Sentant is to be created with a new ID.


  # Get the name of the Sentant from the definition map.
  # Can accept either a string or an atom as the name, and either with the 'sentant' key or not.
  defp sentant_name(%{"name" => name}), do: {:ok, name}
  defp sentant_name(%{name: name}), do: {:ok, name}
  defp sentant_name(_), do: {:error, :definition}


  # Returns a list of all the children of the PartitionSupervisor's children.
  defp get_all_sentant_comms do
    Reality2.Metadata.all(:SentantIDs)
    |> Enum.map(fn {_, id} -> R2Process.whereis(id <> "|comms") end)
    |> Enum.filter(&(&1 != nil))
  end

  # Returns a sentant definition map with the sentant parent removed if present.
  defp remove_sentant_parent_from_definition_map(%{"sentant" => sentant_map}), do: sentant_map
  defp remove_sentant_parent_from_definition_map(%{sentant: sentant_map}), do: sentant_map
  defp remove_sentant_parent_from_definition_map(sentant_map), do: sentant_map

  defp add_defaults(definition_map) do
    definition_map
    |> Map.put_new("description", "")
    |> Map.put_new("version", "0.1.0")
    |> Map.put_new("author", %{"id" => "_", "name" => "_", "email" => "_"}) # Will be changed when we actually have users
    |> Map.put_new("class", "ai.reality2.default")
    |> Map.put_new("data", %{})
    |> Map.put_new("binary", %{})
    |> Map.put_new("keywords", [])
    |> Map.put_new("tags", [])
    |> Map.put_new("plugins", [])
    |> Map.put_new("automations", [])
    |> Map.put_new("states", [])
    |> Map.put_new("status", "unchecked")
  end

  # Convert an input String in either JSON, TOML or YAML format to a map.
  defp convert_input(definition) when is_map(definition), do: {:ok, definition}
  defp convert_input(definition) when is_binary(definition) do
    try do
      case Jason.decode(definition) do
        {:ok, definition_map} ->
          {:ok, definition_map}
        _ ->
          case YamlElixir.read_from_string(definition) do
            {:ok, definition_map} ->
              {:ok, definition_map}
            _ -> case Toml.decode(definition) do
              {:ok, definition_map} ->
                {:ok, definition_map}
              _ -> {:error, :definition}
            end
          end
      end
    rescue
      _ -> {:error, :definition}
    end
  end
  defp convert_input(_), do: {:error, :definition}

  # Wait until the process is alive (and return the pid), or until the count is zero (in which case return an error)
  # This is used to wait for the Sentant processes to be created before sending a message to it.
  defp wait_until_alive(_, 0) do
    {:error}
  end
  defp wait_until_alive(name, count) do
    case R2Process.whereis(name) do
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          Process.sleep(100)
          wait_until_alive(name, count - 1)
        end
      _ ->
        Process.sleep(100)
        wait_until_alive(name, count - 1)
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------
end
