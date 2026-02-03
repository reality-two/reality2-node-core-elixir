defmodule AiReality2Transnet.BLEMesh do
  @moduledoc """
  BLE Mesh integration for scalable Sentant communication.

  This module provides BLE Mesh functionality for Reality2 Transient Networks,
  enabling low-power, scalable messaging between Sentants across many devices.

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │              Sentants + WFS Router                          │
  │         (transport agnostic - unchanged)                    │
  ├─────────────────────────────────────────────────────────────┤
  │                   BLEMesh GenServer                         │
  │  - Message encoding/decoding                                │
  │  - Address management (virtual, group)                      │
  │  - Event routing to local Sentants                          │
  ├─────────────────────────────────────────────────────────────┤
  │                 Rust NIF (bluetooth-meshd)                  │
  │  - BlueZ mesh daemon integration                            │
  │  - Low-level mesh operations                                │
  └─────────────────────────────────────────────────────────────┘
  ```

  ## Message Types

  | Type | Use Case | Size Limit |
  |------|----------|------------|
  | SENTANT_EVENT | Publish event to group | ~380 bytes |
  | SENTANT_SIGNAL | Send to specific Sentant | ~380 bytes |
  | SENTANT_PRESENCE | Announce available Sentants | ~256 bytes |

  ## Usage

  ```elixir
  # Start mesh (typically done by application supervisor)
  {:ok, _pid} = BLEMesh.start_link([])

  # Publish an event (floods through mesh)
  BLEMesh.publish_event("my_sentant", "door_opened", %{room: "A1"})

  # Send signal to specific Sentant
  BLEMesh.send_signal("source", "target_node|target_sentant", "activate", %{level: 50})

  # Subscribe to group
  BLEMesh.subscribe_group("all_sensors")
  ```

  ## Addressing

  - **Virtual Address**: Hash of "node_id|sentant_name" → 0x8000-0xBFFF
  - **Group Address**: Hash of group name → 0xC000-0xFEFF
  - **Unicast Address**: Assigned during provisioning → 0x0001-0x7FFF

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  # Helper to get node name for log messages
  defp log_prefix, do: "[BLEMesh:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  alias AiReality2Transnet.Action

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Constants
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Sentant Model Opcodes (must match Rust)
  @opcode_sentant_event 0xC0_FFFF
  @opcode_sentant_signal 0xC1_FFFF
  @opcode_sentant_presence 0xC4_FFFF

  # Maximum payload size for mesh messages
  @max_payload_size 380

  # Presence announcement interval (ms)
  @presence_interval_ms 60_000

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Type Definitions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc "Mesh message for sending"
  @type mesh_message :: %{
    dst: non_neg_integer(),
    opcode: non_neg_integer(),
    payload: binary(),
    ttl: non_neg_integer()
  }

  @typedoc "Internal state"
  @type state :: %{
    mesh_handle: reference() | nil,
    unicast_address: non_neg_integer(),
    subscriptions: MapSet.t(non_neg_integer()),
    sentant_addresses: %{String.t() => non_neg_integer()},
    active: boolean(),
    stats: map()
  }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the BLE Mesh stack.

  Must be called before other mesh operations. Typically called automatically
  when Bluetooth is available.

  ## Parameters
  - `adapter_name` - Bluetooth adapter (default: "hci0")

  ## Returns
  - `:ok` - Mesh initialized
  - `{:error, reason}` - Failed to initialize
  """
  @spec init_mesh(String.t()) :: :ok | {:error, String.t()}
  def init_mesh(adapter_name \\ "hci0") do
    GenServer.call(__MODULE__, {:init_mesh, adapter_name}, 30_000)
  end

  @doc """
  Publishes a Sentant event to the mesh network.

  Events are flooded through the mesh and received by all nodes subscribed
  to the Sentant's virtual address or relevant groups.

  ## Parameters
  - `sentant_id` - Source Sentant ID
  - `event_name` - Name of the event
  - `parameters` - Event parameters (will be JSON encoded)

  ## Returns
  - `:ok` - Event published
  - `{:error, reason}` - Failed to publish

  ## Example

      BLEMesh.publish_event("sensor_1", "temperature_changed", %{value: 23.5, unit: "C"})
  """
  @spec publish_event(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def publish_event(sentant_id, event_name, parameters \\ %{}) do
    GenServer.call(__MODULE__, {:publish_event, sentant_id, event_name, parameters})
  end

  @doc """
  Sends a signal to a specific Sentant via mesh.

  ## Parameters
  - `source_sentant` - Source Sentant ID
  - `target` - Target as "node_name|sentant_name" or just Sentant ID if local
  - `signal_name` - Name of the signal
  - `parameters` - Signal parameters

  ## Returns
  - `:ok` - Signal sent
  - `{:error, reason}` - Failed to send
  """
  @spec send_signal(String.t(), String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def send_signal(source_sentant, target, signal_name, parameters \\ %{}) do
    GenServer.call(__MODULE__, {:send_signal, source_sentant, target, signal_name, parameters})
  end

  @doc """
  Subscribes to a group address.

  ## Parameters
  - `group_name` - Name of the group (e.g., "all_sensors", "room_kitchen")

  ## Returns
  - `:ok` - Subscribed
  - `{:error, reason}` - Failed
  """
  @spec subscribe_group(String.t()) :: :ok | {:error, String.t()}
  def subscribe_group(group_name) do
    GenServer.call(__MODULE__, {:subscribe_group, group_name})
  end

  @doc """
  Unsubscribes from a group address.
  """
  @spec unsubscribe_group(String.t()) :: :ok | {:error, String.t()}
  def unsubscribe_group(group_name) do
    GenServer.call(__MODULE__, {:unsubscribe_group, group_name})
  end

  @doc """
  Gets the virtual address for a Sentant.

  ## Parameters
  - `node_id` - Node UUID
  - `sentant_name` - Sentant name

  ## Returns
  - `{:ok, address}` - 16-bit virtual address
  """
  @spec get_sentant_address(String.t(), String.t()) :: {:ok, non_neg_integer()}
  def get_sentant_address(node_id, sentant_name) do
    # Use NIF for consistent hashing
    Action.mesh_sentant_address(node_id, sentant_name)
  end

  @doc """
  Gets the group address for a group name.
  """
  @spec get_group_address(String.t()) :: {:ok, non_neg_integer()}
  def get_group_address(group_name) do
    Action.mesh_group_address(group_name)
  end

  @doc """
  Checks if mesh is active and ready.
  """
  @spec active?() :: boolean()
  def active? do
    GenServer.call(__MODULE__, :is_active)
  end

  @doc """
  Gets mesh statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Checks if a message can be sent via mesh (size check).

  ## Parameters
  - `message` - The message to check (will be JSON encoded)

  ## Returns
  - `true` - Message fits in mesh payload
  - `false` - Message too large, use WiFi
  """
  @spec fits_in_mesh?(map()) :: boolean()
  def fits_in_mesh?(message) do
    case Jason.encode(message) do
      {:ok, json} -> byte_size(json) <= @max_payload_size - 6  # Leave room for headers
      _ -> false
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    state = %{
      mesh_handle: nil,
      unicast_address: 0,
      subscriptions: MapSet.new(),
      sentant_addresses: %{},
      active: false,
      stats: %{
        events_published: 0,
        events_received: 0,
        signals_sent: 0,
        signals_received: 0,
        messages_relayed: 0
      }
    }

    Logger.info("#{log_prefix()} Started (mesh not yet initialized)")
    {:ok, state}
  end

  @impl true
  def handle_call({:init_mesh, adapter_name}, _from, state) do
    node_id = Reality2.Bootstrap.get(:node_id)

    case Action.mesh_init(self(), node_id, adapter_name) do
      {:ok, handle} ->
        Logger.info("#{log_prefix()} Mesh initialized on #{adapter_name}")

        # Schedule periodic presence announcements
        schedule_presence_announcement()

        new_state = %{state |
          mesh_handle: handle,
          active: true
        }
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.warning("#{log_prefix()} Failed to initialize mesh: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:publish_event, sentant_id, event_name, parameters}, _from, state) do
    if state.active do
      result = do_publish_event(state, sentant_id, event_name, parameters)
      new_stats = Map.update!(state.stats, :events_published, &(&1 + 1))
      {:reply, result, %{state | stats: new_stats}}
    else
      {:reply, {:error, "mesh_not_active"}, state}
    end
  end

  @impl true
  def handle_call({:send_signal, source, target, signal_name, params}, _from, state) do
    if state.active do
      result = do_send_signal(state, source, target, signal_name, params)
      new_stats = Map.update!(state.stats, :signals_sent, &(&1 + 1))
      {:reply, result, %{state | stats: new_stats}}
    else
      {:reply, {:error, "mesh_not_active"}, state}
    end
  end

  @impl true
  def handle_call({:subscribe_group, group_name}, _from, state) do
    if state.active do
      {:ok, address} = get_group_address(group_name)

      case Action.mesh_subscribe(state.mesh_handle, address) do
        :ok ->
          new_subs = MapSet.put(state.subscriptions, address)
          Logger.info("#{log_prefix()} Subscribed to group #{group_name} (0x#{Integer.to_string(address, 16)})")
          {:reply, :ok, %{state | subscriptions: new_subs}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, "mesh_not_active"}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe_group, group_name}, _from, state) do
    if state.active do
      {:ok, address} = get_group_address(group_name)

      case Action.mesh_unsubscribe(state.mesh_handle, address) do
        :ok ->
          new_subs = MapSet.delete(state.subscriptions, address)
          {:reply, :ok, %{state | subscriptions: new_subs}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, "mesh_not_active"}, state}
    end
  end

  @impl true
  def handle_call(:is_active, _from, state) do
    {:reply, state.active, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      active: state.active,
      unicast_address: state.unicast_address,
      subscriptions: MapSet.size(state.subscriptions)
    })
    {:reply, stats, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Handle Incoming Mesh Messages
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info({:mesh_sentant_event, sentant_hash, event_hash, params_json}, state) do
    Logger.debug("#{log_prefix()} Received event: sentant=0x#{Integer.to_string(sentant_hash, 16)}, event=0x#{Integer.to_string(event_hash, 16)}")

    # Decode and route to local Sentants
    case Jason.decode(params_json) do
      {:ok, params} ->
        # Route via WFS or directly to Sentants
        route_incoming_event(sentant_hash, event_hash, params)

      {:error, _} ->
        Logger.warning("#{log_prefix()} Failed to decode event params")
    end

    new_stats = Map.update!(state.stats, :events_received, &(&1 + 1))
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info({:mesh_sentant_signal, source_hash, target_hash, signal_hash, params_json}, state) do
    Logger.debug("#{log_prefix()} Received signal: #{source_hash} -> #{target_hash}")

    case Jason.decode(params_json) do
      {:ok, params} ->
        route_incoming_signal(source_hash, target_hash, signal_hash, params)

      {:error, _} ->
        Logger.warning("#{log_prefix()} Failed to decode signal params")
    end

    new_stats = Map.update!(state.stats, :signals_received, &(&1 + 1))
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info({:mesh_sentant_presence, node_hash, sentant_count, _sentant_hashes}, state) do
    Logger.debug("#{log_prefix()} Presence from node 0x#{Integer.to_string(node_hash, 16)}: #{sentant_count} sentants")

    # Could update peer tracking here with sentant_hashes
    # For now, just log
    {:noreply, state}
  end

  @impl true
  def handle_info(:announce_presence, state) do
    if state.active do
      announce_local_sentants(state)
    end

    # Schedule next announcement
    schedule_presence_announcement()
    {:noreply, state}
  end

  @impl true
  def handle_info({:mesh_initialized, unicast_address}, state) do
    Logger.info("#{log_prefix()} Mesh provisioned, unicast address: 0x#{Integer.to_string(unicast_address, 16)}")
    {:noreply, %{state | unicast_address: unicast_address, active: true}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("#{log_prefix()} Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Message Sending
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp do_publish_event(state, sentant_id, event_name, parameters) do
    # Encode parameters to JSON
    case Jason.encode(parameters) do
      {:ok, params_json} when byte_size(params_json) <= @max_payload_size - 4 ->
        # Build payload: [sentant_hash:2][event_hash:2][params]
        sentant_hash = simple_hash(sentant_id)
        event_hash = simple_hash(event_name)

        payload =
          <<sentant_hash::big-16, event_hash::big-16>> <> params_json

        # Get virtual address for this Sentant (all subscribers will receive)
        node_id = Reality2.Bootstrap.get(:node_id)
        {:ok, dst_address} = get_sentant_address(node_id, sentant_id)

        # Publish to mesh
        Action.mesh_publish(state.mesh_handle, dst_address, @opcode_sentant_event, payload)

      {:ok, _} ->
        {:error, "payload_too_large"}

      {:error, reason} ->
        {:error, "json_encode_failed: #{inspect(reason)}"}
    end
  end

  defp do_send_signal(state, source_sentant, target, signal_name, parameters) do
    # Parse target: "node_name|sentant_name" or just sentant_name
    {target_node, target_sentant} = parse_target(target)

    case Jason.encode(parameters) do
      {:ok, params_json} when byte_size(params_json) <= @max_payload_size - 6 ->
        # Build payload
        source_hash = simple_hash(source_sentant)
        target_hash = simple_hash(target_sentant)
        signal_hash = simple_hash(signal_name)

        payload =
          <<source_hash::big-16, target_hash::big-16, signal_hash::big-16>> <> params_json

        # Get destination address
        {:ok, dst_address} = get_sentant_address(target_node, target_sentant)

        # Send to mesh
        Action.mesh_publish(state.mesh_handle, dst_address, @opcode_sentant_signal, payload)

      {:ok, _} ->
        {:error, "payload_too_large"}

      {:error, reason} ->
        {:error, "json_encode_failed: #{inspect(reason)}"}
    end
  end

  defp announce_local_sentants(state) do
    node_id = Reality2.Bootstrap.get(:node_id)

    # Get local Sentant names
    sentant_names = case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} ->
        Enum.map(sentants, fn s -> Map.get(s, :name, "") end)
        |> Enum.reject(&(&1 == ""))

      _ -> []
    end

    if length(sentant_names) > 0 do
      # Build presence payload
      node_hash = simple_hash(node_id)
      count = min(length(sentant_names), 128)

      sentant_hashes = sentant_names
        |> Enum.take(count)
        |> Enum.map(&simple_hash/1)
        |> Enum.map(fn h -> <<h::big-16>> end)
        |> Enum.join()

      payload = <<node_hash::big-16, count::8>> <> sentant_hashes

      # Broadcast to all-nodes group (0xFFFF)
      Action.mesh_publish(state.mesh_handle, 0xFFFF, @opcode_sentant_presence, payload)
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Message Routing
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp route_incoming_event(sentant_hash, event_hash, params) do
    # Find local Sentant(s) that match this hash
    # For now, broadcast to all local Sentants
    # TODO: Maintain hash -> sentant_id mapping for efficient routing

    Reality2.Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        type: :ble_mesh_event,
        sentant_hash: sentant_hash,
        event_hash: event_hash,
        params: params,
        transport: :ble_mesh
      }
    })
  end

  defp route_incoming_signal(source_hash, target_hash, signal_hash, params) do
    # Find local Sentant matching target_hash
    # For now, broadcast with filter info
    # TODO: Efficient hash-based routing

    Reality2.Sentants.sendto_all(%{
      event: "__mesh_signal",
      parameters: %{
        source_hash: source_hash,
        target_hash: target_hash,
        signal_hash: signal_hash,
        params: params,
        transport: :ble_mesh
      }
    })
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Utilities
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp parse_target(target) do
    case String.split(target, "|", parts: 2) do
      [node, sentant] -> {node, sentant}
      [sentant] -> {Reality2.Bootstrap.get(:node_id), sentant}
    end
  end

  # Simple hash function matching Rust implementation
  defp simple_hash(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(5381, fn byte, hash ->
      rem((hash * 33) + byte, 0x100000000)
    end)
    |> Bitwise.band(0xFFFF)
  end

  defp schedule_presence_announcement do
    Process.send_after(self(), :announce_presence, @presence_interval_ms)
  end
end
