defmodule AiReality2Transnet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{
        id: AiReality2Transnet.Main,
        start: {AiReality2Transnet.Main, :start_link, [AiReality2Transnet.Main]}
      },
      %{
        id: AiReality2Transnet.Bluetooth,
        start: {AiReality2Transnet.Bluetooth, :start_link, [AiReality2Transnet.Bluetooth]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
