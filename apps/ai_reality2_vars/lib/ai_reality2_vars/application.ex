defmodule AiReality2Vars.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{id: AiReality2Vars.Main, start: {AiReality2Vars.Main, :start_link, [AiReality2Vars.Main]}}
    ]

    opts = [strategy: :one_for_one, name: AiReality2Vars.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
