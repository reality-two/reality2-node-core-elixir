defmodule AiReality2Pns.Router do
  @moduledoc """
  Pathing Name System (PNS) Router - Location-transparent routing for Sentant events.

  Automatically routes events to the appropriate destination:
  - Local Sentants on this node
  - Remote Sentants on peer nodes via GATT
  - Remote Sentants on GraphQL nodes (future)

  ## Architecture

  The router maintains a topology cache of all known Sentants:
  - Local Sentants tracked via Reality2.Metadata
  - Remote Sentants discovered via GATT peer connections
  - GraphQL nodes (future)

  ## Usage

      # Send to any Sentant (local or remote)
      AiReality2Pns.Router.send_to_sentant(
        sentant_id,
        "event_name",
        %{param: "value"},
        %{passthrough: "data"}
      )

      # Broadcast to all Sentants matching a pattern
      AiReality2Pns.Router.broadcast("device_*", event, params)

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger
  alias Reality2.Sentants

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Send an event to a Sentant, automatically routing to local or remote.

  ## Parameters
  - `sentant_identifier` - UUID, name, or %{id: uuid} / %{name: name}
  - `event` - Event name string
  - `parameters` - Optional parameters map (default: %{})
  - `passthrough` - Optional passthrough data (default: nil)

  ## Returns
  - `{:ok, :local}` - Sent to local Sentant
  - `{:ok, {:remote, node_id}}` - Sent to remote Sentant via GATT
  - `{:error, :not_found}` - Sentant not found anywhere
  - `{:error, reason}` - Other error
  """
  def send_to_sentant(sentant_identifier, event, parameters \\ %{}, passthrough \\ nil) do
    GenServer.call(__MODULE__, {:send_to_sentant, sentant_identifier, event, parameters, passthrough})
  end

  @doc """
  Broadcast an event to all Sentants matching a pattern.

  ## Parameters
  - `pattern` - "*" for all, "name_pattern*" for wildcard, or list of IDs/names
  - `event` - Event name
  - `parameters` - Optional parameters
  - `passthrough` - Optional passthrough data

  ## Returns
  - `{:ok, %{local: count, remote: count}}` - Number sent to each type
  """
  def broadcast(pattern, event, parameters \\ %{}, passthrough \\ nil) do
    GenServer.call(__MODULE__, {:broadcast, pattern, event, parameters, passthrough})
  end

  @doc """
  Find a Sentant's location (local or remote).

  ## Returns
  - `{:ok, :local}` - Sentant is on this node
  - `{:ok, {:remote, node_id}}` - Sentant is on remote node
  - `{:error, :not_found}` - Sentant not found
  """
  def locate(sentant_identifier) do
    GenServer.call(__MODULE__, {:locate, sentant_identifier})
  end

  @doc """
  Get the current routing table (for debugging).
  """
  def get_routing_table do
    GenServer.call(__MODULE__, :get_routing_table)
  end

  @doc """
  Force a refresh of the peer topology cache.
  """
  def refresh_topology do
    GenServer.cast(__MODULE__, :refresh_topology)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Subscribe to peer discovery events
    Phoenix.PubSub.subscribe(Reality2.PubSub, "sentant:signals")

    # Initial state
    state = %{
      # Map of sentant_id => {:local | {:remote, node_id}}
      sentant_locations: %{},
      # Map of node_id => [sentant_ids]
      peer_sentants: %{},
      # Statistics
      stats: %{
        local_sends: 0,
        remote_sends: 0,
        broadcasts: 0,
        cache_hits: 0,
        cache_misses: 0
      }
    }

    # Initial topology refresh
    send(self(), :refresh_topology)

    Logger.info("[PNS Router] Started - location-transparent routing enabled")
    {:ok, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Call Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call({:send_to_sentant, identifier, event, params, passthrough}, _from, state) do
    sentant_id = normalize_identifier(identifier)

    case resolve_location(sentant_id, state) do
      {:ok, :local} ->
        # Send to local Sentant
        result = send_to_local(sentant_id, event, params, passthrough)
        new_stats = Map.update!(state.stats, :local_sends, &(&1 + 1))
        {:reply, {:ok, :local, result}, %{state | stats: new_stats}}

      {:ok, {:remote, node_id}} ->
        # Send to remote Sentant via GATT
        result = send_to_remote_gatt(node_id, sentant_id, event, params, passthrough)
        new_stats = Map.update!(state.stats, :remote_sends, &(&1 + 1))
        {:reply, {:ok, {:remote, node_id}, result}, %{state | stats: new_stats}}

      {:error, :not_found} ->
        Logger.debug("[PNS Router] Sentant #{sentant_id} not found - attempting direct send")
        # Try direct send anyway (might be newly created)
        case send_to_local(sentant_id, event, params, passthrough) do
          {:ok, _} = result ->
            # Update cache
            new_locations = Map.put(state.sentant_locations, sentant_id, :local)
            {:reply, {:ok, :local, result}, %{state | sentant_locations: new_locations}}

          error ->
            {:reply, {:error, :not_found, error}, state}
        end
    end
  end

  @impl true
  def handle_call({:broadcast, pattern, event, params, passthrough}, _from, state) do
    targets = resolve_broadcast_targets(pattern, state)

    local_count = Enum.count(targets.local, fn sentant_id ->
      case send_to_local(sentant_id, event, params, passthrough) do
        {:ok, _} -> true
        _ -> false
      end
    end)

    remote_count = Enum.reduce(targets.remote, 0, fn {node_id, sentant_ids}, acc ->
      Enum.count(sentant_ids, fn sentant_id ->
        case send_to_remote_gatt(node_id, sentant_id, event, params, passthrough) do
          :ok -> true
          _ -> false
        end
      end) + acc
    end)

    new_stats = Map.update!(state.stats, :broadcasts, &(&1 + 1))

    {:reply, {:ok, %{local: local_count, remote: remote_count}}, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call({:locate, identifier}, _from, state) do
    sentant_id = normalize_identifier(identifier)
    result = resolve_location(sentant_id, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_routing_table, _from, state) do
    # Count local vs remote from the cache
    {local_count, remote_count} = Enum.reduce(state.sentant_locations, {0, 0}, fn
      {_id, :local}, {local, remote} -> {local + 1, remote}
      {_id, {:remote, _node_id}}, {local, remote} -> {local, remote + 1}
    end)

    table = %{
      sentant_locations: state.sentant_locations,
      peer_sentants: state.peer_sentants,
      stats: state.stats,
      local_sentant_count: local_count,
      remote_sentant_count: remote_count
    }

    {:reply, table, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Cast Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_cast(:refresh_topology, state) do
    {:noreply, refresh_topology_cache(state)}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Info Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info(:refresh_topology, state) do
    # Initial refresh
    {:noreply, refresh_topology_cache(state)}
  end

  @impl true
  def handle_info({:sentant_signal, _signal_data}, state) do
    # Could track signal patterns here for routing optimization
    {:noreply, state}
  end

  # Handle peer discovery events from transnet
  @impl true
  def handle_info({:r2node_found, node_id, _info}, state) do
    Logger.debug("[PNS Router] New peer discovered: #{node_id}")
    # Topology will be updated when peer sentants are discovered
    {:noreply, state}
  end

  @impl true
  def handle_info({:r2node_lost, node_id}, state) do
    Logger.info("[PNS Router] Peer lost: #{node_id} - removing from topology")

    # Remove all sentants from this peer
    peer_sentant_ids = Map.get(state.peer_sentants, node_id, [])
    new_locations = Enum.reduce(peer_sentant_ids, state.sentant_locations, fn sentant_id, acc ->
      Map.delete(acc, sentant_id)
    end)

    new_peer_sentants = Map.delete(state.peer_sentants, node_id)

    {:noreply, %{state | sentant_locations: new_locations, peer_sentants: new_peer_sentants}}
  end

  # Catchall
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Normalize various identifier formats to UUID
  defp normalize_identifier(id) when is_binary(id) do
    # Check if it's a UUID or a name
    case UUID.info(id) do
      {:ok, _} -> id
      {:error, _} ->
        # It's a name, look it up
        case Reality2.Metadata.get(:SentantIDs, id) do
          nil -> id  # Return as-is, will fail later
          uuid -> uuid
        end
    end
  end

  defp normalize_identifier(%{id: id}), do: id
  defp normalize_identifier(%{name: name}) do
    Reality2.Metadata.get(:SentantIDs, name) || name
  end

  defp normalize_identifier(other), do: other

  # Resolve where a Sentant is located
  defp resolve_location(sentant_id, state) do
    # Check cache first
    case Map.get(state.sentant_locations, sentant_id) do
      :local ->
        {:ok, :local}

      {:remote, node_id} ->
        {:ok, {:remote, node_id}}

      nil ->
        # Cache miss - check if it's local
        case is_local_sentant?(sentant_id) do
          true -> {:ok, :local}
          false -> {:error, :not_found}
        end
    end
  end

  # Check if a Sentant exists locally
  defp is_local_sentant?(sentant_id) do
    case Sentants.read(%{id: sentant_id}, :definition) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Send to local Sentant
  defp send_to_local(sentant_id, event, parameters, passthrough) do
    Sentants.sendto(%{id: sentant_id}, %{
      event: event,
      parameters: parameters,
      passthrough: passthrough
    })
  end

  # Send to remote Sentant via appropriate transport (WiFi mesh preferred, BLE discovery only)
  defp send_to_remote_gatt(node_id, sentant_id, event, parameters, passthrough) do
    # Check if transnet modules are available
    with true <- Code.ensure_loaded?(AiReality2Transnet.PeerManager),
         true <- Code.ensure_loaded?(AiReality2Transnet.WifiServer),
         {:ok, peer} <- AiReality2Transnet.PeerManager.get_peer(node_id) do

      # Send via appropriate transport
      case peer.transport do
        :wifi_mesh ->
          # Use WiFi mesh HTTP for sending commands
          send_via_wifi_mesh(peer, sentant_id, event, parameters, passthrough)

        :ble_gatt ->
          # BLE is for discovery only - suggest upgrading to WiFi
          Logger.warning("[PNS Router] Peer #{String.slice(node_id, 0..7)}... is on BLE (discovery only)")
          Logger.info("[PNS Router] Consider upgrading to WiFi mesh for data transfer")
          {:error, :ble_discovery_only}

        _ ->
          {:error, :unknown_transport}
      end
    else
      false ->
        {:error, :transnet_not_available}

      {:error, :not_found} ->
        {:error, :peer_not_found}

      error ->
        error
    end
  end

  # Send command via WiFi mesh HTTP
  defp send_via_wifi_mesh(peer, sentant_id, event, parameters, passthrough) do
    # Get peer's IPv6 address from mesh info
    ipv6 = Map.get(peer, :ipv6_link_local)

    if ipv6 do
      Logger.info("[PNS Router] Sending to Sentant #{String.slice(sentant_id, 0..7)}... via WiFi mesh HTTP")

      case AiReality2Transnet.WifiServer.send_to_peer(ipv6, sentant_id, event, parameters, passthrough) do
        {:ok, response} ->
          Logger.debug("[PNS Router] WiFi mesh command succeeded: #{inspect(response)}")
          {:ok, response}

        {:error, reason} ->
          Logger.error("[PNS Router] WiFi mesh command failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("[PNS Router] Peer has no IPv6 address for WiFi mesh")
      {:error, :no_ipv6_address}
    end
  end


  # Resolve broadcast targets
  defp resolve_broadcast_targets("*", state) do
    # All Sentants everywhere
    local_ids = get_all_local_sentant_ids()
    remote_by_node = state.peer_sentants

    %{local: local_ids, remote: remote_by_node}
  end

  defp resolve_broadcast_targets(pattern, state) when is_binary(pattern) do
    # Wildcard pattern matching
    local_ids = get_all_local_sentant_ids()
    |> Enum.filter(&matches_pattern?(&1, pattern))

    remote_by_node = Enum.reduce(state.peer_sentants, %{}, fn {node_id, sentant_ids}, acc ->
      matching = Enum.filter(sentant_ids, &matches_pattern?(&1, pattern))
      if Enum.empty?(matching), do: acc, else: Map.put(acc, node_id, matching)
    end)

    %{local: local_ids, remote: remote_by_node}
  end

  defp resolve_broadcast_targets(list, state) when is_list(list) do
    # Specific list of IDs/names
    list
    |> Enum.map(&normalize_identifier/1)
    |> Enum.split_with(&is_local_sentant?/1)
    |> then(fn {local, remote} ->
      # Group remote by node
      remote_by_node = Enum.reduce(remote, %{}, fn sentant_id, acc ->
        case Map.get(state.sentant_locations, sentant_id) do
          {:remote, node_id} ->
            Map.update(acc, node_id, [sentant_id], &[sentant_id | &1])
          _ ->
            acc
        end
      end)

      %{local: local, remote: remote_by_node}
    end)
  end

  # Simple pattern matching
  defp matches_pattern?(id, pattern) do
    cond do
      String.ends_with?(pattern, "*") ->
        prefix = String.trim_trailing(pattern, "*")
        String.starts_with?(id, prefix)

      String.starts_with?(pattern, "*") ->
        suffix = String.trim_leading(pattern, "*")
        String.ends_with?(id, suffix)

      true ->
        id == pattern
    end
  end

  # Get all local Sentant IDs
  defp get_all_local_sentant_ids do
    case Reality2.Metadata.all(:SentantIDs) do
      sentant_map when is_map(sentant_map) ->
        Map.values(sentant_map)
      _ ->
        []
    end
  end

  # Refresh the topology cache from all sources
  defp refresh_topology_cache(state) do
    # Get local Sentants
    local_sentants = get_all_local_sentant_ids()

    # Get peer Sentants from transnet PeerManager
    {peer_sentants, remote_locations} = if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      peers = AiReality2Transnet.PeerManager.get_all_peers()

      peer_map = Enum.reduce(peers, %{}, fn {node_id, peer_info}, acc ->
        sentant_ids = Enum.map(peer_info.sentants, fn s ->
          case s do
            %{id: id} -> id
            %{"id" => id} -> id
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

        Map.put(acc, node_id, sentant_ids)
      end)

      # Build reverse lookup: sentant_id => node_id
      locations = Enum.reduce(peer_map, %{}, fn {node_id, sentant_ids}, acc ->
        Enum.reduce(sentant_ids, acc, fn sentant_id, acc2 ->
          Map.put(acc2, sentant_id, {:remote, node_id})
        end)
      end)

      {peer_map, locations}
    else
      {%{}, %{}}
    end

    # Build local locations
    local_locations = Enum.reduce(local_sentants, %{}, fn sentant_id, acc ->
      Map.put(acc, sentant_id, :local)
    end)

    # Merge all locations
    all_locations = Map.merge(local_locations, remote_locations)

    Logger.debug("[PNS Router] Topology refreshed: #{map_size(local_locations)} local, #{map_size(remote_locations)} remote")

    %{state |
      sentant_locations: all_locations,
      peer_sentants: peer_sentants
    }
  end
end
