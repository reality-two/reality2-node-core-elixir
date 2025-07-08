defmodule AiReality2Versioncontrol.Main do
  # *******************************************************************************************************************************************
  @moduledoc """
    Module for managing the main supervisor tree for the `AiReality2Versioncontrol` App.

    In this instance, the main supervisor is a DynamicSupervisor, which is used to manage the process of version control for this node.
    This is somewhat different than other plugins as it is not for use by Sentants, but rather an independent process that determines
    if and when updates are required either to the core code, or to plugins that this node uses.

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """
  # *******************************************************************************************************************************************
    @doc false
    use GenServer, restart: :transient
    alias Reality2.Helpers.R2Map, as: R2Map
    # alias Reality2.Helpers.Crypto, as: Crypto
    # alias :mnesia, as: Mnesia

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Supervisor Callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link(name),                              do: GenServer.start_link(__MODULE__, %{}, name: name)

    @doc false
    def init(state) do
        IO.puts("[ai.reality2.versioncontrol] started successfully.")
        {:ok, state}
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
    Does nothing in this module as there are no child processes.

    - Parameters
      - `sentant_id` - ignored in this implementation.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def create(_sentant_id) do
      {:ok}
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec delete(String.t()) ::
      {:ok}
      | {:error, :existance}

    @doc """
    Does nothing in this module as there are no child processes.

    - Parameters
      - `sentant_id` - ignored in this implementation.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def delete(_sentant_id) do
      {:ok}
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec whereis(String.t() | pid()) :: pid() | String.t() | nil
    @doc """
    Return the process id that can be used for subsequent communications.

    In this implementation, this just refers to this module.

    - Parameters
      - `id` - The id of the Sentant for which process id is being returned.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def whereis(_sentant_id) do
      self()
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec sendto(String.t(), map()) :: :ok | {:error, :command} | {:ok, any()} | {:error, :key}
    @doc """
    Allows sentants to query the state of version control.

    - Parameters
      - `id` - The id of the Sentant for which the command is being sent (ignored here)
      - `command` - A map containing the command and parameters to be sent.

    - Returns
      - `{:ok}` - If the command was sent successfully.
      - `{:error, :command}` - If the command was not recognised.
    """
    def sendto(_sentant_id, command_and_parameters) do
      # parameters = R2Map.get(command_and_parameters, :parameters, %{})
      # data = parameters |> R2Map.delete(:result)
      case R2Map.get(command_and_parameters, :command) do
        "status" ->
          {:ok}
        _ ->
          {:error, :command}
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Private Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # Update the
    def update() do

    end

    # -----------------------------------------------------------------------------------------------------------------------------------------
  end
