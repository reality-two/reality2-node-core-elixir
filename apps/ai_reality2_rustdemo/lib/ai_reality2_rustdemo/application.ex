defmodule AiReality2Rustdemo.Application do
  @moduledoc false

  use Application


  @impl true
  def start(_type, _args) do
    children = [
      %{id: AiReality2Rustdemo.Main, start: {AiReality2Rustdemo.Main, :start_link, [AiReality2Rustdemo.Main]}}
    ]

    opts = [strategy: :one_for_one, name: AiReality2Rustdemo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
