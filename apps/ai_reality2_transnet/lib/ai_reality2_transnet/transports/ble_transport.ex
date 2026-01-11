defmodule AiReality2Transnet.Transports.BLETransport do
  @moduledoc """
  BLE transport adapter implementing the Transport behaviour.

  Wraps the existing Bluetooth module to provide transport-agnostic
  mesh communication via BLE advertising and GATT.

  ## Characteristics

  | Property | Value |
  |----------|-------|
  | Range | ~100m (varies) |
  | Max Payload | 18 bytes |
  | Latency | Low |
  | Power | Low |
  | Best For | Discovery, small messages |

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  @behaviour AiReality2Transnet.Transport

  require Logger

  # BLE advertising data is limited
  @max_payload_size 18

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Transport Behaviour Implementation
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def transport_type, do: :ble

  @impl true
  def available? do
    Code.ensure_loaded?(AiReality2Transnet.Bluetooth) and
      Process.whereis(AiReality2Transnet.Bluetooth) != nil
  end

  @impl true
  def max_payload_size, do: @max_payload_size

  @impl true
  def capabilities do
    %{
      broadcast: true,
      unicast: false,        # BLE advertising is broadcast-only
      bidirectional: true,   # Via GATT characteristics
      reliable: false,       # Best effort
      max_payload: @max_payload_size
    }
  end

  @impl true
  def broadcast(message) do
    if available?() do
      # Encode message in compact format for BLE
      encoded = encode_for_ble(message)

      if byte_size(encoded) <= @max_payload_size + 6 do  # 6 bytes header
        AiReality2Transnet.Bluetooth.broadcast_mesh_message(encoded)
        :ok
      else
        {:error, :payload_too_large}
      end
    else
      {:error, :not_available}
    end
  end

  @impl true
  def send_to(_peer_id, _message) do
    # BLE advertising doesn't support unicast
    # Could implement via GATT write if peer is connected
    {:error, :not_supported}
  end

  @impl true
  def handle_incoming(raw_data) do
    case decode_from_ble(raw_data) do
      {:ok, message} ->
        AiReality2Transnet.MeshRouter.handle_incoming(message, :ble)
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  @impl true
  def get_stats do
    if available?() do
      state = AiReality2Transnet.Bluetooth.get_state()
      %{
        available: true,
        signals_broadcast: Map.get(state, :signals_broadcast, 0),
        queries_processed: Map.get(state, :queries_processed, 0),
        watchdog_restarts: Map.get(state, :watchdog_restarts, 0)
      }
    else
      %{available: false}
    end
  end

  @impl true
  def get_peers do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      AiReality2Transnet.PeerManager.get_all_peers()
      |> Map.keys()
    else
      []
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Encoding/Decoding
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Encode message for BLE (compact binary format)
  defp encode_for_ble(message) do
    # Convert type atom to integer
    type_byte = case message.type do
      :event -> 0x01
      :signal -> 0x02
      :presence -> 0x03
      _ -> 0x00
    end

    # Hash node ID to 2 bytes
    src_hash = hash16(message.src_node_id)

    # Truncate payload if needed
    payload = if byte_size(message.payload) > @max_payload_size do
      binary_part(message.payload, 0, @max_payload_size)
    else
      message.payload
    end

    <<
      message.msg_id::16,
      message.ttl::8,
      type_byte::8,
      src_hash::16,
      payload::binary
    >>
  end

  # Decode message from BLE format
  defp decode_from_ble(<<msg_id::16, ttl::8, type_byte::8, src_hash::16, payload::binary>>) do
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
      src_node_id: "hash:#{Integer.to_string(src_hash, 16)}",  # We only have hash
      payload: payload
    }}
  end

  defp decode_from_ble(_), do: {:error, :invalid_format}

  defp hash16(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(5381, fn byte, hash ->
      rem((hash * 33) + byte, 0x100000000)
    end)
    |> Bitwise.band(0xFFFF)
  end
end
