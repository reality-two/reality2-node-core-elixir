defmodule AiReality2Transnet.Main do
  @behaviour Reality2.Plugin.Main

  # *******************************************************************************************************************************************
  @moduledoc """
  Transient Networking for Reality2 Nodes

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  @doc false
  use GenServer, restart: :transient
  require Logger
  alias Reality2.Helpers.R2Map, as: R2Map
  # alias Reality2.Helpers.Convert, as: Convert

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(name), do: GenServer.start_link(__MODULE__, %{}, name: name)

  @doc false
  @impl true
  def init(state) do
    Logger.info("[ai.reality2.transnet] Main GenServer initialized")
    {:ok, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Does nothing in this module as there are no child processes.

  - Parameters
    - `sentant_id` - ignored in this implementation.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def create(_sentant_id, _details \\ %{}) do
    {:ok}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Does nothing in this module as there are no child processes.

  - Parameters
    - `sentant_id` - ignored in this implementation.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def delete(_sentant_id) do
    {:ok}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Return the process id that can be used for subsequent communications.

  In this implementation, this just refers to this module.

  - Parameters
    - `id` - The id of the Sentant for which process id is being returned.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def whereis(_sentant_id) do
    self()
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Send the command and parameters directly through from the Automation.

  - Parameters
    - `id` - The id of the Sentant for which the command is being sent (ignored here)
    - `command` - A map containing the command and parameters to be sent.
  """
  @impl true
  def sendto(_sentant_id, command_and_parameters) do
    command = R2Map.get(command_and_parameters, :command)
    parameters = R2Map.get(command_and_parameters, :parameters)

    # Send to Bluetooth server for command handling
    GenServer.cast(AiReality2Transnet.Bluetooth, %{command: command, parameters: parameters})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
end
