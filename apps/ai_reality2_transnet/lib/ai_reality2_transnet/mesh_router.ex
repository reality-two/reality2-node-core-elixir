defmodule AiReality2Transnet.MeshRouter do
  @moduledoc """
  Transport-agnostic mesh message router for Reality2.

  The MeshRouter is the central coordinator for mesh communication. It:
  - Routes messages through available transports
  - Handles message deduplication
  - Bridges between transports (BLE ↔ WiFi ↔ LoRa)
  - Delivers messages to local Sentants

  ## Transport Hierarchy

  **BLE beacons are the CORE discovery mechanism.** All other transports
  (WiFi, LoRa) are data layers that activate after BLE discovery.

  ```
                        ┌─────────────────┐
                        │   Reality2      │
                        │   Sentants      │
                        └────────┬────────┘
                                 │
                        ┌────────▼────────┐
                        │   MeshRouter    │  <- Transport-agnostic
                        │  (This module)  │     message routing
                        └────────┬────────┘
                                 │
        ═════════════════════════╪════════════════════════════
        ║  DISCOVERY LAYER (always on, low power)            ║
        ║                        │                           ║
        ║              ┌─────────▼─────────┐                 ║
        ║              │   BLE Beacons     │  <- CORE        ║
        ║              │   (Bluetooth.ex)  │     Always-on   ║
        ║              └─────────┬─────────┘     Discovery   ║
        ═════════════════════════╪════════════════════════════
                                 │
                    ┌────────────┴────────────┐
                    │ Peer discovered via BLE │
                    └────────────┬────────────┘
                                 │
        ═════════════════════════╪════════════════════════════
        ║  DATA LAYER (activated after BLE discovery)        ║
        ║            ┌───────────┴───────────┐               ║
        ║            │                       │               ║
        ║  ┌─────────▼─────────┐   ┌─────────▼─────────┐     ║
        ║  │  WiFi Hotspot     │   │  LoRa Mesh        │     ║
        ║  │  (ConnectionMgr)  │   │  (LoRaMesh.ex)    │     ║
        ║  │  High bandwidth   │   │  Long range       │     ║
        ║  └───────────────────┘   └───────────────────┘     ║
        ═════════════════════════════════════════════════════
  ```

  ## Lifecycle

  1. **BLE Discovery** (always running)
     - Beacons broadcast node_id, node_name, hosting_priority
     - PeerManager tracks discovered peers

  2. **Transport Upgrade** (triggered by ConnectionAssessor)
     - BLE discovery triggers WiFi hotspot connection
     - Or: LoRa used for long-range scenarios

  3. **Data Exchange** (via upgraded transport)
     - Sentant exchange via GraphQL over WiFi
     - Small messages can still use BLE
     - Long-range messages use LoRa

  ## Message Types

  - `:event` - Broadcast to all Sentants
  - `:signal` - Directed to specific Sentant
  - `:presence` - Node/Sentant announcement
  - `:data` - Large data transfer (WiFi only)

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  alias AiReality2Transnet.Transport

  # Helper to get node name for log messages
  defp log_prefix, do: "[MeshRouter:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Constants
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @default_ttl 5
  @seen_cache_ttl_ms 60_000       # Forget seen messages after 60s
  @seen_cache_cleanup_ms 15_000   # Cleanup interval
  @presence_interval_ms 120_000   # Announce presence every 2 minutes

  # Registered transports (order matters for selection)
  @transport_modules [
    AiReality2Transnet.Transports.WiFiTransport,
    AiReality2Transnet.Transports.LoRaTransport,
    AiReality2Transnet.Transports.BLETransport
  ]

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Broadcasts a Sentant event to the mesh.

  Automatically selects the best transport based on payload size.
  Small payloads use BLE, larger ones use WiFi or LoRa.

  ## Parameters
  - `sentant_id` - Source Sentant identifier
  - `event_name` - Event name
  - `params` - Event parameters

  ## Returns
  - `:ok` - Message queued
  - `{:error, reason}` - Failed
  """
  @spec broadcast_event(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def broadcast_event(sentant_id, event_name, params \\ %{}) do
    GenServer.call(__MODULE__, {:broadcast_event, sentant_id, event_name, params})
  end

  @doc """
  Sends a signal to a specific Sentant via mesh.

  ## Parameters
  - `source_sentant` - Source Sentant ID
  - `target_sentant` - Target Sentant ID (or "node|sentant")
  - `signal_name` - Signal name
  - `params` - Signal parameters

  ## Returns
  - `:ok` - Message queued
  - `{:error, reason}` - Failed
  """
  @spec send_signal(String.t(), String.t(), String.t(), map()) :: :ok | {:error, term()}
  def send_signal(source_sentant, target_sentant, signal_name, params \\ %{}) do
    GenServer.call(__MODULE__, {:send_signal, source_sentant, target_sentant, signal_name, params})
  end

  @doc """
  Handles an incoming mesh message from any transport.

  Called by transport modules when they receive a message.

  ## Parameters
  - `message` - Decoded mesh message
  - `transport` - Transport type atom (:ble, :wifi, :lora)

  ## Returns
  - `:ok`
  """
  @spec handle_incoming(Transport.mesh_message(), atom()) :: :ok
  def handle_incoming(message, transport) do
    GenServer.cast(__MODULE__, {:incoming, message, transport})
  end

  @doc """
  Gets mesh router statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Lists available transports and their status.
  """
  @spec list_transports() :: [map()]
  def list_transports do
    GenServer.call(__MODULE__, :list_transports)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Schedule cleanup and presence
    schedule_cleanup()
    schedule_presence()

    state = %{
      # Seen message cache for deduplication
      seen: %{},
      # Statistics
      stats: %{
        messages_sent: 0,
        messages_received: 0,
        messages_relayed: 0,
        messages_dropped_seen: 0,
        messages_dropped_ttl: 0,
        messages_delivered: 0,
        transport_sends: %{}
      },
      # Cache of transport availability
      transports: refresh_transports()
    }

    Logger.info("#{log_prefix()} Started - transport-agnostic mesh router")
    {:ok, state}
  end

  @impl true
  def handle_call({:broadcast_event, sentant_id, event_name, params}, _from, state) do
    my_node_id = Reality2.Bootstrap.get(:node_id)
    msg_id = generate_msg_id()

    message = %{
      msg_id: msg_id,
      ttl: @default_ttl,
      type: :event,
      src_node_id: my_node_id,
      payload: encode_event_payload(sentant_id, event_name, params)
    }

    # Mark as seen
    new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))

    # Broadcast via all suitable transports
    {results, new_stats} = broadcast_via_transports(message, state.stats, state.transports)

    case results do
      [] ->
        {:reply, {:error, :no_transports_available}, %{state | seen: new_seen, stats: new_stats}}

      _ ->
        {:reply, :ok, %{state | seen: new_seen, stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:send_signal, source, target, signal_name, params}, _from, state) do
    my_node_id = Reality2.Bootstrap.get(:node_id)
    msg_id = generate_msg_id()

    message = %{
      msg_id: msg_id,
      ttl: @default_ttl,
      type: :signal,
      src_node_id: my_node_id,
      payload: encode_signal_payload(source, target, signal_name, params)
    }

    new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))

    # Check if target is local
    if is_local_sentant?(target) do
      deliver_signal_locally(message)
      new_stats = Map.update!(state.stats, :messages_delivered, &(&1 + 1))
      {:reply, :ok, %{state | seen: new_seen, stats: new_stats}}
    else
      # Broadcast to mesh
      {results, new_stats} = broadcast_via_transports(message, state.stats, state.transports)

      case results do
        [] ->
          {:reply, {:error, :no_transports_available}, %{state | seen: new_seen, stats: new_stats}}

        _ ->
          {:reply, :ok, %{state | seen: new_seen, stats: new_stats}}
      end
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      seen_cache_size: map_size(state.seen),
      transports_available: length(Enum.filter(state.transports, fn {_mod, info} -> info.available end))
    })
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_transports, _from, state) do
    transport_list = Enum.map(state.transports, fn {mod, info} ->
      %{
        type: info.type,
        module: mod,
        available: info.available,
        max_payload: info.max_payload,
        capabilities: info.capabilities
      }
    end)
    {:reply, transport_list, state}
  end

  @impl true
  def handle_cast({:incoming, message, transport}, state) do
    msg_id = message.msg_id

    # Check if already seen
    if Map.has_key?(state.seen, msg_id) do
      new_stats = Map.update!(state.stats, :messages_dropped_seen, &(&1 + 1))
      {:noreply, %{state | stats: new_stats}}
    else
      # Mark as seen
      new_seen = Map.put(state.seen, msg_id, System.system_time(:millisecond))
      new_stats = Map.update!(state.stats, :messages_received, &(&1 + 1))

      # Deliver locally
      deliver_locally(message)
      new_stats = Map.update!(new_stats, :messages_delivered, &(&1 + 1))

      # Relay to other transports if TTL > 1 (bridge between transports)
      new_stats = if message.ttl > 1 do
        relay_message = %{message | ttl: message.ttl - 1}
        relay_to_other_transports(relay_message, transport, state.transports)
        Map.update!(new_stats, :messages_relayed, &(&1 + 1))
      else
        Map.update!(new_stats, :messages_dropped_ttl, &(&1 + 1))
        new_stats
      end

      {:noreply, %{state | seen: new_seen, stats: new_stats}}
    end
  end

  @impl true
  def handle_info(:cleanup_seen, state) do
    now = System.system_time(:millisecond)
    cutoff = now - @seen_cache_ttl_ms

    new_seen = state.seen
      |> Enum.filter(fn {_id, ts} -> ts > cutoff end)
      |> Map.new()

    # Also refresh transport availability
    new_transports = refresh_transports()

    schedule_cleanup()
    {:noreply, %{state | seen: new_seen, transports: new_transports}}
  end

  @impl true
  def handle_info(:announce_presence, state) do
    announce_presence(state.transports)
    schedule_presence()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("#{log_prefix()} Unhandled: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Transport Management
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp refresh_transports do
    @transport_modules
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.map(fn mod ->
      info = try do
        %{
          type: mod.transport_type(),
          available: mod.available?(),
          max_payload: mod.max_payload_size(),
          capabilities: mod.capabilities()
        }
      rescue
        _ -> %{type: :unknown, available: false, max_payload: 0, capabilities: %{}}
      end
      {mod, info}
    end)
    |> Map.new()
  end

  defp broadcast_via_transports(message, stats, transports) do
    payload_size = byte_size(message.payload)

    # Get available transports that can handle this payload
    suitable = transports
      |> Enum.filter(fn {_mod, info} -> info.available and info.max_payload >= payload_size end)

    results = Enum.map(suitable, fn {mod, _info} ->
      try do
        result = mod.broadcast(message)
        {mod, result}
      rescue
        e -> {mod, {:error, Exception.message(e)}}
      end
    end)

    # Update per-transport stats
    new_stats = Enum.reduce(results, stats, fn {mod, result}, acc ->
      transport_type = Map.get(transports[mod] || %{}, :type, :unknown)
      transport_key = transport_type

      case result do
        :ok ->
          transport_stats = Map.get(acc.transport_sends, transport_key, %{sent: 0, errors: 0})
          new_transport_stats = %{transport_stats | sent: transport_stats.sent + 1}
          put_in(acc, [:transport_sends, transport_key], new_transport_stats)

        {:error, _} ->
          transport_stats = Map.get(acc.transport_sends, transport_key, %{sent: 0, errors: 0})
          new_transport_stats = %{transport_stats | errors: transport_stats.errors + 1}
          put_in(acc, [:transport_sends, transport_key], new_transport_stats)
      end
    end)

    successful = Enum.filter(results, fn {_mod, result} -> result == :ok end)
    new_stats = if length(successful) > 0 do
      Map.update!(new_stats, :messages_sent, &(&1 + 1))
    else
      new_stats
    end

    {successful, new_stats}
  end

  defp relay_to_other_transports(message, source_transport, transports) do
    payload_size = byte_size(message.payload)

    # Relay to all OTHER available transports (bridge between transport types)
    transports
    |> Enum.filter(fn {_mod, info} ->
      info.available and
      info.max_payload >= payload_size and
      info.type != source_transport
    end)
    |> Enum.each(fn {mod, _info} ->
      try do
        mod.broadcast(message)
      rescue
        _ -> :ok
      end
    end)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Message Delivery
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp deliver_locally(message) do
    case message.type do
      :event -> deliver_event_locally(message)
      :signal -> deliver_signal_locally(message)
      :presence -> handle_presence(message)
      _ -> Logger.debug("#{log_prefix()} Unknown message type: #{message.type}")
    end
  end

  defp deliver_event_locally(message) do
    case decode_event_payload(message.payload) do
      {:ok, sentant_id, event_name, params} ->
        Reality2.Sentants.sendto_all(%{
          event: "__mesh_event",
          parameters: %{
            source_sentant: sentant_id,
            source_node: message.src_node_id,
            event: event_name,
            params: params,
            ttl: message.ttl
          }
        })

      {:error, _} ->
        Logger.warning("#{log_prefix()} Failed to decode event payload")
    end
  end

  defp deliver_signal_locally(message) do
    case decode_signal_payload(message.payload) do
      {:ok, source, target, signal_name, params} ->
        # Check if target is local and deliver directly
        if is_local_sentant?(target) do
          case Reality2.Sentants.read(%{name: target}, :definition) do
            {:ok, sentant} ->
              Reality2.Sentants.sendto(%{id: sentant.id}, %{
                event: "__mesh_signal",
                parameters: %{
                  source_sentant: source,
                  source_node: message.src_node_id,
                  signal: signal_name,
                  params: params
                }
              })

            _ ->
              Logger.debug("#{log_prefix()} Target sentant #{target} not found locally")
          end
        else
          # Broadcast to all - they can filter
          Reality2.Sentants.sendto_all(%{
            event: "__mesh_signal",
            parameters: %{
              source_sentant: source,
              source_node: message.src_node_id,
              target_sentant: target,
              signal: signal_name,
              params: params,
              ttl: message.ttl
            }
          })
        end

      {:error, _} ->
        Logger.warning("#{log_prefix()} Failed to decode signal payload")
    end
  end

  defp handle_presence(message) do
    # Presence messages announce node/sentant availability
    # Could update PeerManager here
    Logger.debug("#{log_prefix()} Presence from #{String.slice(message.src_node_id, 0..7)}...")
  end

  defp is_local_sentant?(sentant_name) do
    case Reality2.Sentants.read(%{name: sentant_name}, :definition) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Payload Encoding/Decoding
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp encode_event_payload(sentant_id, event_name, params) do
    Jason.encode!(%{
      sentant: sentant_id,
      event: event_name,
      params: params
    })
  end

  defp decode_event_payload(payload) do
    case Jason.decode(payload) do
      {:ok, %{"sentant" => s, "event" => e, "params" => p}} ->
        {:ok, s, e, p}
      {:ok, %{"sentant" => s, "event" => e}} ->
        {:ok, s, e, %{}}
      _ ->
        {:error, :invalid_format}
    end
  end

  defp encode_signal_payload(source, target, signal_name, params) do
    Jason.encode!(%{
      source: source,
      target: target,
      signal: signal_name,
      params: params
    })
  end

  defp decode_signal_payload(payload) do
    case Jason.decode(payload) do
      {:ok, %{"source" => s, "target" => t, "signal" => sig, "params" => p}} ->
        {:ok, s, t, sig, p}
      {:ok, %{"source" => s, "target" => t, "signal" => sig}} ->
        {:ok, s, t, sig, %{}}
      _ ->
        {:error, :invalid_format}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Presence Announcement
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp announce_presence(transports) do
    my_node_id = Reality2.Bootstrap.get(:node_id)
    my_node_name = Reality2.Bootstrap.get(:node_name)

    # Get local sentant names
    sentant_names = case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} -> Enum.map(sentants, fn s -> Map.get(s, :name, "") end)
      _ -> []
    end

    message = %{
      msg_id: generate_msg_id(),
      ttl: @default_ttl,
      type: :presence,
      src_node_id: my_node_id,
      payload: Jason.encode!(%{
        node_name: my_node_name,
        sentants: sentant_names
      })
    }

    # Broadcast via all available transports
    transports
    |> Enum.filter(fn {_mod, info} -> info.available end)
    |> Enum.each(fn {mod, _info} ->
      try do
        mod.broadcast(message)
      rescue
        _ -> :ok
      end
    end)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private - Utilities
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp generate_msg_id do
    :rand.uniform(0xFFFFFFFF)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_seen, @seen_cache_cleanup_ms)
  end

  defp schedule_presence do
    Process.send_after(self(), :announce_presence, @presence_interval_ms)
  end
end
