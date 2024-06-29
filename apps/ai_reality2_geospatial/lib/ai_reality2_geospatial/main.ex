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
    alias Reality2.Helpers.R2Process, as: R2Process
    alias Reality2.Helpers.R2Map, as: R2Map

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Supervisor Callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link(init_arg) do
      DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    end


    @impl true
    def init(init_arg) do
      IO.puts("[ai.reality2.geospatial #{Mix.Project.config[:version]}] started successfully.")
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
      case whereis(sentant_id) do
        nil->
          case DynamicSupervisor.start_child(__MODULE__, AiReality2Geospatial.Data.child_spec({})) do
            {:ok, pid} ->
              R2Process.register(sentant_id, pid, AiReality2Geospatial.Processes)
              GenServer.cast(pid, %{command: "set", parameters: location, id: sentant_id})
              {:ok}
            error ->
              error
          end
        pid ->
          # Clear the data store so there is no old data that hackers might be able to access in the case this was a reused ID
          R2Process.register(sentant_id, pid, AiReality2Geospatial.Processes)
          GenServer.cast(pid, %{command: "clear"})
          GenServer.cast(pid, %{command: "set", parameters: location, id: sentant_id})
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
      case whereis(sentant_id) do
        nil->
          # It is not an error if the child does not exist
          {:ok}
        pid ->
          # Remove the sentant from the geospatial database
          GenServer.call(AiReality2Geospatial.GeohashSearch, %{command: "delete", sentantid: sentant_id})
          # Remove the registration from the processes DB
          R2Process.deregister(sentant_id, AiReality2Geospatial.Processes)
          # Terminate the child process
          DynamicSupervisor.terminate_child(__MODULE__, pid)
          {:ok}
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec whereis(String.t() | pid()) :: pid() | String.t() | nil
    @doc """
    Return the process id that can be used for subsequent communications.

    In this implementation, each Sentant gets its own Geospatial Entry GenServer process, but other Apps might just use a single process for all Sentants.
    Externally this is transparent.

    - Parameters
      - `id` - The id of the Sentant for which process id is being returned.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def whereis(sentant_id) do
      R2Process.whereis(sentant_id, AiReality2Geospatial.Processes)
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec sendto(String.t(), map()) :: :ok | {:error, :command} | {:ok, any()} | {:error, :key}
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
          case R2Map.get(command_and_parameters, :command) do
            "set" ->
              GenServer.cast(pid, Map.put(command_and_parameters, :id, sentant_id))
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
  end
