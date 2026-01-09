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
        id: AiReality2Transnet.PeerManager,
        start: {AiReality2Transnet.PeerManager, :start_link, [[]]}
      },
      %{
        id: AiReality2Transnet.ConnectionManager,
        start: {AiReality2Transnet.ConnectionManager, :start_link, [[]]}
      },
      %{
        id: AiReality2Transnet.ConnectionAssessor,
        start: {AiReality2Transnet.ConnectionAssessor, :start_link, [[]]}
      },
      %{
        id: AiReality2Transnet.Bluetooth,
        start: {AiReality2Transnet.Bluetooth, :start_link, [AiReality2Transnet.Bluetooth]}
      }
      # NOTE: Legacy modules removed (preserved in git history):
      # - WifiServer: Port 8080/8081 HTTP server for mesh networking
      # - TransportManager: Mesh upgrade decision logic
      #
      # New hotspot architecture:
      #   - BLE beacons for discovery
      #   - ConnectionManager for hotspot/client WiFi
      #   - ConnectionAssessor for quality assessment and handover
      #   - Reality2Web GraphQL (port 4005) for sentantAll exchange
    ]

    IO.puts("[ai.reality2.transnet] started successfully.")
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
