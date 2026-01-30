defmodule AiReality2Pns.Router do
  @moduledoc """
  Pathing Name System (PNS) Router - Location-transparent routing for Sentant events.

  Automatically routes events to the appropriate destination:
  - Local Sentants on this node
  - Remote Sentants on peer nodes via WiFi/GraphQL
  - Remote Sentants on GraphQL nodes (future)

  ## Architecture

  The router maintains a topology of all known Sentants:
  - Local Sentants tracked via Reality2.Metadata (:SentantIDs)
  - Remote Sentants discovered via transnet peer connections
  - Searches local first, then all known peer nodes

  ## Addressing Formats

  ### Local-only (no `|` separator)

  - `"Sentant Name"` - Send to local sentant by name
  - `"sentant-uuid"` - Send to local sentant by UUID
  - No `to:` field - Send to self (current Sentant)

  ### Broadcast all (`*`)

  - `"*"` - Send to ALL sentants on ALL known nodes (local + remote)

  This enables full broadcast messaging across the entire network.

  ### All nodes with name (`*|` prefix)

  - `"*|Sentant Name"` - Send to ALL sentants with this name across ALL known nodes
  - `"*|sentant-uuid"` - Send to sentant by UUID (checks local + all peers)

  This enables broadcast-style messaging to identically-named sentants on different nodes.

  ### Specific node (`node|` prefix)

  - `"node_name|sentant_name"` - Specific node and sentant by names
  - `"node_name|sentant_uuid"` - Specific node by name, sentant by UUID
  - `"node_uuid|sentant_name"` - Specific node by UUID, sentant by name
  - `"node_uuid|sentant_uuid"` - Specific node and sentant by UUIDs

  ## Examples

  In Sentant automation YAML:

      # Send to self (no to: field)
      - command: send
        parameters:
          event: "self_event"

      # Send to local sentant by name
      - command: send
        parameters:
          to: "Zen Quote"
          event: "get_quote"

      # Broadcast to ALL sentants on ALL nodes
      - command: send
        parameters:
          to: "*"
          event: "network_announcement"

      # Send to ALL nodes with "Sensor" sentant
      - command: send
        parameters:
          to: "*|Sensor"
          event: "read_data"

      # Send to specific node and sentant
      - command: send
        parameters:
          to: "R2Node_A3F7|Zen Quote"
          event: "get_quote"

      # Send to multiple targets
      - command: send
        parameters:
          to:
            - "Local Sentant"
            - "R2Node_B2C1|Remote Sentant"
            - "*|Broadcast Target"
          event: "multi_send"

  Programmatic usage:

      # Send to local sentant
      AiReality2Pns.Router.send_to_sentant("Zen Quote", "init", %{})

      # Send to all nodes with "Sensor"
      AiReality2Pns.Router.send_to_sentant("*|Sensor", "ping", %{})
      # => {:ok, %{local: 1, remote: 3, results: [...]}}

      # Target specific node
      AiReality2Pns.Router.send_to_sentant("R2Node_A3F7|Zen Quote", "init", %{})

      # Locate a sentant locally
      AiReality2Pns.Router.locate("Zen Quote")
      # => {:ok, :local, "uuid..."}

      # Locate across all nodes
      AiReality2Pns.Router.locate("*|Sensor")
      # => {:ok, :multiple, [{:local, "uuid1"}, {{:remote, "node-uuid"}, "uuid2"}]}

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
  - `sentant_identifier` - One of:
    - `"sentant_name"` - Send to local sentant by name
    - `"sentant_uuid"` - Send to local sentant by UUID
    - `"*"` - Broadcast to ALL sentants on ALL known nodes
    - `"*|sentant_name"` - Send to ALL nodes with this sentant name
    - `"*|sentant_uuid"` - Send to sentant by UUID (local + all peers)
    - `"node_name|sentant_name"` - Specific node and sentant
    - `"node_uuid|sentant_uuid"` - Specific node and sentant by UUIDs
    - `%{id: uuid}` or `%{name: name}` - Map format (local only)
  - `event` - Event name string
  - `parameters` - Optional parameters map (default: %{})
  - `passthrough` - Optional passthrough data (default: nil)

  ## Returns
  - `{:ok, :local, result}` - Sent to local Sentant
  - `{:ok, {:remote, node_id}, result}` - Sent to remote Sentant
  - `{:ok, %{local: n, remote: m, results: [...]}}` - Sent to multiple (`*` or `*|` format)
  - `{:error, :not_found}` - Sentant not found
  - `{:error, :node_not_found}` - Target node not found
  """
  def send_to_sentant(sentant_identifier, event, parameters \\ %{}, passthrough \\ nil, sender \\ nil) do
    GenServer.call(__MODULE__, {:send_to_sentant, sentant_identifier, event, parameters, passthrough, sender})
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

  Supports the same addressing formats as `send_to_sentant/4`:
  - `"sentant_name"` - Find on local node only
  - `"sentant_uuid"` - Find on local node by UUID
  - `"*|sentant_name"` - Find on ALL known nodes
  - `"node_name|sentant_name"` - Find on specific node

  ## Returns
  - `{:ok, :local, sentant_id}` - Found on local node
  - `{:ok, {:remote, node_id}, sentant_id}` - Found on remote node
  - `{:ok, :multiple, [{location, sentant_id}, ...]}` - Multiple matches (`*|` format)
  - `{:error, :not_found}` - Sentant not found
  - `{:error, :node_not_found}` - Target node not found
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
  def handle_call({:send_to_sentant, identifier, event, params, passthrough, sender}, _from, state) do
    # Parse path to handle different formats
    case parse_path(identifier) do
      :broadcast_all ->
        # "*" - send to ALL sentants on ALL known nodes
        handle_broadcast_all(event, params, passthrough, sender, state)

      {:local_only, sentant_identifier} ->
        # No node prefix — search local first, then hive peers (Gap 1 fix)
        handle_local_then_hive(sentant_identifier, event, params, passthrough, sender, state)

      {:all_nodes, sentant_identifier} ->
        # "*|sentant" - send to all nodes with this sentant
        handle_all_nodes(sentant_identifier, event, params, passthrough, sender, state)

      {:specific_node, node_part, sentant_part} ->
        # "node|sentant" - route to specific node
        handle_specific_node(node_part, sentant_part, event, params, passthrough, sender, state)

      {:specific_node_or_hive, part1, part2} ->
        # Could be node|sentant or hive|sentant — try node first
        case handle_specific_node(part1, part2, event, params, passthrough, sender, state) do
          {:reply, {:error, :node_not_found}, _} ->
            # Not a node — try as hive
            handle_hive_sentant(part1, part2, event, params, passthrough, sender, state)
          result ->
            result
        end

      {:hive_sentant, hive_identifier, sentant_name} ->
        # "hive|sentant" - route to nearest matching sentant in hive
        handle_hive_sentant(hive_identifier, sentant_name, event, params, passthrough, sender, state)

      {:hive_node_sentant, hive_identifier, node_part, sentant_part} ->
        # "hive|node|sentant" - route to specific node in specific hive
        handle_hive_node_sentant(hive_identifier, node_part, sentant_part, event, params, passthrough, sender, state)

      :reply_to_sender ->
        # "@sender" - reply to the sender
        handle_reply_to_sender(event, params, passthrough, sender, state)
    end
  end

  # Backwards compatibility - handle calls without sender
  @impl true
  def handle_call({:send_to_sentant, identifier, event, params, passthrough}, from, state) do
    handle_call({:send_to_sentant, identifier, event, params, passthrough, nil}, from, state)
  end

  @impl true
  def handle_call({:broadcast, pattern, event, params, passthrough}, _from, state) do
    targets = resolve_broadcast_targets(pattern, state)

    local_count = Enum.count(targets.local, fn sentant_id ->
      case send_to_local(sentant_id, event, params, passthrough, nil) do
        {:ok, _} -> true
        _ -> false
      end
    end)

    remote_count = Enum.reduce(targets.remote, 0, fn {node_id, sentant_ids}, acc ->
      Enum.count(sentant_ids, fn sentant_id ->
        case send_to_remote_gatt(node_id, sentant_id, event, params, passthrough, nil) do
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
    case parse_path(identifier) do
      {:local_only, sentant_identifier} ->
        # Only check local node
        sentant_id = normalize_identifier(sentant_identifier)
        if is_local_sentant?(sentant_id) do
          {:reply, {:ok, :local, sentant_id}, state}
        else
          {:reply, {:error, :not_found}, state}
        end

      {:all_nodes, sentant_identifier} ->
        # Search local and all peers, return all matches
        {is_name, id} = case sentant_identifier do
          %{id: i} -> {false, i}
          %{name: n} -> {true, n}
          str when is_binary(str) -> {not uuid?(str), str}
          other -> {false, other}
        end

        local_id = if is_name do
          Reality2.Metadata.get(:SentantIDs, id)
        else
          if is_local_sentant?(id), do: id, else: nil
        end

        local_match = if local_id, do: [{:local, local_id}], else: []

        remote_matches = if is_name do
          case find_sentants_by_name_on_peers(id) do
            {:ok, matches} ->
              Enum.map(matches, fn {sentant_id, node_id} ->
                {{:remote, node_id}, sentant_id}
              end)
            {:error, _} -> []
          end
        else
          case find_sentant_by_id_on_peers(id) do
            {:ok, node_id} -> [{{:remote, node_id}, id}]
            {:error, _} -> []
          end
        end

        all_matches = local_match ++ remote_matches

        case all_matches do
          [] -> {:reply, {:error, :not_found}, state}
          [{location, sentant_id}] -> {:reply, {:ok, location, sentant_id}, state}
          matches -> {:reply, {:ok, :multiple, matches}, state}
        end

      {:specific_node, node_part, sentant_part} ->
        # Target specific node
        locate_on_node(node_part, sentant_part, state)

      {:specific_node_or_hive, node_part, sentant_part} ->
        # Could be node|sentant or hive|sentant — try node first
        case locate_on_node(node_part, sentant_part, state) do
          {:reply, {:error, :node_not_found}, _} ->
            {:reply, {:error, :not_found}, state}
          result ->
            result
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  defp locate_on_node(node_part, sentant_part, state) do
    case resolve_node_identifier(node_part) do
      {:local, _node_id} ->
        sentant_id = resolve_sentant_on_node(sentant_part, :local)
        {:reply, {:ok, :local, sentant_id}, state}

      {:remote, node_id} ->
        sentant_id = resolve_sentant_on_node(sentant_part, {:remote, node_id})
        {:reply, {:ok, {:remote, node_id}, sentant_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
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


  # Handle "*" - broadcast to ALL sentants on ALL known nodes
  defp handle_broadcast_all(event, params, passthrough, sender, state) do
    # Get all local sentants
    local_sentant_ids = case Reality2.Metadata.all(:SentantIDs) do
      map when is_map(map) -> Map.values(map)
      _ -> []
    end

    # Send to all local sentants
    local_results = Enum.map(local_sentant_ids, fn sentant_id ->
      result = send_to_local(sentant_id, event, params, passthrough, sender)
      {:local, sentant_id, result}
    end)
    local_count = length(local_results)

    # Get all remote sentants from all peers
    {remote_count, remote_results} = if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      peers = AiReality2Transnet.PeerManager.get_all_peers()

      results = Enum.flat_map(peers, fn {node_id, peer} ->
        Enum.map(peer.sentants, fn s ->
          sentant_id = Map.get(s, :id) || Map.get(s, "id")
          result = send_to_remote_gatt(node_id, sentant_id, event, params, passthrough, sender)
          {{:remote, node_id}, sentant_id, result}
        end)
      end)

      {length(results), results}
    else
      {0, []}
    end

    all_results = local_results ++ remote_results
    total_sent = local_count + remote_count

    new_stats = state.stats
    |> Map.update!(:local_sends, &(&1 + local_count))
    |> Map.update!(:remote_sends, &(&1 + remote_count))
    |> Map.update!(:broadcasts, &(&1 + 1))

    {:reply, {:ok, %{local: local_count, remote: remote_count, total: total_sent, results: all_results}}, %{state | stats: new_stats}}
  end

  # Handle "node|sentant" - route to specific node
  defp handle_specific_node(node_part, sentant_part, event, params, passthrough, sender, state) do
    case resolve_node_identifier(node_part) do
      {:local, _node_id} ->
        # Target is this node - resolve sentant locally
        sentant_id = resolve_sentant_on_node(sentant_part, :local)
        result = send_to_local(sentant_id, event, params, passthrough, sender)
        new_stats = Map.update!(state.stats, :local_sends, &(&1 + 1))
        {:reply, {:ok, :local, result}, %{state | stats: new_stats}}

      {:remote, node_id} ->
        # Target is a remote node
        sentant_id = resolve_sentant_on_node(sentant_part, {:remote, node_id})
        result = send_to_remote_gatt(node_id, sentant_id, event, params, passthrough, sender)
        new_stats = Map.update!(state.stats, :remote_sends, &(&1 + 1))
        {:reply, {:ok, {:remote, node_id}, result}, %{state | stats: new_stats}}

      {:error, :node_not_found} ->
        Logger.warning("[PNS Router] Node not found: #{node_part}")
        {:reply, {:error, :node_not_found}, state}
    end
  end

  # Handle bare-name routing: local first, then hive directory (Gap 1 fix)
  # Falls through to hive peers when local lookup fails
  defp handle_local_then_hive(sentant_identifier, event, params, passthrough, sender, state) do
    sentant_id = normalize_identifier(sentant_identifier)

    # Check local first
    if is_local_sentant?(sentant_id) do
      result = send_to_local(sentant_id, event, params, passthrough, sender)
      new_stats = Map.update!(state.stats, :local_sends, &(&1 + 1))
      {:reply, {:ok, :local, result}, %{state | stats: new_stats}}
    else
      # Not found locally — search hive directory for nearest peer with this sentant
      sentant_name = case sentant_identifier do
        %{name: n} -> n
        str when is_binary(str) -> str
        _ -> to_string(sentant_identifier)
      end

      case find_in_hive_directory(sentant_name) do
        {:ok, node_id, _entry} ->
          # Found on a hive peer — route via best transport
          result = send_to_remote_with_transport(node_id, sentant_name, event, params, passthrough, sender)
          new_stats = Map.update!(state.stats, :remote_sends, &(&1 + 1))
          {:reply, {:ok, {:remote, node_id}, result}, %{state | stats: new_stats}}

        {:error, :not_found} ->
          Logger.debug("[PNS Router] Sentant '#{sentant_name}' not found locally or in hive directory")
          {:reply, {:error, :not_found}, state}
      end
    end
  end

  # Handle "hive|sentant" — route to nearest matching sentant in hive
  defp handle_hive_sentant(hive_identifier, sentant_name, event, params, passthrough, sender, state) do
    case find_in_hive_directory_by_hive(hive_identifier, sentant_name) do
      {:ok, node_id, _entry} ->
        result = send_to_remote_with_transport(node_id, sentant_name, event, params, passthrough, sender)
        new_stats = Map.update!(state.stats, :remote_sends, &(&1 + 1))
        {:reply, {:ok, {:remote, node_id}, result}, %{state | stats: new_stats}}

      {:error, :not_found} ->
        # Check if the target is actually local (our hive)
        sentant_id = normalize_identifier(sentant_name)
        if is_local_sentant?(sentant_id) do
          result = send_to_local(sentant_id, event, params, passthrough, sender)
          new_stats = Map.update!(state.stats, :local_sends, &(&1 + 1))
          {:reply, {:ok, :local, result}, %{state | stats: new_stats}}
        else
          Logger.debug("[PNS Router] Sentant '#{sentant_name}' not found in hive '#{hive_identifier}'")
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  # Handle "hive|node|sentant" — route to specific node in hive
  defp handle_hive_node_sentant(_hive_identifier, node_part, sentant_part, event, params, passthrough, sender, state) do
    # Resolve the node within the hive context, then route normally
    handle_specific_node(node_part, sentant_part, event, params, passthrough, sender, state)
  end

  # Handle "@sender" — reply to the original sender
  defp handle_reply_to_sender(event, params, passthrough, sender, state) do
    case sender do
      %{node_id: sender_node_id, sentant_id: sender_sentant_id} when not is_nil(sender_sentant_id) ->
        local_node_id = Reality2.Bootstrap.get(:node_id)
        if sender_node_id == local_node_id do
          result = send_to_local(sender_sentant_id, event, params, passthrough, sender)
          new_stats = Map.update!(state.stats, :local_sends, &(&1 + 1))
          {:reply, {:ok, :local, result}, %{state | stats: new_stats}}
        else
          result = send_to_remote_with_transport(sender_node_id, sender_sentant_id, event, params, passthrough, sender)
          new_stats = Map.update!(state.stats, :remote_sends, &(&1 + 1))
          {:reply, {:ok, {:remote, sender_node_id}, result}, %{state | stats: new_stats}}
        end

      %{sentant_name: sender_name} when not is_nil(sender_name) ->
        # Try to find the sender by name
        handle_local_then_hive(sender_name, event, params, passthrough, sender, state)

      _ ->
        Logger.warning("[PNS Router] @sender used but no sender context available")
        {:reply, {:error, :no_sender_context}, state}
    end
  end

  # Handle "*|sentant" - send to ALL nodes with this sentant
  defp handle_all_nodes(sentant_identifier, event, params, passthrough, sender, state) do
    # Determine if this is a name or UUID
    {is_name, identifier} = case sentant_identifier do
      %{id: id} -> {false, id}
      %{name: name} -> {true, name}
      str when is_binary(str) -> {not uuid?(str), str}
      other -> {false, other}
    end

    # Check local first
    local_sentant_id = if is_name do
      Reality2.Metadata.get(:SentantIDs, identifier)
    else
      if is_local_sentant?(identifier), do: identifier, else: nil
    end

    # Send to local if found
    {local_count, local_results} = if local_sentant_id do
      result = send_to_local(local_sentant_id, event, params, passthrough, sender)
      {1, [{:local, result}]}
    else
      {0, []}
    end

    # Send to all remote peers with matching sentant
    {remote_count, remote_results} = if is_name do
      case find_sentants_by_name_on_peers(identifier) do
        {:ok, matches} ->
          results = Enum.map(matches, fn {sentant_id, node_id} ->
            result = send_to_remote_gatt(node_id, sentant_id, event, params, passthrough, sender)
            {{:remote, node_id}, result}
          end)
          {length(matches), results}

        {:error, _} ->
          {0, []}
      end
    else
      # ID-based: can only be on one remote node
      case find_sentant_by_id_on_peers(identifier) do
        {:ok, node_id} ->
          result = send_to_remote_gatt(node_id, identifier, event, params, passthrough, sender)
          {1, [{{:remote, node_id}, result}]}

        {:error, _} ->
          {0, []}
      end
    end

    all_results = local_results ++ remote_results
    total_sent = local_count + remote_count

    if total_sent > 0 do
      new_stats = state.stats
      |> Map.update!(:local_sends, &(&1 + local_count))
      |> Map.update!(:remote_sends, &(&1 + remote_count))

      {:reply, {:ok, %{local: local_count, remote: remote_count, results: all_results}}, %{state | stats: new_stats}}
    else
      Logger.debug("[PNS Router] Sentant '#{identifier}' not found on any known node")
      {:reply, {:error, :not_found}, state}
    end
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

  # Parse path format:
  # - "*" -> :broadcast_all (all sentants on all nodes)
  # - "sentant" -> {:local_only, sentant}
  # - "*|sentant" -> {:all_nodes, sentant}
  # - "node|sentant" -> {:specific_node, node, sentant}
  # - "hive_name|sentant" -> {:hive_sentant, hive_id_or_name, sentant}
  # - "hive|node|sentant" -> {:hive_node_sentant, hive, node, sentant}
  # - "@sender" -> {:reply_to_sender} (resolved via sender context)
  defp parse_path("*"), do: :broadcast_all
  defp parse_path("@sender"), do: :reply_to_sender
  defp parse_path(path) when is_binary(path) do
    case String.split(path, "|") do
      ["*", sentant_part] ->
        {:all_nodes, sentant_part}

      [part1, part2, part3] ->
        # Three-part: hive|node|sentant
        {:hive_node_sentant, part1, part2, part3}

      [part1, part2] ->
        # Two-part: could be node|sentant or hive|sentant
        # Determine if part1 is a known node (by name or UUID) or a hive identifier
        case classify_identifier(part1) do
          :local_node -> {:specific_node, part1, part2}
          :known_peer -> {:specific_node, part1, part2}
          :hive -> {:hive_sentant, part1, part2}
          :unknown ->
            # Could be either — try node first, fall back to hive
            {:specific_node_or_hive, part1, part2}
        end

      [sentant_only] ->
        {:local_only, sentant_only}
    end
  end

  defp parse_path(%{id: _} = map), do: {:local_only, map}
  defp parse_path(%{name: _} = map), do: {:local_only, map}
  defp parse_path(other), do: {:local_only, other}

  # Classify an identifier as local node, known peer, hive, or unknown
  defp classify_identifier(identifier) do
    local_node_id = Reality2.Bootstrap.get(:node_id)
    local_node_name = Reality2.Bootstrap.get(:node_name)

    cond do
      identifier == local_node_id or identifier == local_node_name ->
        :local_node

      # Check if it's a known peer by name
      Reality2.Metadata.get(:PNS_NodeNames, identifier) != nil ->
        :known_peer

      # Check if it's a known peer by UUID
      uuid?(identifier) and peer_exists?(identifier) ->
        :known_peer

      # Check if it's a hive identifier (name or UUID matches our hive or a trusted hive)
      is_hive_identifier?(identifier) ->
        :hive

      true ->
        :unknown
    end
  end

  defp peer_exists?(node_id) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case AiReality2Transnet.PeerManager.get_peer(node_id) do
        {:ok, _} -> true
        _ -> false
      end
    else
      false
    end
  end

  defp is_hive_identifier?(identifier) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveDirectory) and
       Process.whereis(AiReality2Transnet.HiveDirectory) != nil do
      # Check if it matches our hive name or ID
      case AiReality2Transnet.HiveDirectory.get_directory() do
        %{hive_id: hive_id, hive_name: hive_name} ->
          identifier == hive_id or identifier == hive_name or
          AiReality2Transnet.HiveDirectory.hive_trusted?(identifier)
        _ -> false
      end
    else
      false
    end
  end

  # Resolve a node identifier (name or ID) to node_id
  # Returns the node_id, or nil if not found
  defp resolve_node_identifier(identifier) when is_binary(identifier) do
    local_node_id = Reality2.Bootstrap.get(:node_id)
    local_node_name = Reality2.Bootstrap.get(:node_name)

    cond do
      # Check if it's this node's ID
      identifier == local_node_id ->
        {:local, local_node_id}

      # Check if it's this node's name
      identifier == local_node_name ->
        {:local, local_node_id}

      # Check if it's a UUID (remote node ID)
      uuid?(identifier) ->
        {:remote, identifier}

      # Must be a remote node name - look it up in PNS_NodeNames
      true ->
        case Reality2.Metadata.get(:PNS_NodeNames, identifier) do
          nil -> {:error, :node_not_found}
          node_id -> {:remote, node_id}
        end
    end
  end

  # Resolve a sentant identifier on a specific node
  # For local: use existing lookup
  # For remote: look up in peer's sentant list
  defp resolve_sentant_on_node(sentant_identifier, :local) do
    normalize_identifier(sentant_identifier)
  end

  defp resolve_sentant_on_node(sentant_identifier, {:remote, node_id}) do
    # If it's already a UUID, return it
    if uuid?(sentant_identifier) do
      sentant_identifier
    else
      # It's a name - look it up in the peer's sentant list
      case lookup_sentant_name_on_peer(node_id, sentant_identifier) do
        {:ok, sentant_id} -> sentant_id
        {:error, _} -> sentant_identifier  # Return as-is, will fail on remote
      end
    end
  end

  # Search for ALL sentants by name across all known peers
  # Returns {:ok, [{sentant_id, node_id}, ...]} or {:error, :not_found}
  defp find_sentants_by_name_on_peers(sentant_name) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      peers = AiReality2Transnet.PeerManager.get_all_peers()

      # Search each peer's sentant list for the name - collect ALL matches
      matches = Enum.flat_map(peers, fn {node_id, peer} ->
        peer.sentants
        |> Enum.filter(fn s ->
          name = Map.get(s, :name) || Map.get(s, "name")
          name == sentant_name
        end)
        |> Enum.map(fn s ->
          sentant_id = Map.get(s, :id) || Map.get(s, "id")
          {sentant_id, node_id}
        end)
      end)

      case matches do
        [] -> {:error, :not_found}
        list -> {:ok, list}
      end
    else
      {:error, :transnet_not_available}
    end
  end

  # Search for a sentant by ID across all known peers
  # Returns {:ok, node_id} or {:error, :not_found}
  defp find_sentant_by_id_on_peers(sentant_id) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      peers = AiReality2Transnet.PeerManager.get_all_peers()

      # Search each peer's sentant list for the ID
      result = Enum.find_value(peers, fn {node_id, peer} ->
        found = Enum.any?(peer.sentants, fn s ->
          id = Map.get(s, :id) || Map.get(s, "id")
          id == sentant_id
        end)

        if found, do: {:found, node_id}, else: nil
      end)

      case result do
        {:found, node_id} -> {:ok, node_id}
        nil -> {:error, :not_found}
      end
    else
      {:error, :transnet_not_available}
    end
  end

  # Look up a sentant name on a remote peer
  defp lookup_sentant_name_on_peer(node_id, sentant_name) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case AiReality2Transnet.PeerManager.get_peer(node_id) do
        {:ok, peer} ->
          # Search the sentant list for matching name
          sentant = Enum.find(peer.sentants, fn s ->
            name = Map.get(s, :name) || Map.get(s, "name")
            name == sentant_name
          end)

          case sentant do
            nil -> {:error, :sentant_not_found}
            s -> {:ok, Map.get(s, :id) || Map.get(s, "id")}
          end

        {:error, _} ->
          {:error, :peer_not_found}
      end
    else
      {:error, :transnet_not_available}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Hive Directory Integration (Gap 1, Gap 4, Gap 6, Gap 8 fixes)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Search hive directory for nearest peer with a sentant of the given name
  defp find_in_hive_directory(sentant_name) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveDirectory) and
       Process.whereis(AiReality2Transnet.HiveDirectory) != nil do
      case AiReality2Transnet.HiveDirectory.find_sentant_by_name(sentant_name) do
        [{node_id, entry, _conf} | _] -> {:ok, node_id, entry}
        [] -> {:error, :not_found}
      end
    else
      # Fall back to legacy peer search
      case find_sentants_by_name_on_peers(sentant_name) do
        {:ok, [{sentant_id, node_id} | _]} -> {:ok, node_id, %{sentant_id: sentant_id}}
        _ -> {:error, :not_found}
      end
    end
  end

  # Search hive directory for sentant in a specific hive
  defp find_in_hive_directory_by_hive(hive_identifier, sentant_name) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveDirectory) and
       Process.whereis(AiReality2Transnet.HiveDirectory) != nil do
      case AiReality2Transnet.HiveDirectory.find_sentant_in_hive(hive_identifier, sentant_name) do
        [{node_id, entry, _conf} | _] -> {:ok, node_id, entry}
        [] -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  # Send to remote peer using reachability-aware transport selection (Gap 4, Gap 8 fixes)
  # Instead of always assuming WiFi/GraphQL, uses PeerManager to select best transport
  defp send_to_remote_with_transport(node_id, sentant_identifier, event, params, passthrough, sender) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case AiReality2Transnet.PeerManager.best_transport(node_id) do
        {:ok, :wifi, _info} ->
          # WiFi available — use GraphQL or MeshRouter
          sentant_id = resolve_sentant_on_node(sentant_identifier, {:remote, node_id})
          send_to_remote_gatt(node_id, sentant_id, event, params, passthrough, sender)

        {:ok, transport, _info} when transport in [:ble, :lora] ->
          # BLE or LoRa — route via MeshRouter (transport-agnostic)
          send_via_mesh_router(node_id, sentant_identifier, event, params, passthrough, sender)

        {:error, _} ->
          # Peer not tracked or unreachable — try MeshRouter as last resort
          send_via_mesh_router(node_id, sentant_identifier, event, params, passthrough, sender)
      end
    else
      # PeerManager not available — try direct
      sentant_id = resolve_sentant_on_node(sentant_identifier, {:remote, node_id})
      send_to_remote_gatt(node_id, sentant_id, event, params, passthrough, sender)
    end
  end

  # Send via MeshRouter for non-WiFi transports
  defp send_via_mesh_router(node_id, sentant_identifier, event, params, passthrough, sender) do
    if Code.ensure_loaded?(AiReality2Transnet.MeshRouter) do
      target = "#{node_id}|#{sentant_identifier}"
      full_params = Map.merge(params || %{}, %{_passthrough: passthrough, _sender: sender})

      case AiReality2Transnet.MeshRouter.send_signal("pns_router", target, event, full_params) do
        :ok -> {:ok, %{routed_via: :mesh_router, target: target}}
        error -> error
      end
    else
      {:error, :mesh_router_not_available}
    end
  end

  # Check if a string is a valid UUID
  defp uuid?(str) when is_binary(str) do
    case UUID.info(str) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp uuid?(_), do: false

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

  # Check if a Sentant exists locally
  defp is_local_sentant?(sentant_id) do
    case Sentants.read(%{id: sentant_id}, :definition) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Send to local Sentant
  defp send_to_local(sentant_id, event, parameters, passthrough, sender) do
    Sentants.sendto(%{id: sentant_id}, %{
      event: event,
      parameters: parameters,
      passthrough: passthrough,
      sender: sender
    })
  end

  # Send to remote Sentant - prefers GraphQL for WiFi-connected peers (location-transparent)
  # Falls back to MeshRouter for non-WiFi transports (BLE, LoRa)
  defp send_to_remote_gatt(node_id, sentant_id, event, parameters, passthrough, sender) do
    # Check if transnet modules are available
    with true <- Code.ensure_loaded?(AiReality2Transnet.PeerManager),
         {:ok, peer} <- AiReality2Transnet.PeerManager.get_peer(node_id) do

      # For WiFi-connected peers, use GraphQL directly for transparent event delivery
      # (MeshRouter wraps events in __mesh_signal envelope, breaking transparency)
      if peer.transport == :wifi_hotspot do
        Logger.debug("[PNS Router] Routing to #{sentant_id} on #{peer.node_name || node_id} via GraphQL (WiFi)")
        case send_via_graphql(node_id, sentant_id, event, parameters, passthrough, sender) do
          {:ok, _} = result -> result
          {:error, _} ->
            # GraphQL failed — fall back to MeshRouter
            Logger.debug("[PNS Router] GraphQL failed, falling back to MeshRouter")
            send_via_mesh(node_id, peer, sentant_id, event, parameters, passthrough, sender)
        end
      else
        # Non-WiFi transport — use MeshRouter (BLE, LoRa)
        send_via_mesh(node_id, peer, sentant_id, event, parameters, passthrough, sender)
      end
    else
      false ->
        # MeshRouter not available, try direct GraphQL as fallback
        Logger.debug("[PNS Router] MeshRouter not loaded, using direct GraphQL")
        send_via_graphql_if_available(node_id, sentant_id, event, parameters, passthrough, sender)

      {:error, :not_found} ->
        {:error, :peer_not_found}

      error ->
        error
    end
  end

  # Send via MeshRouter (for non-WiFi transports or as fallback)
  defp send_via_mesh(node_id, peer, sentant_id, event, parameters, passthrough, sender) do
    if Code.ensure_loaded?(AiReality2Transnet.MeshRouter) do
      target = if peer.node_name do
        "#{peer.node_name}|#{sentant_id}"
      else
        "#{node_id}|#{sentant_id}"
      end

      full_params = Map.merge(parameters || %{}, %{_passthrough: passthrough, _sender: sender})

      Logger.debug("[PNS Router] Routing to #{target} via MeshRouter")

      case AiReality2Transnet.MeshRouter.send_signal("pns_router", target, event, full_params) do
        :ok -> {:ok, %{routed_via: :mesh_router, target: target}}
        {:error, :no_transports_available} ->
          Logger.debug("[PNS Router] MeshRouter unavailable, falling back to direct GraphQL")
          send_via_graphql(node_id, sentant_id, event, parameters, passthrough, sender)
        error -> error
      end
    else
      Logger.debug("[PNS Router] MeshRouter not loaded, using direct GraphQL")
      send_via_graphql_if_available(node_id, sentant_id, event, parameters, passthrough, sender)
    end
  end

  # Fallback when MeshRouter isn't available
  defp send_via_graphql_if_available(node_id, sentant_id, event, parameters, passthrough, sender) do
    with true <- Code.ensure_loaded?(AiReality2Transnet.PeerManager),
         {:ok, peer} <- AiReality2Transnet.PeerManager.get_peer(node_id),
         :wifi_hotspot <- peer.transport do
      send_via_graphql(node_id, sentant_id, event, parameters, passthrough, sender)
    else
      :ble_gatt ->
        {:error, :ble_discovery_only}
      _ ->
        {:error, :transnet_not_available}
    end
  end

  # Send command via GraphQL (Reality2Web endpoint on port 4005)
  defp send_via_graphql(node_id, sentant_id, event, parameters, passthrough, sender) do
    # Get peer's IP address from PNS_Peers metadata (stored by ConnectionManager)
    peer_ip = get_peer_ip(node_id)

    if peer_ip do
      Logger.info("[PNS Router] Sending to Sentant #{String.slice(sentant_id, 0..7)}... via GraphQL")

      # Build sender argument for GraphQL (if present)
      sender_arg = if sender do
        """
        , sender: {
            sentant_id: #{if sender[:sentant_id], do: "\"#{sender[:sentant_id]}\"", else: "null"},
            sentant_name: #{if sender[:sentant_name], do: "\"#{sender[:sentant_name]}\"", else: "null"},
            node_id: "#{sender[:node_id]}",
            node_name: "#{sender[:node_name]}"
          }
        """
      else
        ""
      end

      # Build GraphQL mutation
      # Schema: sentantSend(path: String!, event: String!, parameters: JSON, passthrough: JSON, sender: SenderInput)
      params_json = Jason.encode!(Jason.encode!(parameters || %{}))
      passthrough_json = Jason.encode!(Jason.encode!(passthrough))

      mutation = """
      mutation {
        sentantSend(
          path: "#{sentant_id}",
          event: "#{event}",
          parameters: #{params_json},
          passthrough: #{passthrough_json}#{sender_arg}
        ) {
          id
          name
        }
      }
      """

      graphql_request = %{query: mutation}
      url = "https://#{peer_ip}:4005/reality2"
      headers = [{"content-type", "application/json"}]
      body = Jason.encode!(graphql_request)

      case Finch.build(:post, url, headers, body)
           |> Finch.request(Reality2.TransnetHTTPClient, receive_timeout: 5_000) do
        {:ok, %Finch.Response{status: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"data" => %{"sentantSend" => sentant}}} ->
              Logger.debug("[PNS Router] GraphQL command succeeded")
              {:ok, sentant}

            {:ok, %{"errors" => errors}} ->
              Logger.error("[PNS Router] GraphQL errors: #{inspect(errors)}")
              {:error, :graphql_error}

            {:error, _} ->
              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: status}} ->
          Logger.error("[PNS Router] HTTP error #{status}")
          {:error, :http_error}

        {:error, reason} ->
          Logger.error("[PNS Router] Connection failed: #{inspect(reason)}")
          {:error, :connection_failed}
      end
    else
      Logger.error("[PNS Router] Peer has no IP address for GraphQL")
      {:error, :no_ip_address}
    end
  end

  # Get peer IP from PNS_Peers metadata (stored by ConnectionManager)
  defp get_peer_ip(node_id) do
    case Reality2.Metadata.get(:PNS_Peers, node_id) do
      %{peer_ip: ip} -> ip
      _ -> nil
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
