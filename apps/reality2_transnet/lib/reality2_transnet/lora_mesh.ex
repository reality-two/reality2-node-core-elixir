defmodule Reality2Transnet.LoRaMesh do
  @moduledoc """
  LoRa Mesh - Long-range mesh communication for Sentants.

  Optional module that provides LoRa mesh networking when hardware is available.
  Follows the same API pattern as R2Mesh for consistency.

  ## Hardware Support

  Works with common USB LoRa dongles/modules:
  - RAK RAK2287 / RAK811
  - Adafruit RFM95W (via USB-serial adapter)
  - LILYGO TTGO LoRa32
  - Heltec WiFi LoRa 32
  - Any module supporting AT commands or serial protocol

  ## Characteristics

  | Property | Value |
  |----------|-------|
  | Range | 2-15 km (line of sight) |
  | Bandwidth | 0.3-50 kbps |
  | Max Payload | ~200 bytes (conservative) |
  | Power | Medium (TX bursts) |
  | Best For | Rural, outdoor, sparse networks |

  ## Message Format

  Compatible with R2Mesh format for easy bridging:

  ```
  ┌────────────────────────────────────────────────────┐
  │  [msg_id:2][ttl:1][type:1][src_hash:2][payload:N]  │
  │                                                    │
  │  Total: 6 + N bytes (N ≤ 200)                      │
  └────────────────────────────────────────────────────┘
  ```

  ## Usage

  ```elixir
  # Check if LoRa is available
  LoRaMesh.available?()

  # Broadcast event (same API as R2Mesh)
  LoRaMesh.broadcast_event("sensor_1", "reading", %{temp: 23, humidity: 65})

  # Send signal to specific Sentant
  LoRaMesh.send_signal("source", "target", "alert", %{level: "high"})

  # Check if data fits in LoRa payload
  LoRaMesh.fits?(%{large: "data"})  # => true (more room than BLE)
  ```

  ## Configuration

  Set via application config or environment:

  ```elixir
  config :reality2_transnet, :lora,
    enabled: true,
    port: "/dev/ttyUSB0",  # or auto-detect
    baud: 115200,
    spreading_factor: 7,   # 7-12 (higher = longer range, slower)
    bandwidth: 125,        # kHz
    tx_power: 14           # dBm
  ```

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  # Helper to get node name for log messages
  defp log_prefix, do: "[LoRaMesh:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Constants
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Message types (same as R2Mesh for compatibility)
  @msg_type_event 0x01
  @msg_type_signal 0x02
  @msg_type_presence 0x03

  # Protocol settings
  @default_ttl 7                    # LoRa can travel further, higher TTL
  @max_payload_size 200             # Conservative for reliability
  @seen_cache_ttl_ms 120_000        # 2 minutes (LoRa is slower)
  @seen_cache_cleanup_ms 30_000     # Cleanup interval
  @presence_interval_ms 300_000     # 5 minutes (preserve airtime)
  @tx_delay_min_ms 100              # Minimum delay between transmissions
  @tx_delay_max_ms 500              # Random backoff max

  # Serial communication
  @default_baud 115200
  @serial_timeout_ms 5000

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Types
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc "LoRa Mesh message"
  @type lora_message :: %{
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
  Checks if LoRa hardware is available and initialized.

  ## Returns
  - `true` - LoRa is ready
  - `false` - No LoRa hardware or not initialized
  """
  @spec available?() :: boolean()
  def available? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, :available?)
    end
  catch
    :exit, _ -> false
  end

  @doc """
  Broadcasts a Sentant event via LoRa mesh.

  Same API as R2Mesh.broadcast_event/3 for consistency.

  ## Parameters
  - `sentant_id` - Source Sentant identifier
  - `event_name` - Event name
  - `params` - Event parameters (max ~190 bytes encoded)

  ## Returns
  - `:ok` - Message queued for broadcast
  - `{:error, :not_available}` - LoRa not initialized
  - `{:error, :payload_too_large}` - Data exceeds max size
  """
  @spec broadcast_event(String.t(), String.t(), map()) :: :ok | {:error, atom() | String.t()}
  def broadcast_event(sentant_id, event_name, params \\ %{}) do
    if available?() do
      GenServer.call(__MODULE__, {:broadcast_event, sentant_id, event_name, params})
    else
      {:error, :not_available}
    end
  end

  @doc """
  Sends a signal to a specific Sentant via LoRa mesh.

  Same API as R2Mesh.send_signal/4 for consistency.

  ## Parameters
  - `source_sentant` - Source Sentant ID
  - `target_sentant` - Target Sentant ID
  - `signal_name` - Signal name
  - `params` - Signal parameters

  ## Returns
  - `:ok` - Message queued
  - `{:error, reason}` - Failed
  """
  @spec send_signal(String.t(), String.t(), String.t(), map()) :: :ok | {:error, atom() | String.t()}
  def send_signal(source_sentant, target_sentant, signal_name, params \\ %{}) do
    if available?() do
      GenServer.call(__MODULE__, {:send_signal, source_sentant, target_sentant, signal_name, params})
    else
      {:error, :not_available}
    end
  end

  @doc """
  Handles an incoming LoRa mesh message.

  Called by the serial receiver when a message arrives.

  ## Parameters
  - `raw_data` - Raw message bytes from LoRa radio

  ## Returns
  - `:ok`
  """
  @spec handle_incoming(binary()) :: :ok
  def handle_incoming(raw_data) do
    if available?() do
      GenServer.cast(__MODULE__, {:incoming, raw_data})
    end
    :ok
  end

  @doc """
  Sends raw binary data via LoRa (used by LoRaTransport adapter).

  The data should already be in the correct wire format.

  ## Parameters
  - `data` - Pre-encoded binary data

  ## Returns
  - `:ok` - Queued for transmission
  - `{:error, reason}` - Failed
  """
  @spec send_raw(binary()) :: :ok | {:error, term()}
  def send_raw(data) when is_binary(data) do
    if available?() do
      GenServer.call(__MODULE__, {:send_raw, data})
    else
      {:error, :not_available}
    end
  end

  @doc """
  Gets LoRa mesh statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    if available?() do
      GenServer.call(__MODULE__, :get_stats)
    else
      %{available: false}
    end
  end

  @doc """
  Checks if data fits in LoRa mesh payload.

  LoRa has more room than BLE (~200 bytes vs ~18 bytes).

  ## Parameters
  - `data` - Data to check

  ## Returns
  - `true` - Fits in LoRa payload
  - `false` - Too large
  """
  @spec fits?(term()) :: boolean()
  def fits?(data) when is_map(data) do
    case Jason.encode(data) do
      {:ok, encoded} -> byte_size(encoded) <= @max_payload_size - 6  # Header overhead
      _ -> false
    end
  end

  def fits?(data) when is_binary(data), do: byte_size(data) <= @max_payload_size - 6
  def fits?(_), do: false

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    # Check if LoRa is enabled in config
    lora_config = Application.get_env(:reality2_transnet, :lora, [])
    enabled = Keyword.get(lora_config, :enabled, true)

    if enabled do
      # Try to detect and initialize LoRa hardware
      case detect_lora_hardware(opts) do
        {:ok, port_info} ->
          state = %{
            port: port_info.port,
            port_pid: port_info.pid,
            available: true,
            seen: %{},
            stats: %{
              messages_sent: 0,
              messages_received: 0,
              messages_relayed: 0,
              messages_dropped_seen: 0,
              messages_dropped_ttl: 0,
              tx_errors: 0,
              rx_errors: 0
            },
            last_tx: 0,
            config: port_info.config
          }

          schedule_cleanup()
          schedule_presence()

          Logger.info("#{log_prefix()} Initialized on #{port_info.port}")
          {:ok, state}

        {:error, reason} ->
          Logger.info("#{log_prefix()} No LoRa hardware detected: #{inspect(reason)} - running without LoRa")
          {:ok, %{available: false, stats: %{available: false}}}
      end
    else
      Logger.info("#{log_prefix()} Disabled by configuration")
      {:ok, %{available: false, stats: %{available: false}}}
    end
  end

  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, Map.get(state, :available, false), state}
  end

  @impl true
  def handle_call({:broadcast_event, sentant_id, event_name, params}, _from, state) do
    if state.available do
      msg_id = generate_msg_id()
      src_hash = hash16(sentant_id)
      event_hash = hash16(event_name)

      case Jason.encode(params) do
        {:ok, params_json} when byte_size(params_json) <= @max_payload_size - 8 ->
          # Payload: [event_hash:2][params_json]
          payload = <<event_hash::16>> <> params_json

          message = %{
            msg_id: msg_id,
            ttl: @default_ttl,
            type: @msg_type_event,
            src_hash: src_hash,
            payload: payload
          }

          # Mark as seen
          new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))

          # Transmit with backoff
          case transmit_with_backoff(message, state) do
            {:ok, new_state} ->
              new_stats = Map.update!(new_state.stats, :messages_sent, &(&1 + 1))
              {:reply, :ok, %{new_state | seen: new_seen, stats: new_stats}}

            {:error, reason} ->
              new_stats = Map.update!(state.stats, :tx_errors, &(&1 + 1))
              {:reply, {:error, reason}, %{state | stats: new_stats}}
          end

        {:ok, _} ->
          {:reply, {:error, :payload_too_large}, state}

        {:error, _} ->
          {:reply, {:error, :encode_failed}, state}
      end
    else
      {:reply, {:error, :not_available}, state}
    end
  end

  @impl true
  def handle_call({:send_signal, source, target, signal_name, params}, _from, state) do
    if state.available do
      msg_id = generate_msg_id()
      src_hash = hash16(source)
      target_hash = hash16(target)
      signal_hash = hash16(signal_name)

      case Jason.encode(params) do
        {:ok, params_json} when byte_size(params_json) <= @max_payload_size - 12 ->
          # Payload: [target_hash:2][signal_hash:2][params_json]
          payload = <<target_hash::16, signal_hash::16>> <> params_json

          message = %{
            msg_id: msg_id,
            ttl: @default_ttl,
            type: @msg_type_signal,
            src_hash: src_hash,
            payload: payload
          }

          new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))

          case transmit_with_backoff(message, state) do
            {:ok, new_state} ->
              new_stats = Map.update!(new_state.stats, :messages_sent, &(&1 + 1))
              {:reply, :ok, %{new_state | seen: new_seen, stats: new_stats}}

            {:error, reason} ->
              new_stats = Map.update!(state.stats, :tx_errors, &(&1 + 1))
              {:reply, {:error, reason}, %{state | stats: new_stats}}
          end

        {:ok, _} ->
          {:reply, {:error, :payload_too_large}, state}

        {:error, _} ->
          {:reply, {:error, :encode_failed}, state}
      end
    else
      {:reply, {:error, :not_available}, state}
    end
  end

  @impl true
  def handle_call({:send_raw, data}, _from, state) do
    if state.available do
      case transmit_raw(data, state) do
        :ok ->
          new_stats = Map.update!(state.stats, :messages_sent, &(&1 + 1))
          {:reply, :ok, %{state | stats: new_stats, last_tx: System.system_time(:millisecond)}}

        {:error, reason} ->
          new_stats = Map.update!(state.stats, :tx_errors, &(&1 + 1))
          {:reply, {:error, reason}, %{state | stats: new_stats}}
      end
    else
      {:reply, {:error, :not_available}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      available: state.available,
      seen_cache_size: map_size(Map.get(state, :seen, %{}))
    })
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:incoming, raw_data}, state) do
    if state.available do
      case decode_message(raw_data) do
        {:ok, message} ->
          handle_lora_message(message, state)

        {:error, _reason} ->
          new_stats = Map.update!(state.stats, :rx_errors, &(&1 + 1))
          {:noreply, %{state | stats: new_stats}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_seen, state) do
    if state.available do
      now = System.system_time(:millisecond)
      cutoff = now - @seen_cache_ttl_ms

      new_seen = state.seen
        |> Enum.filter(fn {_id, ts} -> ts > cutoff end)
        |> Map.new()

      schedule_cleanup()
      {:noreply, %{state | seen: new_seen}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:announce_presence, state) do
    if state.available do
      announce_presence(state)
      schedule_presence()
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:relay, message}, state) do
    if state.available do
      case transmit_with_backoff(message, state) do
        {:ok, new_state} ->
          new_stats = Map.update!(new_state.stats, :messages_relayed, &(&1 + 1))
          {:noreply, %{new_state | stats: new_stats}}

        {:error, _reason} ->
          new_stats = Map.update!(state.stats, :tx_errors, &(&1 + 1))
          {:noreply, %{state | stats: new_stats}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:serial, _port, data}, state) do
    # Data received from serial port
    handle_incoming(data)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("#{log_prefix()} Unhandled: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Hardware Detection
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp detect_lora_hardware(opts) do
    lora_config = Application.get_env(:reality2_transnet, :lora, [])

    # Check for explicit port configuration
    configured_port = Keyword.get(opts, :port) || Keyword.get(lora_config, :port)

    port = if configured_port do
      configured_port
    else
      # Auto-detect common LoRa USB devices
      detect_lora_port()
    end

    case port do
      nil ->
        {:error, :no_device_found}

      port_path ->
        # Try to open and verify it's a LoRa device
        baud = Keyword.get(lora_config, :baud, @default_baud)

        case open_serial_port(port_path, baud) do
          {:ok, pid} ->
            config = %{
              spreading_factor: Keyword.get(lora_config, :spreading_factor, 7),
              bandwidth: Keyword.get(lora_config, :bandwidth, 125),
              tx_power: Keyword.get(lora_config, :tx_power, 14)
            }

            {:ok, %{port: port_path, pid: pid, config: config}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp detect_lora_port do
    # Common LoRa USB device paths
    candidates = [
      "/dev/ttyUSB0",
      "/dev/ttyUSB1",
      "/dev/ttyACM0",
      "/dev/ttyACM1",
      "/dev/serial/by-id/*LoRa*",
      "/dev/serial/by-id/*RAK*",
      "/dev/serial/by-id/*Heltec*"
    ]

    # Check which ports exist
    candidates
    |> Enum.flat_map(fn pattern ->
      if String.contains?(pattern, "*") do
        Path.wildcard(pattern)
      else
        if File.exists?(pattern), do: [pattern], else: []
      end
    end)
    |> List.first()
  end

  defp open_serial_port(port_path, baud) do
    # Check if Circuits.UART is available
    if Code.ensure_loaded?(Circuits.UART) do
      case Circuits.UART.start_link() do
        {:ok, pid} ->
          case Circuits.UART.open(pid, port_path, speed: baud, active: true) do
            :ok ->
              # Try to verify it's a LoRa device (send AT command)
              Circuits.UART.write(pid, "AT\r\n")

              receive do
                {:circuits_uart, ^port_path, "OK" <> _} ->
                  {:ok, pid}
                {:circuits_uart, ^port_path, _other} ->
                  # Some response - assume it's working
                  {:ok, pid}
              after
                @serial_timeout_ms ->
                  # No response - might still work, some devices don't use AT commands
                  Logger.warning("#{log_prefix()} No AT response from #{port_path}, assuming raw mode")
                  {:ok, pid}
              end

            {:error, reason} ->
              Circuits.UART.stop(pid)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Circuits.UART not available - LoRa disabled
      {:error, :circuits_uart_not_available}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Message Handling
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp handle_lora_message(message, state) do
    msg_id = message.msg_id

    if Map.has_key?(state.seen, msg_id) do
      new_stats = Map.update!(state.stats, :messages_dropped_seen, &(&1 + 1))
      {:noreply, %{state | stats: new_stats}}
    else
      # Mark as seen
      new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))
      new_stats = Map.update!(state.stats, :messages_received, &(&1 + 1))

      # Deliver locally
      deliver_locally(message)

      # Also forward to R2Mesh/BLE for local delivery (bridge between transports)
      bridge_to_ble(message)

      # Relay if TTL > 1
      if message.ttl > 1 do
        relay_message = %{message | ttl: message.ttl - 1}
        # Random delay to reduce collisions (longer for LoRa due to airtime)
        delay = @tx_delay_min_ms + :rand.uniform(@tx_delay_max_ms)
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
        handle_presence(message)
        Logger.debug("#{log_prefix()} Presence from 0x#{Integer.to_string(message.src_hash, 16)}")

      _ ->
        Logger.debug("#{log_prefix()} Unknown message type: #{message.type}")
    end
  end

  defp deliver_event(message) do
    case message.payload do
      <<event_hash::16, params_json::binary>> ->
        params = case Jason.decode(params_json) do
          {:ok, p} -> p
          _ -> %{raw: params_json}
        end

        Reality2.Sentants.sendto_all(%{
          event: "__lora_mesh_event",
          parameters: %{
            src_hash: message.src_hash,
            event_hash: event_hash,
            params: params,
            ttl: message.ttl,
            transport: :lora_mesh
          }
        })

      _ ->
        Logger.warning("#{log_prefix()} Malformed event payload")
    end
  end

  defp deliver_signal(message) do
    case message.payload do
      <<target_hash::16, signal_hash::16, params_json::binary>> ->
        params = case Jason.decode(params_json) do
          {:ok, p} -> p
          _ -> %{raw: params_json}
        end

        Reality2.Sentants.sendto_all(%{
          event: "__lora_mesh_signal",
          parameters: %{
            src_hash: message.src_hash,
            target_hash: target_hash,
            signal_hash: signal_hash,
            params: params,
            ttl: message.ttl,
            transport: :lora_mesh
          }
        })

      _ ->
        Logger.warning("#{log_prefix()} Malformed signal payload")
    end
  end

  # Handle incoming presence: update reachability via PeerManager and HiveDirectory
  defp handle_presence(message) do
    # Try to decode the new presence format
    if Code.ensure_loaded?(Reality2Transnet.Transports.LoRaTransport) do
      case Reality2Transnet.Transports.LoRaTransport.decode_presence(message.payload) do
        {:ok, presence} ->
          # Try to resolve compressed source ID to full UUID
          src_node_id = resolve_lora_source(message)

          # Update PeerManager reachability for LoRa
          if Code.ensure_loaded?(Reality2Transnet.PeerManager) and src_node_id != nil do
            Reality2Transnet.PeerManager.update_reachability(src_node_id, :lora, %{
              confidence: 120,
              hive_compressed: Map.get(presence, :hive_compressed),
              dir_version: Map.get(presence, :dir_version, 0)
            })
          end

          # Update HiveDirectory reachability
          if Code.ensure_loaded?(Reality2Transnet.HiveDirectory) and
             Process.whereis(Reality2Transnet.HiveDirectory) != nil and
             src_node_id != nil do
            Reality2Transnet.HiveDirectory.update_reachability(src_node_id, :lora, %{
              confidence: 120
            })
          end

        {:error, _} ->
          :ok
      end
    end
  end

  # Resolve LoRa source to full UUID (via compressed ID lookup or hash)
  defp resolve_lora_source(message) do
    cond do
      # New format: message may have src_compressed field
      is_map_key(message, :src_compressed) and is_binary(message.src_compressed) ->
        if Code.ensure_loaded?(Reality2Transnet.HiveDirectory) and
           Process.whereis(Reality2Transnet.HiveDirectory) != nil do
          case Reality2Transnet.HiveDirectory.resolve_compressed_id(message.src_compressed) do
            {:ok, node_id} -> node_id
            _ -> nil
          end
        else
          nil
        end

      # Legacy: src_hash is a 16-bit hash, can't reliably resolve
      true ->
        nil
    end
  end

  # Bridge LoRa messages to BLE mesh for local delivery
  defp bridge_to_ble(message) do
    if Code.ensure_loaded?(Reality2Transnet.R2Mesh) do
      # Re-encode for BLE (may need to truncate if too large)
      if byte_size(message.payload) <= 18 do
        encoded = encode_message(message)
        Reality2Transnet.R2Mesh.handle_incoming(encoded)
      end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Transmission
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp transmit_with_backoff(message, state) do
    now = System.system_time(:millisecond)
    time_since_last = now - state.last_tx

    # Enforce minimum delay between transmissions
    if time_since_last < @tx_delay_min_ms do
      Process.sleep(@tx_delay_min_ms - time_since_last)
    end

    encoded = encode_message(message)

    case transmit_raw(encoded, state) do
      :ok ->
        {:ok, %{state | last_tx: System.system_time(:millisecond)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transmit_raw(data, state) do
    if state.available and state.port_pid do
      # Send via serial port
      # Format depends on LoRa module - this assumes raw binary mode
      # Some modules need AT commands: AT+SEND=<len>,<data>
      if Code.ensure_loaded?(Circuits.UART) do
        Circuits.UART.write(state.port_pid, data)
      else
        {:error, :no_uart}
      end
    else
      {:error, :not_available}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Encoding/Decoding
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

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Presence
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp announce_presence(state) do
    node_id = Reality2.Bootstrap.get(:node_id)
    node_name = Reality2.Bootstrap.get(:node_name, "unknown")

    # Use compressed ID from HiveIdentity
    _src_compressed = if Code.ensure_loaded?(Reality2Transnet.HiveIdentity) do
      Reality2Transnet.HiveIdentity.compressed_id(node_id)
    else
      hash16_to_binary(hash16(node_id))
    end

    # Get hive compressed ID
    hive_compressed = if Code.ensure_loaded?(Reality2Transnet.HiveIdentity) do
      case Reality2Transnet.HiveIdentity.get_hive_compressed_id() do
        {:ok, cid} -> cid
        _ -> <<0, 0, 0, 0>>
      end
    else
      <<0, 0, 0, 0>>
    end

    # Get sentant count
    sentant_count = case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} -> min(length(sentants), 255)
      _ -> 0
    end

    # Get directory version
    dir_version = if Code.ensure_loaded?(Reality2Transnet.HiveDirectory) and
                     Process.whereis(Reality2Transnet.HiveDirectory) != nil do
      Reality2Transnet.HiveDirectory.get_version()
    else
      0
    end

    # Build presence payload using the new format
    presence_info = %{
      hive_compressed: hive_compressed,
      capabilities: %{has_wifi: true, has_ble: true, is_relay: true},
      sentant_count: sentant_count,
      hosting_priority: 0,
      node_name_hash: hash16(node_name),
      cell_hint: 0,
      dir_version: dir_version,
      energy_state: 255,
      backlog_count: 0
    }

    presence_payload = if Code.ensure_loaded?(Reality2Transnet.Transports.LoRaTransport) do
      Reality2Transnet.Transports.LoRaTransport.encode_presence(presence_info)
    else
      <<sentant_count::16>>
    end

    # Use new 8-byte header format if LoRaTransport is available
    encoded = if Code.ensure_loaded?(Reality2Transnet.Transports.LoRaTransport) do
      Reality2Transnet.Transports.LoRaTransport.encode_message(%{
        msg_id: generate_msg_id(),
        ttl: @default_ttl,
        type: :presence,
        src_node_id: node_id,
        payload: presence_payload
      })
    else
      # Legacy format
      msg_id = generate_msg_id()
      src_hash = hash16(node_id)
      <<msg_id::16, @default_ttl::8, @msg_type_presence::8, src_hash::16, presence_payload::binary>>
    end

    transmit_raw(encoded, state)
  end

  defp hash16_to_binary(hash) do
    <<hash::32>>
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
