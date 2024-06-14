defmodule AiReality2Backup.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: AiReality2Backup.Worker.start_link(arg)
      # {AiReality2Backup.Worker, arg}
      %{id: AiReality2Backup.Main, start: {AiReality2Backup.Main, :start_link, [AiReality2Backup.Main]}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AiReality2Backup.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
