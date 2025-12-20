defmodule AiReality2Transnet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{
        id: AiReality2Transnet.Processes,
        start: {Reality2.Helpers.R2Process, :start_link, [AiReality2Transnet.Processes]}
      },
      %{
        id: AiReality2Transnet.Main,
        start: {AiReality2Transnet.Main, :start_link, [AiReality2Transnet.Main]}
      },
      %{
        id: AiReality2Transnet.Bluetooth,
        start: {AiReality2Transnet.Bluetooth, :start_link, [AiReality2Transnet.Bluetooth]}
      },

      # Event bus for discovery notifications (multi-subscriber)
      {Registry, keys: :duplicate, name: AiReality2Transnet.Bluetooth.Registry},

      # BlueZ discovery scanner (sibling child)
      %{
        id: AiReality2Transnet.Bluetooth.BlueZScanner,
        start:
          {AiReality2Transnet.Bluetooth.BlueZScanner, :start_link,
           [
             [
               name: AiReality2Transnet.Bluetooth.BlueZScanner,
               registry: AiReality2Transnet.Bluetooth.Registry,
               adapter: "hci0",
               transport: "le",

               # safety-net poll + drop-off heuristic
               scan_interval_ms: 30_000,
               stale_after_ms: 120_000
             ]
           ]}
      }
    ]

    # opts = [strategy: :one_for_one, name: AiReality2Transnet.Supervisor]
    # Supervisor.start_link(children, opts)
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
