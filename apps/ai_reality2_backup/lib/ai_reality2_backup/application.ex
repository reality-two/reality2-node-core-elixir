defmodule AiReality2Backup.Application do
    @moduledoc false

    use Application

    @impl true
    def start(_type, _args) do
      children = [
          %{id: AiReality2Backup.Main, start: {AiReality2Backup.Main, :start_link, [AiReality2Backup.Main]}}
      ]

      opts = [strategy: :one_for_one, name: AiReality2Backup.Supervisor]
      Supervisor.start_link(children, opts)
    end
end
