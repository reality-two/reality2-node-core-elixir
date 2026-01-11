defmodule AiReality2Transnet.DiscoverySupervisor do
  @moduledoc """
  Supervisor for the discovery layer (BLE and LoRa).

  This supervisor isolates discovery failures from the connection management layer.
  Uses `:one_for_one` strategy - each discovery mechanism can fail independently.

  ## Children
  - `Bluetooth` - BLE beacon discovery and GATT server
  - `LoRaMesh` - LoRa mesh networking (optional hardware)

  ## Restart Strategy
  `:one_for_one` - If Bluetooth crashes, LoRa continues (and vice versa)

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # BLE discovery - restart: :transient means don't restart if terminated normally
      # (e.g., Bluetooth unavailable is expected on some hardware)
      %{
        id: AiReality2Transnet.Bluetooth,
        start: {AiReality2Transnet.Bluetooth, :start_link, [AiReality2Transnet.Bluetooth]},
        restart: :transient
      },
      # LoRa mesh - also transient (hardware may not be present)
      %{
        id: AiReality2Transnet.LoRaMesh,
        start: {AiReality2Transnet.LoRaMesh, :start_link, [[]]},
        restart: :transient
      }
    ]

    Logger.info("[TransnetDiscoverySupervisor] Starting discovery layer (BLE + LoRa)")
    Supervisor.init(children, strategy: :one_for_one)
  end
end
