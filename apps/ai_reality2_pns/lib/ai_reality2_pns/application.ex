defmodule AiReality2Pns.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Pathing Name System Router - Location-transparent routing
      AiReality2Pns.Router
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AiReality2Pns.Supervisor]
    Logger.info("[ai.reality2.pns] started successfully")
    Supervisor.start_link(children, opts)
  end
end
