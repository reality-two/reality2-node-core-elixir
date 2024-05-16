defmodule AiReality2Geospatial.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: AiReality2Geospatial.Worker.start_link(arg)
      # {AiReality2Geospatial.Worker, arg}
      %{id: AiReality2Geospatial.Main, start: {AiReality2Geospatial.Main, :start_link, [AiReality2Geospatial.Main]}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AiReality2Geospatial.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
