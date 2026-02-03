defmodule Reality2Wfs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Waggle Finding Service Router - Location-transparent routing
      Reality2Wfs.Router
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Reality2Wfs.Supervisor]
    Logger.info("[reality2.wfs] started successfully")
    Supervisor.start_link(children, opts)
  end
end
