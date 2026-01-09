defmodule AiReality2Pns.Main do
  @behaviour Reality2.Plugin.Main

  # *******************************************************************************************************************************************
  @moduledoc """
  Main entry point for the Pathing Name System (PNS) plugin.

  PNS provides routing for messages to Sentants across transient networks.
  Unlike per-Sentant plugins, PNS operates globally via the Router GenServer,
  so the create/delete callbacks are no-ops.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  @doc false
  use GenServer, restart: :transient

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(name), do: GenServer.start_link(__MODULE__, %{}, name: name)

  @doc false
  @impl true
  def init(state) do
    # Startup message is printed by Application module
    {:ok, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Does nothing in this module as PNS operates globally.

  PNS routing is managed by the Router GenServer, not per-Sentant processes.

  - Parameters
    - `sentant_id` - ignored in this implementation.
    - `details` - ignored in this implementation.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def create(_sentant_id, _details \\ %{}) do
    {:ok}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Does nothing in this module as PNS operates globally.

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

  In this implementation, this just refers to this module as PNS is global.

  - Parameters
    - `id` - The id of the Sentant (ignored).
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def whereis(_sentant_id) do
    self()
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  PNS doesn't support direct sendto commands.

  Use AiReality2Pns.Router functions instead for routing operations.

  - Parameters
    - `id` - The id of the Sentant (ignored)
    - `command` - Command map (ignored)
  """
  @impl true
  def sendto(_sentant_id, _command_and_parameters) do
    {:error, :not_supported}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
end
