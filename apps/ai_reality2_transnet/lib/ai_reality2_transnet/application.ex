defmodule AiReality2Transnet.Application do
  # *******************************************************************************************************************************************
  @moduledoc """
  Main supervisor for Transient Networking App

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

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
