defmodule AiReality2Transnet.Transport do
  @moduledoc """
  Transport behaviour for Reality2 mesh communication.

  This module defines the common interface that all transport mechanisms
  (BLE, WiFi, LoRa, etc.) must implement. The R2Mesh module uses this
  abstraction to route messages without knowing transport details.

  ## Transport Types

  | Transport | Range | Bandwidth | Best For |
  |-----------|-------|-----------|----------|
  | BLE | ~100m | Low (~20 bytes) | Discovery, small messages |
  | WiFi Mesh | ~50m | High (~1MB) | Data exchange, GraphQL |
  | WiFi Hotspot | ~50m | High (~1MB) | Full sentant exchange |
  | LoRa | ~15km | Very Low (~200 bytes) | Long range, rural |

  ## Message Format

  All transports use a common message format:

  ```
  %{
    msg_id: non_neg_integer(),     # Unique message ID for deduplication
    ttl: non_neg_integer(),        # Time-to-live (hop count)
    type: atom(),                  # :event | :signal | :presence | :data
    src_node_id: String.t(),       # Source node ID
    payload: binary()              # Transport-specific payload
  }
  ```

  ## Implementing a Transport

  ```elixir
  defmodule MyTransport do
    @behaviour AiReality2Transnet.Transport

    @impl true
    def transport_type, do: :my_transport

    @impl true
    def available?, do: true

    @impl true
    def max_payload_size, do: 1024

    @impl true
    def broadcast(message) do
      # Send message via this transport
      :ok
    end

    @impl true
    def send_to(peer_id, message) do
      # Send directly to peer if supported
      {:error, :not_supported}
    end
  end
  ```

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Types
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc "Standard mesh message format"
  @type mesh_message :: %{
    msg_id: non_neg_integer(),
    ttl: non_neg_integer(),
    type: atom(),
    src_node_id: String.t(),
    payload: binary()
  }

  @typedoc "Transport capabilities"
  @type capabilities :: %{
    broadcast: boolean(),       # Can broadcast to all peers
    unicast: boolean(),         # Can send to specific peer
    bidirectional: boolean(),   # Full duplex communication
    reliable: boolean(),        # Guaranteed delivery (TCP-like)
    max_payload: non_neg_integer()
  }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Returns the transport type identifier.

  ## Example
      :ble | :wifi_hotspot | :wifi_mesh | :lora
  """
  @callback transport_type() :: atom()

  @doc """
  Checks if this transport is currently available.

  Should check hardware availability, initialization status, etc.
  """
  @callback available?() :: boolean()

  @doc """
  Returns the maximum payload size in bytes.

  Messages larger than this should use a different transport.
  """
  @callback max_payload_size() :: non_neg_integer()

  @doc """
  Returns the transport's capabilities.
  """
  @callback capabilities() :: capabilities()

  @doc """
  Broadcasts a message to all reachable peers via this transport.

  ## Parameters
  - `message` - Standard mesh message

  ## Returns
  - `:ok` - Message queued for broadcast
  - `{:error, reason}` - Failed
  """
  @callback broadcast(mesh_message()) :: :ok | {:error, term()}

  @doc """
  Sends a message directly to a specific peer.

  Not all transports support unicast (e.g., BLE advertising is broadcast-only).

  ## Parameters
  - `peer_id` - Target peer's node ID
  - `message` - Standard mesh message

  ## Returns
  - `:ok` - Message sent
  - `{:error, :not_supported}` - Transport doesn't support unicast
  - `{:error, reason}` - Other failure
  """
  @callback send_to(peer_id :: String.t(), mesh_message()) :: :ok | {:error, term()}

  @doc """
  Called when a message is received from this transport.

  The transport should call `AiReality2Transnet.MeshRouter.handle_incoming/2`
  when it receives a message.
  """
  @callback handle_incoming(raw_data :: binary()) :: :ok

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Optional Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Returns current transport statistics.
  """
  @callback get_stats() :: map()

  @doc """
  Returns list of peers reachable via this transport.
  """
  @callback get_peers() :: [String.t()]

  @optional_callbacks [get_stats: 0, get_peers: 0]

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Checks if a payload fits in the given transport.

  ## Parameters
  - `transport_module` - Module implementing Transport behaviour
  - `payload` - Data to check

  ## Returns
  - `true` - Fits
  - `false` - Too large
  """
  @spec fits?(module(), binary() | map()) :: boolean()
  def fits?(transport_module, payload) when is_binary(payload) do
    byte_size(payload) <= transport_module.max_payload_size()
  end

  def fits?(transport_module, payload) when is_map(payload) do
    case Jason.encode(payload) do
      {:ok, encoded} -> byte_size(encoded) <= transport_module.max_payload_size()
      _ -> false
    end
  end

  def fits?(_, _), do: false

  @doc """
  Selects the best transport for a message based on payload size and requirements.

  ## Parameters
  - `transports` - List of transport modules
  - `payload_size` - Size of payload in bytes
  - `opts` - Options like `[require_reliable: true, prefer: :lora]`

  ## Returns
  - `{:ok, transport_module}` - Best matching transport
  - `{:error, :no_suitable_transport}` - No transport can handle the message
  """
  @spec select_best([module()], non_neg_integer(), keyword()) :: {:ok, module()} | {:error, :no_suitable_transport}
  def select_best(transports, payload_size, opts \\ []) do
    require_reliable = Keyword.get(opts, :require_reliable, false)
    preferred = Keyword.get(opts, :prefer)

    # Filter to available transports that can handle the payload
    suitable = transports
      |> Enum.filter(fn t ->
        t.available?() and
        t.max_payload_size() >= payload_size and
        (not require_reliable or t.capabilities().reliable)
      end)

    case suitable do
      [] ->
        {:error, :no_suitable_transport}

      candidates ->
        # Prefer the specified transport if available
        if preferred && Enum.any?(candidates, fn t -> t.transport_type() == preferred end) do
          {:ok, Enum.find(candidates, fn t -> t.transport_type() == preferred end)}
        else
          # Otherwise pick by priority: WiFi > LoRa > BLE
          sorted = Enum.sort_by(candidates, fn t ->
            case t.transport_type() do
              :wifi_hotspot -> 0
              :wifi_mesh -> 1
              :lora -> 2
              :ble -> 3
              _ -> 99
            end
          end)
          {:ok, List.first(sorted)}
        end
    end
  end
end
