defmodule Reality2Web.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Reality2Web.Telemetry,
      # Start a worker by calling: Reality2Web.Worker.start_link(arg)
      # {Reality2Web.Worker, arg},
      # Start to serve requests, typically the last entry
      {Phoenix.PubSub, name: Reality2Web.PubSub},
      Reality2Web.Endpoint,
      {Absinthe.Subscription, Reality2Web.Endpoint}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Reality2Web.Supervisor]
    IO.puts("[ai.reality2.web #{Mix.Project.config[:version]}] started successfully.")
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Reality2Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
