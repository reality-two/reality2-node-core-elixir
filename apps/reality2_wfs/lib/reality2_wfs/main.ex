defmodule Reality2Wfs.Main do
  # *******************************************************************************************************************************************
  @moduledoc """
  Main entry point for the Waggle Finding Service (WFS).

  WFS provides routing for messages to Sentants across transient networks.
  WFS operates globally via the Router GenServer.

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
end
