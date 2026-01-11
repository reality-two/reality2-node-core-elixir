defmodule AiReality2Transnet.ConnectionSupervisor do
  @moduledoc """
  Supervisor for the WiFi connection management layer.

  This supervisor manages the tightly-coupled connection components with proper
  dependency ordering using `:rest_for_one` strategy.

  ## Children (in dependency order)
  1. `ConnectionManager` - WiFi hotspot/client management
  2. `ConnectionAssessor` - Connection quality assessment and handover decisions

  ## Restart Strategy
  `:rest_for_one` - If ConnectionManager restarts, ConnectionAssessor also restarts.
  This is critical because ConnectionAssessor makes GenServer.call to ConnectionManager,
  and if ConnectionManager restarts, ConnectionAssessor's cached state/assumptions
  become invalid.

  ## Why not :one_for_all?
  ConnectionAssessor can crash without needing to restart ConnectionManager.
  The dependency is one-directional: Assessor → Manager.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # Order matters with :rest_for_one!
    # ConnectionManager must start first, then ConnectionAssessor
    children = [
      # ConnectionManager - WiFi hotspot/client management
      # restart: :permanent - critical for mesh operation
      %{
        id: AiReality2Transnet.ConnectionManager,
        start: {AiReality2Transnet.ConnectionManager, :start_link, [[]]},
        restart: :permanent,
        shutdown: 10_000  # Allow 10s for graceful shutdown (cleanup WiFi)
      },
      # ConnectionAssessor - periodic assessment and handover
      # restart: :permanent - must keep assessing
      # If ConnectionManager restarts, this also restarts (rest_for_one)
      %{
        id: AiReality2Transnet.ConnectionAssessor,
        start: {AiReality2Transnet.ConnectionAssessor, :start_link, [[]]},
        restart: :permanent
      }
    ]

    Logger.info("[TransnetConnectionSupervisor] Starting connection layer (Manager + Assessor)")
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
