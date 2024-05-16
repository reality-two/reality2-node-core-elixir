defmodule AiReality2Geospatial.Main do
# *******************************************************************************************************************************************
@moduledoc """
  Module for managing the main supervisor tree for the `AiReality2Geospatial` App.

  In this instance, the main supervisor is a DynamicSupervisor, which is used to manage the Geospatial interelationships between Sentants.
  Implementation of this is using octatrees and geohashes.

  In order to minimise side effects of a geospatial search crashing and wiping out the entire octatree, the octatree is managed by a GenServer
  with each Sentant having its own GenServer process.  This means that if one Sentant plugin crashes, it does not affect the others.
  This means that the locations are in essence stored in memory, not on disk, so if keeping location between restarts is important, then
  a storage plugin will be required as well.

  Use this as a template for your own Main module for your own Apps.  The `create`, `delete`, `sendto` and `whereas` functions must be implemented.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
"""
# *******************************************************************************************************************************************
  @doc false
  use DynamicSupervisor, restart: :transient

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end


  @impl true
  def init(init_arg) do
    DynamicSupervisor.init( strategy: :one_for_one, extra_arguments: [init_arg] )
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec create(String.t(), %{}) ::
    {:ok}
    | {:error, :existance}

  @doc """
  Create a new Geospatial location for this Sentant, returning {:ok} or an appropriate error.

  This creates a new entry into the geospatial database.  Each Sentant gets a Geospatial data store, with the idea that in the future, this
  might be expanded to do more than just store one location.  Each Sentant could store a whole GIS database, for example.

  - Parameters
    - `id` - The id of the Sentant for which the Geospatial Plugin is being created.
    - `location` - A map containing the location of the Sentant expressed as %{"latitude" => 0.0, "longitude" => 0.0, "altitude" => 0.0},
                   or alternatively, a geohash string and an altitude for example %{"geohash" => "u4pruydqqvj", "altitude" => 0.0}
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def create(sentant_id, location \\ %{}) do
    name = sentant_id <> "|" <> app_name()
    case Process.whereis(String.to_atom(name)) do
      nil->
        case DynamicSupervisor.start_child(__MODULE__, AiReality2Geospatial.Data.child_spec(String.to_atom(name))) do
          {:ok, pid} ->
            GenServer.call(pid, %{command: "set", parameters: location})
            {:ok}
          error -> error
        end
      pid ->
        # Clear the data store so there is no old data that hackers might be able to access in the case this was a reused ID
        GenServer.call(pid, %{command: "clear"})
        GenServer.call(pid, %{command: "set", parameters: location})
        {:ok}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec delete(String.t()) ::
    {:ok}
    | {:error, :existance}

  @doc """
  Delete a Geospatial Entry, returning {:ok} or an appropriate error.

  - Parameters
    - `id` - The id of the Sentant for which the Geospatial Entry is being deleted.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def delete(sentant_id) do
    name = sentant_id <> "|" <> app_name()
    case Process.whereis(String.to_atom(name)) do
      nil->
        # It is not an error if the child does not exist
        {:ok}
      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec whereis(String.t()) :: pid() | nil
  @doc """
  Return the process id that can be used for subsequent communications.

  In this implementation, each Sentant gets its own Geospatial Entry GenServer process, but other Apps might just use a single process for all Sentants.
  Externally this is transparent.

  - Parameters
    - `id` - The id of the Sentant for which process id is being returned.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def whereis(sentant_id) do
    sentant_id <> "|" <> app_name() |> String.to_atom() |> Process.whereis()
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec sendto(String.t(), map()) :: {:ok} | {:error, :unknown_command}
  @doc """
  Send a command to the Geospatial Entry for the given Sentant id.

  Depending on the command, this might be a synchronous call or an asynchronous cast.  Ideally, use this convention when creating your own Apps
  so that the commands are consistent across all Apps.

  - Parameters
    - `id` - The id of the Sentant for which the command is being sent.
    - `command` - A map containing the command and parameters to be sent.

  - Returns
    - `{:ok}` - If the command was sent successfully.
    - `{:error, :unknown_command}` - If the command was not recognised.
  """
  def sendto(sentant_id, command_and_parameters) do
    case whereis(sentant_id) do
      nil ->
        {:error, :existence}
      pid ->
        case get(command_and_parameters, :command) do
          "set" ->
            GenServer.cast(pid, command_and_parameters)
          "delete" ->
            GenServer.cast(pid, command_and_parameters)
          "get" ->
             case GenServer.call(pid, command_and_parameters) do
                nil ->
                  {:error, :key}
                result ->
                  result
             end
          "all" ->
            GenServer.call(pid, command_and_parameters)
          "clear" ->
            GenServer.cast(pid, command_and_parameters)
          "search" ->
            GenServer.call(pid, command_and_parameters)
          _ ->
            {:error, :command}
        end
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Extract the App name from the module name and reformat it to be '.' separated and lower case.
  # In reality, the name used for the child nodes can be anything as long as it is unique and predictable, but this is a good convention to follow.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp app_name() do
    Atom.to_string(__MODULE__)
    |> String.replace_prefix("Elixir.", "")
    |> String.replace(~r/([A-Z])/u, ".\\1")
    |> String.downcase()
    |> String.replace_suffix(".main", "")
    |> String.trim(".")
  end

  def get(map, key, default \\ nil)
  def get(nil, _, default), do: default
  def get(map, key, default) when is_binary(key) do
    case Elixir.Map.get(map, key) do
      nil ->
        case Elixir.Map.get(map, String.to_atom(key)) do
          nil -> default
          value -> value
        end
      value -> value
    end
  end

  def get(map, key, default) when is_atom(key) do
    case Elixir.Map.get(map, key) do
      nil ->
        case Elixir.Map.get(map, Atom.to_string(key)) do
          nil -> default
          value -> value
        end
      value -> value
    end
  end

  def get(map, key, default), do: Elixir.Map.get(map, key, default)
  # -----------------------------------------------------------------------------------------------------------------------------------------
end
