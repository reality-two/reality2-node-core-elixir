defmodule Reality2Transnet.Transports.InternetTransport do
  @moduledoc """
  Internet transport adapter implementing the Transport behaviour.

  Routes mesh messages to cloud-hosted hive nodes via the CloudConnector.
  Used when hive members include nodes running in the cloud (backup servers,
  analytics processors, always-on coordinators, etc.).

  ## Characteristics

  | Property | Value |
  |----------|-------|
  | Range | Global (internet) |
  | Max Payload | 1MB |
  | Latency | Medium-High (variable) |
  | Power | Low (delegated to network stack) |
  | Best For | Cloud backup, always-on relay, analytics |

  ## Connection Model

  Unlike local transports (BLE, WiFi, LoRa) which operate in proximity,
  the Internet transport connects to pre-configured cloud endpoints via
  WebSocket (or HTTP polling fallback). At least one local node must have
  internet connectivity (GSM, wired ethernet, WiFi to internet).

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  @behaviour Reality2Transnet.Transport

  require Logger

  alias Reality2Transnet.CloudConnector

  @max_payload_size 1_000_000  # 1MB — same as WiFi

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Transport Behaviour Implementation
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def transport_type, do: :internet

  @impl true
  def available? do
    Code.ensure_loaded?(CloudConnector) and
      Process.whereis(CloudConnector) != nil and
      CloudConnector.available?()
  end

  @impl true
  def max_payload_size, do: @max_payload_size

  @impl true
  def capabilities do
    %{
      broadcast: true,         # Send to all connected cloud nodes
      unicast: true,           # Send to specific cloud node
      bidirectional: true,     # Full duplex over WebSocket/HTTP
      reliable: true,          # TCP-based
      max_payload: @max_payload_size
    }
  end

  @impl true
  def broadcast(message) do
    if available?() do
      CloudConnector.send_to_cloud(message)
    else
      {:error, :not_available}
    end
  end

  @impl true
  def send_to(peer_id, message) do
    if available?() do
      CloudConnector.send_to_node(peer_id, message)
    else
      {:error, :not_available}
    end
  end

  @impl true
  def handle_incoming(raw_data) do
    # CloudConnector handles incoming messages directly via MeshRouter.handle_incoming/2
    # This callback exists for completeness but incoming messages from cloud
    # are routed through CloudConnector → MeshRouter, not through this adapter
    case Jason.decode(raw_data) do
      {:ok, data} ->
        message_type = parse_message_type(Map.get(data, "message_type", "event"))
        message = %{
          msg_id: Map.get(data, "msg_id", :rand.uniform(0xFFFFFFFF)),
          ttl: Map.get(data, "ttl", 5),
          type: message_type,
          src_node_id: Map.get(data, "src_node_id", ""),
          payload: Map.get(data, "payload", "")
        }
        Reality2Transnet.MeshRouter.handle_incoming(message, :internet)
        :ok

      {:error, reason} ->
        Logger.warning("[InternetTransport] Failed to decode incoming message: #{inspect(reason)}")
        :ok
    end
  rescue
    e ->
      Logger.warning("[InternetTransport] Error handling incoming message: #{Exception.message(e)}")
      :ok
  end

  # Safe message type parsing — maps known string types to atoms, defaults to :event
  defp parse_message_type("event"), do: :event
  defp parse_message_type("signal"), do: :signal
  defp parse_message_type("presence"), do: :presence
  defp parse_message_type("data"), do: :data
  defp parse_message_type(other) do
    Logger.warning("[InternetTransport] Unknown message_type: #{inspect(other)}, defaulting to :event")
    :event
  end

  @impl true
  def get_stats do
    if available?() do
      status = CloudConnector.get_status()
      connected = Enum.count(status, fn s -> s.status == :connected end)
      %{
        available: true,
        connected_cloud_nodes: connected,
        total_configured: length(status),
        nodes: status
      }
    else
      %{available: false}
    end
  end

  @impl true
  def get_peers do
    if available?() do
      CloudConnector.connected_nodes()
    else
      []
    end
  end
end
