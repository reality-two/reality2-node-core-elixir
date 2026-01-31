defmodule AiReality2Transnet.R2Mesh do
  @moduledoc """
  R2 Mesh - Simple relay protocol for Sentant communication over BLE.

  A pragmatic mesh-like protocol that works on any BLE device without requiring
  BlueZ 5.47+ or special mesh daemons. Uses existing BLE advertising with
  managed flooding and deduplication.

  ## How It Works

  ```
  Node A                    Node B                    Node C
    │                         │                         │
    │──── broadcast ─────────▶│                         │
    │     [msg_id][ttl=3]     │                         │
    │                         │──── relay ─────────────▶│
    │                         │     [msg_id][ttl=2]     │
    │                         │                         │
    │◀─────────────────────────────── relay ───────────│
    │     (dropped - seen)          [msg_id][ttl=1]    │
  ```

  ## Message Format

  Fits in BLE advertising data (alongside beacon):

  ```
  ┌────────────────────────────────────────────────────┐
  │  [msg_id:2][ttl:1][type:1][src_hash:2][payload:18] │
  │                                                    │
  │  Total: 24 bytes (fits in manufacturer data)       │
  └────────────────────────────────────────────────────┘
  ```

  ## Message Types

  - `0x01` EVENT   - Sentant event broadcast
  - `0x02` SIGNAL  - Directed signal (target in payload)
  - `0x03` PRESENCE - Node/Sentant announcement

  ## Future Migration

  This protocol can be replaced by:
  - **BLE Mesh** - When BlueZ 5.47+ is available
  - **WiFi Mesh** - For higher bandwidth needs
  - **LoRa Mesh** - For long range

  The Sentant/WFS layer remains unchanged regardless of transport.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  # Helper to get node name for log messages
  defp log_prefix, do: "[R2Mesh:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Constants
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Message types
  @msg_type_event 0x01
  @msg_type_signal 0x02
  @msg_type_presence 0x03

  # Protocol settings
  @default_ttl 5
  @max_payload_size 18
  @seen_cache_ttl_ms 30_000        # Forget seen messages after 30s
  @seen_cache_cleanup_ms 10_000    # Cleanup interval
  @presence_interval_ms 60_000     # Announce presence every 60s
  @relay_delay_ms 50               # Small random delay before relay (reduce collisions)

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Types
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc "R2 Mesh message"
  @type r2_message :: %{
    msg_id: non_neg_integer(),
    ttl: non_neg_integer(),
    type: non_neg_integer(),
    src_hash: non_neg_integer(),
    payload: binary()
  }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Broadcasts a Sentant event to the mesh.

  Event will be flooded to all reachable nodes within TTL hops.

  ## Parameters
  - `sentant_id` - Source Sentant identifier
  - `event_name` - Event name (will be hashed to 2 bytes)
  - `params` - Event parameters (will be compacted, max ~14 bytes useful)

  ## Returns
  - `:ok` - Message queued for broadcast
  - `{:error, reason}` - Failed

  ## Example

      R2Mesh.broadcast_event("sensor_1", "temp", %{v: 23})
  """
  @spec broadcast_event(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def broadcast_event(sentant_id, event_name, params \\ %{}) do
    GenServer.call(__MODULE__, {:broadcast_event, sentant_id, event_name, params})
  end

  @doc """
  Sends a signal to a specific Sentant via mesh.

  ## Parameters
  - `source_sentant` - Source Sentant ID
  - `target_sentant` - Target Sentant ID (or "node|sentant")
  - `signal_name` - Signal name
  - `params` - Signal parameters (max ~10 bytes useful)

  ## Returns
  - `:ok` - Message queued
  - `{:error, reason}` - Failed
  """
  @spec send_signal(String.t(), String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def send_signal(source_sentant, target_sentant, signal_name, params \\ %{}) do
    GenServer.call(__MODULE__, {:send_signal, source_sentant, target_sentant, signal_name, params})
  end

  @doc """
  Handles an incoming mesh message (called by Bluetooth GenServer).

  ## Parameters
  - `raw_data` - Raw message bytes from BLE advertising

  ## Returns
  - `:ok`
  """
  @spec handle_incoming(binary()) :: :ok
  def handle_incoming(raw_data) do
    GenServer.cast(__MODULE__, {:incoming, raw_data})
  end

  @doc """
  Gets mesh statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Checks if a message fits in R2 Mesh payload.

  ## Parameters
  - `data` - Data to check (map will be encoded)

  ## Returns
  - `true` - Fits
  - `false` - Too large, use WiFi
  """
  @spec fits?(term()) :: boolean()
  def fits?(data) when is_map(data) do
    case compact_encode(data) do
      {:ok, encoded} -> byte_size(encoded) <= @max_payload_size - 4  # Leave room for headers
      _ -> false
    end
  end

  def fits?(data) when is_binary(data), do: byte_size(data) <= @max_payload_size - 4
  def fits?(_), do: false

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Schedule cleanup and presence tasks
    schedule_cleanup()
    schedule_presence()

    state = %{
      # Seen message cache: %{msg_id => timestamp}
      seen: %{},
      # Pending outgoing messages (with random delay for collision avoidance)
      outgoing_queue: :queue.new(),
      # Statistics
      stats: %{
        messages_sent: 0,
        messages_received: 0,
        messages_relayed: 0,
        messages_dropped_seen: 0,
        messages_dropped_ttl: 0
      }
    }

    Logger.info("#{log_prefix()} Started - simple relay protocol for Sentant communication")
    {:ok, state}
  end

  @impl true
  def handle_call({:broadcast_event, sentant_id, event_name, params}, _from, state) do
    msg_id = generate_msg_id()
    src_hash = hash16(sentant_id)
    event_hash = hash16(event_name)

    # Encode params compactly
    case compact_encode(params) do
      {:ok, params_bin} when byte_size(params_bin) <= @max_payload_size - 4 ->
        # Payload: [event_hash:2][params]
        payload = <<event_hash::16>> <> params_bin

        message = %{
          msg_id: msg_id,
          ttl: @default_ttl,
          type: @msg_type_event,
          src_hash: src_hash,
          payload: payload
        }

        # Mark as seen (don't relay our own messages)
        new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))

        # Broadcast immediately
        broadcast_message(message)

        new_stats = Map.update!(state.stats, :messages_sent, &(&1 + 1))
        {:reply, :ok, %{state | seen: new_seen, stats: new_stats}}

      {:ok, _} ->
        {:reply, {:error, "payload_too_large"}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_signal, source, target, signal_name, params}, _from, state) do
    msg_id = generate_msg_id()
    src_hash = hash16(source)
    target_hash = hash16(target)
    signal_hash = hash16(signal_name)

    case compact_encode(params) do
      {:ok, params_bin} when byte_size(params_bin) <= @max_payload_size - 6 ->
        # Payload: [target_hash:2][signal_hash:2][params]
        payload = <<target_hash::16, signal_hash::16>> <> params_bin

        message = %{
          msg_id: msg_id,
          ttl: @default_ttl,
          type: @msg_type_signal,
          src_hash: src_hash,
          payload: payload
        }

        new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))
        broadcast_message(message)

        new_stats = Map.update!(state.stats, :messages_sent, &(&1 + 1))
        {:reply, :ok, %{state | seen: new_seen, stats: new_stats}}

      {:ok, _} ->
        {:reply, {:error, "payload_too_large"}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      seen_cache_size: map_size(state.seen)
    })
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:incoming, raw_data}, state) do
    case decode_message(raw_data) do
      {:ok, message} ->
        handle_mesh_message(message, state)

      {:error, _reason} ->
        # Not a mesh message or malformed - ignore
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_seen, state) do
    now = System.system_time(:millisecond)
    cutoff = now - @seen_cache_ttl_ms

    # Remove old entries
    new_seen = state.seen
      |> Enum.filter(fn {_id, ts} -> ts > cutoff end)
      |> Map.new()

    schedule_cleanup()
    {:noreply, %{state | seen: new_seen}}
  end

  @impl true
  def handle_info(:announce_presence, state) do
    announce_presence()
    schedule_presence()
    {:noreply, state}
  end

  @impl true
  def handle_info({:relay, message}, state) do
    # Delayed relay to reduce collision probability
    broadcast_message(message)
    new_stats = Map.update!(state.stats, :messages_relayed, &(&1 + 1))
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("#{log_prefix()} Unhandled: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Message Handling
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp handle_mesh_message(message, state) do
    msg_id = message.msg_id

    # Check if we've seen this message
    if Map.has_key?(state.seen, msg_id) do
      new_stats = Map.update!(state.stats, :messages_dropped_seen, &(&1 + 1))
      {:noreply, %{state | stats: new_stats}}
    else
      # Mark as seen
      new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))
      new_stats = Map.update!(state.stats, :messages_received, &(&1 + 1))

      # Deliver to local Sentants
      deliver_locally(message)

      # Relay if TTL > 1
      if message.ttl > 1 do
        relay_message = %{message | ttl: message.ttl - 1}
        # Random delay to reduce collisions
        delay = :rand.uniform(@relay_delay_ms * 2)
        Process.send_after(self(), {:relay, relay_message}, delay)
      end

      {:noreply, %{state | seen: new_seen, stats: new_stats}}
    end
  end

  defp deliver_locally(message) do
    case message.type do
      @msg_type_event ->
        deliver_event(message)

      @msg_type_signal ->
        deliver_signal(message)

      @msg_type_presence ->
        # Presence messages are informational - could update peer tracking
        Logger.debug("#{log_prefix()} Presence from 0x#{Integer.to_string(message.src_hash, 16)}")

      _ ->
        Logger.debug("#{log_prefix()} Unknown message type: #{message.type}")
    end
  end

  defp deliver_event(message) do
    # Decode payload: [event_hash:2][params]
    case message.payload do
      <<event_hash::16, params_bin::binary>> ->
        params = compact_decode(params_bin)

        # Broadcast to all local Sentants
        Reality2.Sentants.sendto_all(%{
          event: "__r2mesh_event",
          parameters: %{
            src_hash: message.src_hash,
            event_hash: event_hash,
            params: params,
            ttl: message.ttl,
            transport: :r2_mesh
          }
        })

      _ ->
        Logger.warning("#{log_prefix()} Malformed event payload")
    end
  end

  defp deliver_signal(message) do
    # Decode payload: [target_hash:2][signal_hash:2][params]
    case message.payload do
      <<target_hash::16, signal_hash::16, params_bin::binary>> ->
        params = compact_decode(params_bin)

        # Check if target is local
        # For now, broadcast to all - Sentants can filter by their own hash
        Reality2.Sentants.sendto_all(%{
          event: "__r2mesh_signal",
          parameters: %{
            src_hash: message.src_hash,
            target_hash: target_hash,
            signal_hash: signal_hash,
            params: params,
            ttl: message.ttl,
            transport: :r2_mesh
          }
        })

      _ ->
        Logger.warning("#{log_prefix()} Malformed signal payload")
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Message Encoding/Decoding
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp encode_message(message) do
    <<
      message.msg_id::16,
      message.ttl::8,
      message.type::8,
      message.src_hash::16,
      message.payload::binary
    >>
  end

  defp decode_message(<<msg_id::16, ttl::8, type::8, src_hash::16, payload::binary>>) do
    {:ok, %{
      msg_id: msg_id,
      ttl: ttl,
      type: type,
      src_hash: src_hash,
      payload: payload
    }}
  end

  defp decode_message(_), do: {:error, :invalid_format}

  # Compact encoding for small payloads (simplified MessagePack-like)
  defp compact_encode(data) when is_map(data) and map_size(data) == 0, do: {:ok, <<>>}

  defp compact_encode(data) when is_map(data) do
    # Simple approach: JSON but shorter keys
    try do
      json = Jason.encode!(data)
      {:ok, json}
    rescue
      _ -> {:error, "encode_failed"}
    end
  end

  defp compact_encode(data) when is_binary(data), do: {:ok, data}
  defp compact_encode(_), do: {:error, "unsupported_type"}

  defp compact_decode(<<>>), do: %{}

  defp compact_decode(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> %{raw: data}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Broadcasting
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp broadcast_message(message) do
    encoded = encode_message(message)

    # Send via Bluetooth module's advertising
    # This piggybacks on existing BLE infrastructure
    if Code.ensure_loaded?(AiReality2Transnet.Bluetooth) do
      AiReality2Transnet.Bluetooth.broadcast_mesh_message(encoded)
    else
      Logger.warning("#{log_prefix()} Bluetooth module not available")
    end
  end

  defp announce_presence do
    node_id = Reality2.Bootstrap.get(:node_id)
    src_hash = hash16(node_id)

    # Get local Sentant count and hashes
    sentant_hashes = case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} ->
        sentants
        |> Enum.map(fn s -> Map.get(s, :name, "") end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.take(7)  # Max 7 sentants in presence (14 bytes)
        |> Enum.map(&hash16/1)

      _ -> []
    end

    # Payload: [count:1][sentant_hashes:2*count]
    count = length(sentant_hashes)
    hashes_bin = sentant_hashes
      |> Enum.map(fn h -> <<h::16>> end)
      |> Enum.join()

    payload = <<count::8>> <> hashes_bin

    message = %{
      msg_id: generate_msg_id(),
      ttl: @default_ttl,
      type: @msg_type_presence,
      src_hash: src_hash,
      payload: payload
    }

    broadcast_message(message)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Utilities
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp generate_msg_id do
    :rand.uniform(0xFFFF)
  end

  defp hash16(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(5381, fn byte, hash ->
      rem((hash * 33) + byte, 0x100000000)
    end)
    |> Bitwise.band(0xFFFF)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_seen, @seen_cache_cleanup_ms)
  end

  defp schedule_presence do
    Process.send_after(self(), :announce_presence, @presence_interval_ms)
  end
end
