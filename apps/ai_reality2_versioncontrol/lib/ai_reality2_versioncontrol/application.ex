defmodule AiReality2Versioncontrol.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{id: AiReality2Versioncontrol.Main, start: {AiReality2Versioncontrol.Main, :start_link, [AiReality2Versioncontrol.Main]}}
    ]

    opts = [strategy: :one_for_one, name: AiReality2Versioncontrol.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
