defmodule Reality2Transnet.Main do
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

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(name), do: GenServer.start_link(__MODULE__, %{}, name: name)

  @doc false
  @impl true
  def init(state) do
    node_name = Reality2.Bootstrap.get(:node_name, "unknown")
    Logger.info("[reality2.transnet:#{node_name}] Main GenServer initialized")
    {:ok, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
end
