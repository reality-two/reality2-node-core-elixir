defmodule AiReality2Transnet.Main do
  @behaviour Reality2.Plugin.Main

  # *******************************************************************************************************************************************
  @moduledoc """
    Implementation of Transient Networks for Reality2 Nodes.

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
    IO.puts("[ai.reality2.transnet] started successfully.")
    DynamicSupervisor.init( strategy: :one_for_one, extra_arguments: [init_arg] )
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Create a process for each Sentant.  It is through these processes, set up as a plugin with return events, that network events are
  received.  In this way, only Sentants that really need to know about networking have these processes - more efficient.

  - Parameters
    - `sentant_id` - the Sentant ID.
    - `details` - other parameters required during set up.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
    def create(sentant_id, _details \\ %{}) do
      case whereis(sentant_id) do
        nil->
          case DynamicSupervisor.start_child(__MODULE__, AiReality2Transnet.Data.child_spec({})) do
            {:ok, pid} ->
              R2Process.register(sentant_id, pid, AiReality2Transnet.Processes)
              {:ok}
            error -> error
          end
        pid ->
          # Clear the data store so there is no old data that hackers might be able to access in the case this was a reused ID
          R2Process.register(sentant_id, pid, AiReality2Transnet.Processes)
          GenServer.call(pid, %{command: "clear"})
          {:ok}
      end
    end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Deletes the Sentant TransNet process.

  - Parameters
    - `sentant_id` - the Sentant IDss.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def delete(sentant_id) do
    case whereis(sentant_id) do
      nil->
        # It is not an error if the child does not exist
        {:ok}
      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        R2Process.deregister(sentant_id, AiReality2Transnet.Processes)
        {:ok}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Return the process id that can be used for subsequent communications.

  - Parameters
    - `id` - The id of the Sentant for which process id is being returned.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def whereis(sentant_id) do
    R2Process.whereis(sentant_id, AiReality2Transnet.Processes)
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Send commands to the plugin, and set up callbacks.

  - Parameters
    - `id` - The id of the Sentant for which the command is being sent.
    - `command` - A map containing the command and parameters to be sent.

  - Returns
    - `{:ok, %{/result map/}}` - If the command was sent successfully.
    - `{:error, :unknown_command}` - If the command was not recognised.
  """
  @impl true
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

end
