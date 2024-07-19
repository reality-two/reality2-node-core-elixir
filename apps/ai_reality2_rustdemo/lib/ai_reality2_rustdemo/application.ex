defmodule AiReality2Rustdemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: AiReality2Rustdemo.Worker.start_link(arg)
      # {AiReality2Rustdemo.Worker, arg}
      %{id: AiReality2Rustdemo.Main, start: {AiReality2Rustdemo.Main, :start_link, [AiReality2Rustdemo.Main]}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AiReality2Rustdemo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
