defmodule AiReality2Transnet.Transports.LoRaTransport do
  @moduledoc """
  LoRa transport adapter implementing the Transport behaviour.

  Provides long-range mesh communication via LoRa radio.
  Alternative to WiFi for rural/outdoor scenarios.

  ## Characteristics

  | Property | Value |
  |----------|-------|
  | Range | 2-15km |
  | Max Payload | 200 bytes |
  | Latency | Medium |
  | Power | Medium |
  | Best For | Long range, rural, outdoor |

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  @behaviour AiReality2Transnet.Transport

  require Logger

  @max_payload_size 200

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Transport Behaviour Implementation
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def transport_type, do: :lora

  @impl true
  def available? do
    Code.ensure_loaded?(AiReality2Transnet.LoRaMesh) and
      AiReality2Transnet.LoRaMesh.available?()
  end

  @impl true
  def max_payload_size, do: @max_payload_size

  @impl true
  def capabilities do
    %{
      broadcast: true,
      unicast: false,        # LoRa is broadcast
      bidirectional: true,   # Can receive
      reliable: false,       # Best effort
      max_payload: @max_payload_size
    }
  end

  @impl true
  def broadcast(message) do
    if available?() do
      # Forward to existing LoRaMesh module
      AiReality2Transnet.LoRaMesh.broadcast_event(
        message.src_node_id,
        to_string(message.type),
        %{payload: message.payload, ttl: message.ttl, msg_id: message.msg_id}
      )
    else
      {:error, :not_available}
    end
  end

  @impl true
  def send_to(_peer_id, _message) do
    {:error, :not_supported}
  end

  @impl true
  def handle_incoming(raw_data) do
    case decode_message(raw_data) do
      {:ok, message} ->
        AiReality2Transnet.MeshRouter.handle_incoming(message, :lora)
        :ok

      {:error, _} ->
        :ok
    end
  end

  @impl true
  def get_stats do
    if available?() do
      AiReality2Transnet.LoRaMesh.get_stats()
    else
      %{available: false}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp decode_message(<<msg_id::16, ttl::8, type_byte::8, src_hash::16, payload::binary>>) do
    type = case type_byte do
      0x01 -> :event
      0x02 -> :signal
      0x03 -> :presence
      _ -> :unknown
    end

    {:ok, %{
      msg_id: msg_id,
      ttl: ttl,
      type: type,
      src_node_id: "hash:#{Integer.to_string(src_hash, 16)}",
      payload: payload
    }}
  end

  defp decode_message(_), do: {:error, :invalid_format}
end
