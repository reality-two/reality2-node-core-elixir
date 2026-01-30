defmodule AiReality2Transnet.Transports.LoRaTransport do
  @moduledoc """
  LoRa transport adapter implementing the Transport behaviour.

  Translates between MeshRouter's structured messages and LoRaMesh's binary
  wire format. Uses 4-byte compressed node IDs instead of full UUIDs to
  conserve LoRa airtime.

  ## Revised Packet Format (8-byte header)

  ```
  Header (8 bytes):
    msg_id:        16 bits  (deduplication)
    ttl:            4 bits  (0-15 hops)
    packet_class:   4 bits  (event/signal/presence/backlog/lastseen/bundle)
    src_compressed: 32 bits (4-byte compressed node ID)

  Payload (variable, max ~192 bytes)
  ```

  ## Characteristics

  | Property | Value |
  |----------|-------|
  | Range | 2-15km |
  | Max Payload | 200 bytes (8 header + 192 payload) |
  | Latency | Medium |
  | Power | Medium |
  | Best For | Long range, rural, outdoor |

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  @behaviour AiReality2Transnet.Transport

  require Logger
  import Bitwise

  alias AiReality2Transnet.{HiveIdentity, HiveDirectory}

  @max_payload_size 200
  @header_size 8
  @max_inner_payload @max_payload_size - @header_size

  # Packet classes (4 bits)
  @class_event 0x01
  @class_signal 0x02
  @class_presence 0x03
  @class_backlog 0x04
  @class_lastseen 0x05
  @class_bundle 0x06

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
      unicast: false,
      bidirectional: true,
      reliable: false,
      max_payload: @max_payload_size
    }
  end

  @impl true
  def broadcast(message) do
    if available?() do
      # Validate payload fits
      payload_size = if is_binary(message.payload), do: byte_size(message.payload), else: 0
      if payload_size > @max_inner_payload do
        {:error, :payload_too_large}
      else
        # Encode to binary wire format with compressed IDs
        encoded = encode_message(message)
        # Send raw binary to LoRaMesh for transmission
        AiReality2Transnet.LoRaMesh.send_raw(encoded)
      end
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
  # Encoding — MeshRouter message → LoRa binary wire format
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Encodes a MeshRouter message into the 8-byte-header LoRa wire format.
  """
  @spec encode_message(map()) :: binary()
  def encode_message(message) do
    msg_id = Map.get(message, :msg_id, :rand.uniform(0xFFFF))
    ttl = min(Map.get(message, :ttl, 5), 15)
    packet_class = type_to_class(Map.get(message, :type, :event))

    # Get compressed source node ID (4 bytes)
    src_node_id = Map.get(message, :src_node_id, "")
    src_compressed = node_id_to_compressed(src_node_id)

    # Combine ttl (4 bits) and packet_class (4 bits) into one byte
    ttl_class = ((ttl &&& 0x0F) <<< 4) ||| (packet_class &&& 0x0F)

    payload = Map.get(message, :payload, <<>>)
    payload_bin = if is_binary(payload), do: payload, else: Jason.encode!(payload)

    # Truncate if too large
    payload_bin = if byte_size(payload_bin) > @max_inner_payload do
      binary_part(payload_bin, 0, @max_inner_payload)
    else
      payload_bin
    end

    <<msg_id::16, ttl_class::8, src_compressed::binary-size(4), payload_bin::binary>>
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Decoding — LoRa binary wire format → MeshRouter message
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Decodes a LoRa wire format binary into a MeshRouter-compatible message.

  Resolves compressed source ID to full UUID via HiveDirectory lookup table.
  """
  @spec decode_message(binary()) :: {:ok, map()} | {:error, :invalid_format}
  def decode_message(<<msg_id::16, ttl_class::8, src_compressed::binary-size(4), payload::binary>>) do
    ttl = (ttl_class >>> 4) &&& 0x0F
    packet_class = ttl_class &&& 0x0F
    type = class_to_type(packet_class)

    # Resolve compressed ID to full UUID
    src_node_id = resolve_compressed_id(src_compressed)

    {:ok, %{
      msg_id: msg_id,
      ttl: ttl,
      type: type,
      src_node_id: src_node_id,
      src_compressed: src_compressed,
      payload: payload
    }}
  end

  # Legacy 6-byte header format (backwards compatibility)
  def decode_message(<<msg_id::16, ttl::8, type_byte::8, src_hash::16, payload::binary>>)
      when byte_size(payload) > 0 do
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
      src_node_id: "hash:0x#{String.upcase(Integer.to_string(src_hash, 16) |> String.pad_leading(4, "0"))}",
      payload: payload
    }}
  end

  def decode_message(_), do: {:error, :invalid_format}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Presence Packet Encoding/Decoding
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Encodes a presence announcement for LoRa transmission.

  Payload format (up to 26 bytes):
    hive_compressed:  32 bits
    capabilities:      8 bits
    sentant_count:     8 bits
    hosting_priority:  8 bits
    node_name_hash:   16 bits
    cell_hint:        16 bits
    dir_version:      16 bits
    energy_state:      8 bits
    backlog_count:    16 bits
  """
  @spec encode_presence(map()) :: binary()
  def encode_presence(info) do
    hive_compressed = Map.get(info, :hive_compressed, <<0, 0, 0, 0>>)
    capabilities = encode_capabilities(Map.get(info, :capabilities, %{}))
    sentant_count = min(Map.get(info, :sentant_count, 0), 255)
    hosting_priority = min(Map.get(info, :hosting_priority, 0), 255)
    node_name_hash = Map.get(info, :node_name_hash, 0)
    cell_hint = Map.get(info, :cell_hint, 0)
    dir_version = Map.get(info, :dir_version, 0) |> min(0xFFFF)
    energy_state = Map.get(info, :energy_state, 255)
    backlog_count = Map.get(info, :backlog_count, 0) |> min(0xFFFF)

    <<
      hive_compressed::binary-size(4),
      capabilities::8,
      sentant_count::8,
      hosting_priority::8,
      node_name_hash::16,
      cell_hint::16,
      dir_version::16,
      energy_state::8,
      backlog_count::16
    >>
  end

  @doc """
  Decodes a presence payload.
  """
  @spec decode_presence(binary()) :: {:ok, map()} | {:error, :invalid_format}
  def decode_presence(<<
    hive_compressed::binary-size(4),
    capabilities::8,
    sentant_count::8,
    hosting_priority::8,
    node_name_hash::16,
    cell_hint::16,
    dir_version::16,
    energy_state::8,
    backlog_count::16
  >>) do
    {:ok, %{
      hive_compressed: hive_compressed,
      capabilities: decode_capabilities(capabilities),
      sentant_count: sentant_count,
      hosting_priority: hosting_priority,
      node_name_hash: node_name_hash,
      cell_hint: cell_hint,
      dir_version: dir_version,
      energy_state: energy_state,
      backlog_count: backlog_count
    }}
  end

  # Legacy 2-byte presence
  def decode_presence(<<sentant_count::16>>) do
    {:ok, %{sentant_count: sentant_count, capabilities: %{}, dir_version: 0}}
  end

  def decode_presence(_), do: {:error, :invalid_format}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — ID Conversion
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp node_id_to_compressed(node_id) when is_binary(node_id) do
    # Check if it's already a compressed ID (4 bytes)
    if byte_size(node_id) == 4 do
      node_id
    else
      HiveIdentity.compressed_id(node_id)
    end
  end

  defp resolve_compressed_id(compressed) when is_binary(compressed) and byte_size(compressed) == 4 do
    # Try HiveDirectory lookup first
    if Code.ensure_loaded?(HiveDirectory) and Process.whereis(HiveDirectory) != nil do
      case HiveDirectory.resolve_compressed_id(compressed) do
        {:ok, node_id} -> node_id
        {:error, _} -> "compressed:" <> HiveIdentity.compressed_id_to_hex(compressed)
      end
    else
      "compressed:" <> HiveIdentity.compressed_id_to_hex(compressed)
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Type/Class Conversion
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp type_to_class(:event), do: @class_event
  defp type_to_class(:signal), do: @class_signal
  defp type_to_class(:presence), do: @class_presence
  defp type_to_class(:backlog), do: @class_backlog
  defp type_to_class(:lastseen), do: @class_lastseen
  defp type_to_class(:bundle), do: @class_bundle
  defp type_to_class(_), do: @class_event

  defp class_to_type(@class_event), do: :event
  defp class_to_type(@class_signal), do: :signal
  defp class_to_type(@class_presence), do: :presence
  defp class_to_type(@class_backlog), do: :backlog
  defp class_to_type(@class_lastseen), do: :lastseen
  defp class_to_type(@class_bundle), do: :bundle
  defp class_to_type(_), do: :unknown

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Capabilities Bitfield
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp encode_capabilities(caps) when is_map(caps) do
    b0 = if Map.get(caps, :has_wifi, false), do: 1, else: 0
    b1 = if Map.get(caps, :has_ble, false), do: 1, else: 0
    b2 = if Map.get(caps, :is_relay, false), do: 1, else: 0
    b3 = if Map.get(caps, :is_bridge, false), do: 1, else: 0
    b4 = if Map.get(caps, :is_anchor, false), do: 1, else: 0
    b5 = if Map.get(caps, :is_sensor, false), do: 1, else: 0
    b6 = if Map.get(caps, :is_mobile, false), do: 1, else: 0
    b7 = if Map.get(caps, :is_cloud, false), do: 1, else: 0

    b0 ||| (b1 <<< 1) ||| (b2 <<< 2) ||| (b3 <<< 3) |||
    (b4 <<< 4) ||| (b5 <<< 5) ||| (b6 <<< 6) ||| (b7 <<< 7)
  end
  defp encode_capabilities(_), do: 0

  defp decode_capabilities(byte) do
    %{
      has_wifi: (byte &&& 0x01) != 0,
      has_ble: (byte &&& 0x02) != 0,
      is_relay: (byte &&& 0x04) != 0,
      is_bridge: (byte &&& 0x08) != 0,
      is_anchor: (byte &&& 0x10) != 0,
      is_sensor: (byte &&& 0x20) != 0,
      is_mobile: (byte &&& 0x40) != 0,
      is_cloud: (byte &&& 0x80) != 0
    }
  end
end
