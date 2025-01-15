defmodule AiReality2Transnet.Application do
  @moduledoc false

  use Application


  @impl true
  def start(_type, _args) do
    children = [
      %{id: AiReality2Transnet.Main, start: {AiReality2Transnet.Main, :start_link, [AiReality2Transnet.Main]}}
    ]

    opts = [strategy: :one_for_one, name: AiReality2Transnet.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
