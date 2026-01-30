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
    AiReality2Transnet.Transports.InternetTransport,
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
      # Transport-aware routing (Gap 5 fix): prefer the target's known transport
      {results, new_stats} = route_to_target(message, target, state.stats, state.transports)

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

  # Transport-aware routing: prefer the target peer's known transport (Gap 5 fix)
  defp route_to_target(message, target, stats, transports) do
    # Extract node_id from target (format: "node|sentant" or just "sentant")
    target_node_id = case String.split(target, "|", parts: 2) do
      [node, _sentant] -> node
      [_sentant_only] -> nil
    end

    if target_node_id do
      # Try to find the best transport for this specific peer
      if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
        case AiReality2Transnet.PeerManager.best_transport(target_node_id) do
          {:ok, transport_type, _info} ->
            # Find the transport module matching this type
            case find_transport_module(transport_type, transports) do
              {:ok, mod} ->
                # Send via the preferred transport only
                send_via_single_transport(message, mod, stats, transports)

              {:error, _} ->
                # Transport module not available, fall back to broadcast
                broadcast_via_transports(message, stats, transports)
            end

          {:error, _} ->
            # Unknown peer — broadcast on all transports (discovery)
            broadcast_via_transports(message, stats, transports)
        end
      else
        broadcast_via_transports(message, stats, transports)
      end
    else
      # No node specified — broadcast
      broadcast_via_transports(message, stats, transports)
    end
  end

  defp find_transport_module(transport_type, transports) do
    # Map transport types to what the modules report
    type_mapping = %{
      wifi: :wifi_hotspot,
      wifi_hotspot: :wifi_hotspot,
      ble: :ble,
      ble_gatt: :ble,
      lora: :lora,
      internet: :internet
    }

    target_type = Map.get(type_mapping, transport_type, transport_type)

    case Enum.find(transports, fn {_mod, info} ->
      info.available and info.type == target_type
    end) do
      {mod, _info} -> {:ok, mod}
      nil -> {:error, :not_found}
    end
  end

  defp send_via_single_transport(message, mod, stats, transports) do
    payload_size = byte_size(message.payload)
    mod_info = Map.get(transports, mod, %{max_payload: 0})

    if mod_info.max_payload >= payload_size do
      result = try do
        mod.broadcast(message)
      rescue
        e -> {:error, Exception.message(e)}
      end

      transport_type = mod_info.type || :unknown
      new_stats = case result do
        :ok ->
          transport_stats = Map.get(stats.transport_sends, transport_type, %{sent: 0, errors: 0})
          new_ts = %{transport_stats | sent: transport_stats.sent + 1}
          stats
          |> put_in([:transport_sends, transport_type], new_ts)
          |> Map.update!(:messages_sent, &(&1 + 1))

        {:error, _} ->
          transport_stats = Map.get(stats.transport_sends, transport_type, %{sent: 0, errors: 0})
          new_ts = %{transport_stats | errors: transport_stats.errors + 1}
          put_in(stats, [:transport_sends, transport_type], new_ts)
      end

      successful = if result == :ok, do: [{mod, :ok}], else: []
      {successful, new_stats}
    else
      # Payload too large for preferred transport, broadcast to find one that fits
      broadcast_via_transports(message, stats, transports)
    end
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
        # Extract sentant name from node|sentant format
        sentant_name = case String.split(target, "|", parts: 2) do
          [_node, sentant] -> sentant
          [sentant] -> sentant
        end

        # Extract sender context from params (embedded by PNS Router as _sender)
        sender = case params do
          %{"_sender" => s} when is_map(s) ->
            %{
              sentant_name: Map.get(s, "sentant_name"),
              sentant_id: Map.get(s, "sentant_id"),
              node_id: Map.get(s, "node_id"),
              node_name: Map.get(s, "node_name")
            }
          _ -> nil
        end

        # Remove internal routing keys from params before delivery
        clean_params = params
          |> Map.delete("_sender")
          |> Map.delete("_passthrough")

        # Check if target is local and deliver directly
        if is_local_sentant?(target) do
          # Try by name first, then by UUID
          sentant_result = case Reality2.Sentants.read(%{name: sentant_name}, :definition) do
            {:ok, s} -> {:ok, s}
            _ -> Reality2.Sentants.read(%{id: sentant_name}, :definition)
          end

          case sentant_result do
            {:ok, sentant} ->
              # Deliver as the original signal event (not __mesh_signal) with sender context
              msg = %{
                event: signal_name,
                parameters: clean_params,
                passthrough: Map.get(params, "_passthrough") || %{},
                sender: sender
              }
              Reality2.Sentants.sendto(%{id: sentant.id}, msg)

            _ ->
              Logger.debug("#{log_prefix()} Target sentant #{sentant_name} not found locally")
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
              params: clean_params,
              ttl: message.ttl
            },
            sender: sender
          })
        end

      {:error, _} ->
        Logger.warning("#{log_prefix()} Failed to decode signal payload")
    end
  end

  defp handle_presence(message) do
    # Presence messages announce node/sentant availability
    case Jason.decode(message.payload) do
      {:ok, payload} ->
        node_id = message.src_node_id
        node_name = Map.get(payload, "node_name")

        Logger.debug("#{log_prefix()} Presence from #{String.slice(node_id, 0..7)}... (#{node_name || "unknown"})")

        # Register/update the peer in PeerManager
        sentants = Map.get(payload, "sentants", [])
        AiReality2Transnet.PeerManager.register_peer(node_id, %{
          node_name: node_name,
          sentants: sentants
        })

        # Update Hive info if present
        hive_id = Map.get(payload, "hive_id")
        if hive_id do
          hive_info = %{
            hive_id: hive_id,
            hive_public_key: Map.get(payload, "hive_public_key"),
            node_cert: Map.get(payload, "node_cert")
          }

          case AiReality2Transnet.PeerManager.update_peer_hive_info(node_id, hive_info) do
            :ok ->
              Logger.debug("#{log_prefix()} Updated Hive info for peer #{String.slice(node_id, 0..7)}... (Hive: #{String.slice(hive_id, 0..7)}...)")

            {:error, reason} ->
              Logger.warning("#{log_prefix()} Failed to update Hive info for #{String.slice(node_id, 0..7)}...: #{inspect(reason)}")
          end
        end

        # Register in HiveDirectory for hive-level addressing
        if Code.ensure_loaded?(AiReality2Transnet.HiveDirectory) and
           Process.whereis(AiReality2Transnet.HiveDirectory) != nil do
          sentant_entries = Enum.map(sentants, fn s ->
            %{
              id: (if is_map(s), do: Map.get(s, "id") || Map.get(s, :id), else: nil),
              name: (if is_binary(s), do: s, else: Map.get(s, "name") || Map.get(s, :name, ""))
            }
          end)

          AiReality2Transnet.HiveDirectory.register_node(node_id, %{
            name: node_name,
            sentants: sentant_entries,
            hive_id: hive_id
          })
        end

      {:error, _} ->
        Logger.warning("#{log_prefix()} Failed to decode presence payload from #{String.slice(message.src_node_id, 0..7)}...")
    end
  end

  defp is_local_sentant?(target) do
    # Handle node|sentant format
    {node_part, sentant_name} = case String.split(target, "|", parts: 2) do
      [node, sentant] -> {node, sentant}
      [sentant] -> {nil, sentant}
    end

    # If node is specified, check if it's us
    is_for_us = if node_part do
      my_node_id = Reality2.Bootstrap.get(:node_id)
      my_node_name = Reality2.Bootstrap.get(:node_name)
      node_part == my_node_id or node_part == my_node_name or node_part == "*"
    else
      true  # No node specified, could be local
    end

    # Check if we have this sentant
    if is_for_us do
      case Reality2.Sentants.read(%{name: sentant_name}, :definition) do
        {:ok, _} -> true
        _ ->
          # Try by UUID
          case Reality2.Sentants.read(%{id: sentant_name}, :definition) do
            {:ok, _} -> true
            _ -> false
          end
      end
    else
      false
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

    # Get local sentant info
    sentants_data = case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} -> sentants
      _ -> []
    end
    sentant_names = Enum.map(sentants_data, fn s -> Map.get(s, :name, "") end)

    # Update HiveDirectory with our current sentants
    if Code.ensure_loaded?(AiReality2Transnet.HiveDirectory) and
       Process.whereis(AiReality2Transnet.HiveDirectory) != nil do
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      sentant_entries = Enum.map(sentants_data, fn s ->
        %{
          id: Map.get(s, :id, ""),
          name: Map.get(s, :name, ""),
          updated_at: now
        }
      end)
      AiReality2Transnet.HiveDirectory.update_self(%{sentants: sentant_entries, name: my_node_name})
    end

    # Get Hive identity info
    hive_info = case AiReality2Transnet.HiveIdentity.get_identity() do
      {:ok, identity} ->
        %{
          hive_id: identity.hive_id,
          hive_name: identity.name,
          hive_public_key: Base.encode64(identity.public_key),
          hive_created_at: DateTime.to_iso8601(identity.created_at),
          hive_provisional: identity.provisional,
          node_cert: identity.node_cert  # nil for key holders, cert for members
        }
      _ ->
        %{}
    end

    message = %{
      msg_id: generate_msg_id(),
      ttl: @default_ttl,
      type: :presence,
      src_node_id: my_node_id,
      payload: Jason.encode!(Map.merge(%{
        node_name: my_node_name,
        sentants: sentant_names
      }, hive_info))
    }

    # Broadcast via non-LoRa transports only (Gap 9 fix)
    # LoRa presence is handled by LoRaMesh directly with its own binary format
    # to avoid duplicate announcements and wasted airtime
    transports
    |> Enum.filter(fn {_mod, info} -> info.available and info.type != :lora end)
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
