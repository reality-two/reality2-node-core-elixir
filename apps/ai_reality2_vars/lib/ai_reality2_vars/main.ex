defmodule AiReality2Vars.Main do
  # *******************************************************************************************************************************************
  @moduledoc """
    Module for managing the main supervisor tree for the `AiReality2Vars` App.

    In this instance, the main supervisor is a DynamicSupervisor, which is used to manage the Data stores for each Sentant,
    however, this could be a PartitionSupervisor, or indeed, just a single process for all Sentants.

    Use this as a template for your own Main module for your own Apps.  The `create`, `delete`, `sendto` and `whereis` functions must be implemented.

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
      DynamicSupervisor.init( strategy: :one_for_one, extra_arguments: [init_arg] )
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Public Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec create(String.t()) ::
      {:ok}
      | {:error, :existance}

    @doc """
    Create a new Data store, returning {:ok} or an appropriate error.

    This creates a new child for each Sentant where the id is passed in and has the App name appended.

    - Parameters
      - `id` - The id of the Sentant for which the Data store is being created.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def create(sentant_id) do
      case whereis(sentant_id) do
        nil->
          case DynamicSupervisor.start_child(__MODULE__, AiReality2Vars.Data.child_spec({})) do
            {:ok, pid} ->
              R2Process.register(sentant_id, pid, AiReality2Vars.Processes)
              {:ok}
            error -> error
          end
        pid ->
          # Clear the data store so there is no old data that hackers might be able to access in the case this was a reused ID
          R2Process.register(sentant_id, pid, AiReality2Vars.Processes)
          GenServer.call(pid, %{command: "clear"})
          {:ok}
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec delete(String.t()) ::
      {:ok}
      | {:error, :existance}

    @doc """
    Delete a Data store, returning {:ok} or an appropriate error.

    - Parameters
      - `id` - The id of the Sentant for which the Data store is being deleted.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def delete(sentant_id) do
      case whereis(sentant_id) do
        nil->
          # It is not an error if the child does not exist
          {:ok}
        pid ->
          DynamicSupervisor.terminate_child(__MODULE__, pid)
          R2Process.deregister(sentant_id, AiReality2Vars.Processes)
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
      R2Process.whereis(sentant_id, AiReality2Vars.Processes)
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec sendto(String.t(), map()) :: {:ok} | {:error, :unknown_command}
    @doc """
    Send a command to the Data store for the given Sentant id.

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
