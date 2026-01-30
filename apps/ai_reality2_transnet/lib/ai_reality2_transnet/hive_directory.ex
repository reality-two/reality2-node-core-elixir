defmodule AiReality2Transnet.HiveDirectory do
  @moduledoc """
  Distributed, eventually-consistent Hive directory.

  Maintains a local copy of the Hive directory that converges through gossip
  with peer nodes. No central coordinator — all nodes are equal peers.

  ## Data Model

  Each node maintains entries for:
  - All nodes in its own Hive (Tier 1 — full directory)
  - Nodes in trusted Hives (Tier 2 — shared sentants only)
  - Current cell/nearby peers (Tier 3 — presence only)
  - Heard-of nodes (Tier 4 — ephemeral, pruned aggressively)

  ## Merge Semantics (CRDT-inspired, LWW per field)

  - Per-node entries: compare `updated_at` timestamps, take newer
  - Sentant lists: owning node is authoritative
  - Reachability: each observer updates its own observations only
  - Status: `revoked` always wins (tombstone)

  ## Persistence

  Directory is persisted to `.hive/directory.json` and reloaded on boot
  with confidence decay based on elapsed time.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  alias AiReality2Transnet.HiveIdentity

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Constants
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @persist_interval_ms 60_000        # Persist to disk every 60 seconds
  @decay_interval_ms 30_000          # Decay confidence every 30 seconds
  @prune_absent_days 7               # Prune absent nodes after 7 days
  @confidence_decay_rate 0.95        # Multiply confidence by this each decay interval
  @directory_filename "directory.json"

  # Confidence thresholds
  @confidence_wifi_connected 255
  @confidence_ble_seen 200
  @confidence_lora_seen 120
  @confidence_minimum 5              # Below this, considered unreachable

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Types
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc "Reachability info for a single transport"
  @type reachability :: %{
    last_seen: String.t() | nil,
    confidence: non_neg_integer(),
    rssi: integer() | nil,
    ip: String.t() | nil,
    via: binary() | nil
  }

  @typedoc "A node entry in the directory"
  @type node_entry :: %{
    name: String.t(),
    compressed_id: binary(),
    certificate: String.t() | nil,
    status: :active | :absent | :revoked,
    updated_at: String.t(),
    sentants: [map()],
    reachability: %{
      ble: reachability(),
      wifi: reachability(),
      lora: reachability()
    }
  }

  @typedoc "Trust relationship with another Hive"
  @type trusted_hive :: %{
    name: String.t(),
    public_key: String.t(),
    trust_ring: non_neg_integer(),
    established_at: String.t(),
    shared_sentant_filter: [String.t()],
    permissions: [String.t()]
  }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the full directory state.
  """
  @spec get_directory() :: map()
  def get_directory do
    GenServer.call(__MODULE__, :get_directory)
  end

  @doc """
  Returns the current directory version (monotonic counter).
  """
  @spec get_version() :: non_neg_integer()
  def get_version do
    GenServer.call(__MODULE__, :get_version)
  end

  @doc """
  Gets a specific node entry from the directory.
  """
  @spec get_node(String.t()) :: {:ok, node_entry()} | {:error, :not_found}
  def get_node(node_id) do
    GenServer.call(__MODULE__, {:get_node, node_id})
  end

  @doc """
  Gets the compressed ID ↔ full UUID mapping table.
  """
  @spec get_compressed_id_map() :: %{binary() => String.t()}
  def get_compressed_id_map do
    GenServer.call(__MODULE__, :get_compressed_id_map)
  end

  @doc """
  Resolves a compressed ID (4 bytes) to a full node UUID.

  ## Returns
  - `{:ok, node_uuid}` - Found
  - `{:error, :unknown_id}` - Not in lookup table
  """
  @spec resolve_compressed_id(binary()) :: {:ok, String.t()} | {:error, :unknown_id}
  def resolve_compressed_id(compressed) when is_binary(compressed) and byte_size(compressed) == 4 do
    GenServer.call(__MODULE__, {:resolve_compressed_id, compressed})
  end
  def resolve_compressed_id(_), do: {:error, :unknown_id}

  @doc """
  Updates this node's own entry (sentants, name, etc.).

  Each node is authoritative about its own sentants and name.
  """
  @spec update_self(map()) :: :ok
  def update_self(updates) do
    GenServer.cast(__MODULE__, {:update_self, updates})
  end

  @doc """
  Updates reachability for a peer node on a specific transport.

  ## Parameters
  - `node_id` - UUID of the peer
  - `transport` - `:ble` | `:wifi` | `:lora`
  - `reachability_info` - Map with `:confidence`, optional `:rssi`, `:ip`, `:via`
  """
  @spec update_reachability(String.t(), atom(), map()) :: :ok
  def update_reachability(node_id, transport, reachability_info) do
    GenServer.cast(__MODULE__, {:update_reachability, node_id, transport, reachability_info})
  end

  @doc """
  Merges a remote directory into the local one (bidirectional sync).

  Called during WiFi sentant exchange. Uses LWW semantics.

  ## Parameters
  - `remote_directory` - The remote node's directory data

  ## Returns
  - `{:ok, local_directory}` - Merged directory (to send back to remote)
  """
  @spec merge_directory(map()) :: {:ok, map()}
  def merge_directory(remote_directory) do
    GenServer.call(__MODULE__, {:merge_directory, remote_directory})
  end

  @doc """
  Registers or updates a node entry in the directory.

  Used when a peer announces itself or we discover it.
  """
  @spec register_node(String.t(), map()) :: :ok
  def register_node(node_id, node_info) do
    GenServer.cast(__MODULE__, {:register_node, node_id, node_info})
  end

  @doc """
  Finds all nodes in the directory that have a sentant with the given name.

  Returns nodes sorted by best reachability (highest confidence first).

  ## Returns
  - List of `{node_id, node_entry, best_confidence}` tuples, sorted descending by confidence
  """
  @spec find_sentant_by_name(String.t()) :: [{String.t(), node_entry(), non_neg_integer()}]
  def find_sentant_by_name(sentant_name) do
    GenServer.call(__MODULE__, {:find_sentant_by_name, sentant_name})
  end

  @doc """
  Finds all nodes belonging to a specific hive that have a sentant with the given name.

  ## Parameters
  - `hive_identifier` - Hive UUID or Hive name
  - `sentant_name` - Name of the sentant to find

  ## Returns
  - List of `{node_id, node_entry, best_confidence}` tuples, sorted descending by confidence
  """
  @spec find_sentant_in_hive(String.t(), String.t()) :: [{String.t(), node_entry(), non_neg_integer()}]
  def find_sentant_in_hive(hive_identifier, sentant_name) do
    GenServer.call(__MODULE__, {:find_sentant_in_hive, hive_identifier, sentant_name})
  end

  @doc """
  Gets the best transport to reach a given node.

  ## Returns
  - `{:ok, transport_atom, reachability_info}` - Best transport with info
  - `{:error, :unreachable}` - No transport with sufficient confidence
  """
  @spec best_transport_for(String.t()) :: {:ok, atom(), reachability()} | {:error, :unreachable}
  def best_transport_for(node_id) do
    GenServer.call(__MODULE__, {:best_transport_for, node_id})
  end

  @doc """
  Adds a trusted hive relationship.
  """
  @spec add_trusted_hive(String.t(), map()) :: :ok
  def add_trusted_hive(hive_id, trust_info) do
    GenServer.cast(__MODULE__, {:add_trusted_hive, hive_id, trust_info})
  end

  @doc """
  Gets all trusted hives.
  """
  @spec get_trusted_hives() :: map()
  def get_trusted_hives do
    GenServer.call(__MODULE__, :get_trusted_hives)
  end

  @doc """
  Checks if a hive is trusted (Ring 0 or Ring 1).
  """
  @spec hive_trusted?(String.t()) :: boolean()
  def hive_trusted?(hive_id) do
    GenServer.call(__MODULE__, {:hive_trusted?, hive_id})
  end

  @doc """
  Forces a persist of the directory to disk.
  """
  @spec persist!() :: :ok
  def persist! do
    GenServer.call(__MODULE__, :persist)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    data_dir = get_data_dir()

    # Load existing directory or create empty one
    state = case load_directory(data_dir) do
      {:ok, loaded} ->
        Logger.info("[HiveDirectory] Loaded directory: #{map_size(loaded.nodes)} nodes, version #{loaded.directory_version}")
        # Decay confidence based on time since last persist
        decay_all_confidence(loaded)

      {:error, _} ->
        Logger.info("[HiveDirectory] Creating new directory")
        new_directory()
    end

    # Populate our own entry
    state = update_self_entry(state)

    # Schedule periodic tasks
    schedule_persist()
    schedule_decay()

    {:ok, %{directory: state, data_dir: data_dir, compressed_id_map: build_compressed_id_map(state), dirty: false}}
  end

  @impl true
  def handle_call(:get_directory, _from, state) do
    {:reply, state.directory, state}
  end

  @impl true
  def handle_call(:get_version, _from, state) do
    {:reply, state.directory.directory_version, state}
  end

  @impl true
  def handle_call({:get_node, node_id}, _from, state) do
    case Map.get(state.directory.nodes, node_id) do
      nil -> {:reply, {:error, :not_found}, state}
      entry -> {:reply, {:ok, entry}, state}
    end
  end

  @impl true
  def handle_call(:get_compressed_id_map, _from, state) do
    {:reply, state.compressed_id_map, state}
  end

  @impl true
  def handle_call({:resolve_compressed_id, compressed}, _from, state) do
    case Map.get(state.compressed_id_map, compressed) do
      nil -> {:reply, {:error, :unknown_id}, state}
      node_id -> {:reply, {:ok, node_id}, state}
    end
  end

  @impl true
  def handle_call({:merge_directory, remote_dir}, _from, state) do
    merged = merge_directories(state.directory, remote_dir)
    new_map = build_compressed_id_map(merged)
    {:reply, {:ok, export_directory(merged)}, %{state | directory: merged, compressed_id_map: new_map, dirty: true}}
  end

  @impl true
  def handle_call({:find_sentant_by_name, sentant_name}, _from, state) do
    results = do_find_sentant_by_name(state.directory, sentant_name)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:find_sentant_in_hive, hive_identifier, sentant_name}, _from, state) do
    results = do_find_sentant_in_hive(state.directory, hive_identifier, sentant_name)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:best_transport_for, node_id}, _from, state) do
    result = do_best_transport_for(state.directory, node_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_trusted_hives, _from, state) do
    {:reply, state.directory.trusted_hives, state}
  end

  @impl true
  def handle_call({:hive_trusted?, hive_id}, _from, state) do
    # Same hive is always trusted (Ring 0)
    is_same = hive_id == state.directory.hive_id
    is_trusted = Map.has_key?(state.directory.trusted_hives, hive_id)
    {:reply, is_same or is_trusted, state}
  end

  @impl true
  def handle_call(:persist, _from, state) do
    persist_directory(state.directory, state.data_dir)
    {:reply, :ok, %{state | dirty: false}}
  end

  @impl true
  def handle_cast({:update_self, updates}, state) do
    dir = state.directory
    my_node_id = dir.my_node_id
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    current_entry = Map.get(dir.nodes, my_node_id, default_node_entry(my_node_id))
    updated_entry = Map.merge(current_entry, updates)
    updated_entry = %{updated_entry | updated_at: now}

    new_nodes = Map.put(dir.nodes, my_node_id, updated_entry)
    new_dir = %{dir | nodes: new_nodes, directory_version: dir.directory_version + 1}
    new_map = build_compressed_id_map(new_dir)

    {:noreply, %{state | directory: new_dir, compressed_id_map: new_map, dirty: true}}
  end

  @impl true
  def handle_cast({:update_reachability, node_id, transport, reach_info}, state) do
    dir = state.directory
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    current_entry = Map.get(dir.nodes, node_id, default_node_entry(node_id))
    current_reach = Map.get(current_entry, :reachability, default_reachability())
    transport_key = transport

    transport_reach = Map.get(current_reach, transport_key, %{})
    new_transport_reach = Map.merge(transport_reach, %{
      last_seen: now,
      confidence: Map.get(reach_info, :confidence, @confidence_minimum)
    })
    |> maybe_put(:rssi, Map.get(reach_info, :rssi))
    |> maybe_put(:ip, Map.get(reach_info, :ip))
    |> maybe_put(:via, Map.get(reach_info, :via))

    new_reach = Map.put(current_reach, transport_key, new_transport_reach)
    updated_entry = %{current_entry | reachability: new_reach}

    new_nodes = Map.put(dir.nodes, node_id, updated_entry)
    new_dir = %{dir | nodes: new_nodes}

    {:noreply, %{state | directory: new_dir, dirty: true}}
  end

  @impl true
  def handle_cast({:register_node, node_id, node_info}, state) do
    dir = state.directory
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    current_entry = Map.get(dir.nodes, node_id, default_node_entry(node_id))

    # Only update fields that were provided
    updated_entry = current_entry
    |> maybe_update(:name, Map.get(node_info, :name))
    |> maybe_update(:compressed_id, Map.get(node_info, :compressed_id))
    |> maybe_update(:certificate, Map.get(node_info, :certificate))
    |> maybe_update(:status, Map.get(node_info, :status))
    |> maybe_update(:sentants, Map.get(node_info, :sentants))
    |> maybe_update(:hive_id, Map.get(node_info, :hive_id))
    |> Map.put(:updated_at, now)

    new_nodes = Map.put(dir.nodes, node_id, updated_entry)
    new_dir = %{dir | nodes: new_nodes, directory_version: dir.directory_version + 1}
    new_map = build_compressed_id_map(new_dir)

    {:noreply, %{state | directory: new_dir, compressed_id_map: new_map, dirty: true}}
  end

  @impl true
  def handle_cast({:add_trusted_hive, hive_id, trust_info}, state) do
    dir = state.directory
    new_trusted = Map.put(dir.trusted_hives, hive_id, trust_info)
    new_dir = %{dir | trusted_hives: new_trusted, directory_version: dir.directory_version + 1}
    {:noreply, %{state | directory: new_dir, dirty: true}}
  end

  @impl true
  def handle_info(:persist, state) do
    state = if state.dirty do
      persist_directory(state.directory, state.data_dir)
      %{state | dirty: false}
    else
      state
    end
    schedule_persist()
    {:noreply, state}
  end

  @impl true
  def handle_info(:decay, state) do
    dir = decay_all_confidence(state.directory)
    dir = prune_absent_nodes(dir)
    schedule_decay()
    {:noreply, %{state | directory: dir}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    persist_directory(state.directory, state.data_dir)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Directory Operations
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp new_directory do
    my_node_id = Reality2.Bootstrap.get(:node_id, UUID.uuid4())
    my_node_name = Reality2.Bootstrap.get(:node_name, "unknown")

    hive_id = case HiveIdentity.get_hive_id() do
      {:ok, id} -> id
      _ -> nil
    end

    hive_name = case HiveIdentity.get_identity() do
      {:ok, identity} -> identity.name
      _ -> "DefaultHive"
    end

    %{
      hive_id: hive_id,
      hive_name: hive_name,
      my_node_id: my_node_id,
      directory_version: 1,
      nodes: %{
        my_node_id => %{
          name: my_node_name,
          compressed_id: HiveIdentity.compressed_id(my_node_id),
          certificate: nil,
          status: :active,
          updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          sentants: [],
          hive_id: hive_id,
          reachability: default_reachability()
        }
      },
      trusted_hives: %{},
      foreign_nodes: %{}
    }
  end

  defp update_self_entry(directory) do
    my_node_id = Reality2.Bootstrap.get(:node_id, directory.my_node_id)
    my_node_name = Reality2.Bootstrap.get(:node_name, "unknown")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    hive_id = case HiveIdentity.get_hive_id() do
      {:ok, id} -> id
      _ -> directory.hive_id
    end

    # Get current sentants
    sentants = case Reality2.Sentants.read_all(:definition) do
      {:ok, sentant_list} ->
        Enum.map(sentant_list, fn s ->
          %{
            id: Map.get(s, :id, ""),
            name: Map.get(s, :name, ""),
            updated_at: now
          }
        end)
      _ -> []
    end

    current_entry = Map.get(directory.nodes, my_node_id, default_node_entry(my_node_id))
    updated_entry = %{current_entry |
      name: my_node_name,
      compressed_id: HiveIdentity.compressed_id(my_node_id),
      status: :active,
      updated_at: now,
      sentants: sentants,
      hive_id: hive_id
    }

    new_nodes = Map.put(directory.nodes, my_node_id, updated_entry)
    %{directory |
      hive_id: hive_id,
      my_node_id: my_node_id,
      nodes: new_nodes
    }
  end

  defp default_node_entry(node_id) do
    %{
      name: nil,
      compressed_id: HiveIdentity.compressed_id(node_id),
      certificate: nil,
      status: :active,
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      sentants: [],
      hive_id: nil,
      reachability: default_reachability()
    }
  end

  defp default_reachability do
    %{
      ble: %{last_seen: nil, confidence: 0, rssi: nil},
      wifi: %{last_seen: nil, confidence: 0, ip: nil},
      lora: %{last_seen: nil, confidence: 0, via: nil},
      internet: %{last_seen: nil, confidence: 0}
    }
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Merge
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp merge_directories(local, remote) do
    remote_nodes = Map.get(remote, :nodes, %{}) |> ensure_string_keys()
    local_nodes = local.nodes

    merged_nodes = Map.merge(local_nodes, remote_nodes, fn node_id, local_entry, remote_entry ->
      merge_node_entries(node_id, local_entry, remote_entry, local.my_node_id)
    end)

    # Also add any remote nodes we don't have
    new_nodes = Map.merge(remote_nodes, merged_nodes)

    # Merge trusted hives
    remote_trusted = Map.get(remote, :trusted_hives, %{}) |> ensure_string_keys()
    merged_trusted = Map.merge(local.trusted_hives, remote_trusted, fn _hive_id, local_trust, remote_trust ->
      # LWW by established_at
      if compare_timestamps(local_trust[:established_at], remote_trust[:established_at]) == :gt do
        local_trust
      else
        remote_trust
      end
    end)

    %{local |
      nodes: new_nodes,
      trusted_hives: merged_trusted,
      directory_version: local.directory_version + 1
    }
  end

  defp merge_node_entries(node_id, local_entry, remote_entry, my_node_id) do
    local_ts = Map.get(local_entry, :updated_at)
    remote_ts = Map.get(remote_entry, :updated_at)

    # Status: revoked always wins (tombstone)
    merged_status = cond do
      Map.get(remote_entry, :status) == :revoked -> :revoked
      Map.get(local_entry, :status) == :revoked -> :revoked
      true ->
        if compare_timestamps(local_ts, remote_ts) == :gt do
          Map.get(local_entry, :status, :active)
        else
          Map.get(remote_entry, :status, :active)
        end
    end

    # Sentants: the owning node is authoritative
    merged_sentants = if node_id == my_node_id do
      # We are authoritative about our own sentants
      Map.get(local_entry, :sentants, [])
    else
      # Take the newer sentant list
      if compare_timestamps(local_ts, remote_ts) == :gt do
        Map.get(local_entry, :sentants, [])
      else
        Map.get(remote_entry, :sentants, [])
      end
    end

    # Reachability: keep local observations, treat remote as hints (lower confidence)
    local_reach = Map.get(local_entry, :reachability, default_reachability())
    remote_reach = Map.get(remote_entry, :reachability, default_reachability())
    merged_reach = merge_reachability(local_reach, remote_reach)

    # Take newer fields for everything else
    if compare_timestamps(local_ts, remote_ts) == :gt do
      %{local_entry |
        status: merged_status,
        sentants: merged_sentants,
        reachability: merged_reach
      }
    else
      %{remote_entry |
        status: merged_status,
        sentants: merged_sentants,
        reachability: merged_reach
      }
    end
  end

  defp merge_reachability(local_reach, remote_reach) do
    Enum.reduce([:ble, :wifi, :lora, :internet], local_reach, fn transport, acc ->
      local_t = Map.get(acc, transport, %{})
      remote_t = Map.get(remote_reach, transport, %{})

      # Keep the more confident observation
      local_conf = Map.get(local_t, :confidence, 0)
      remote_conf = Map.get(remote_t, :confidence, 0)

      # Remote observations are hints — halve their confidence
      remote_hint_conf = div(remote_conf, 2)

      if local_conf >= remote_hint_conf do
        Map.put(acc, transport, local_t)
      else
        # Use remote but with reduced confidence
        Map.put(acc, transport, %{remote_t | confidence: remote_hint_conf})
      end
    end)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Queries
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp do_find_sentant_by_name(directory, sentant_name) do
    directory.nodes
    |> Enum.filter(fn {_node_id, entry} ->
      entry.status == :active and
      Enum.any?(Map.get(entry, :sentants, []), fn s ->
        Map.get(s, :name) == sentant_name or Map.get(s, "name") == sentant_name
      end)
    end)
    |> Enum.map(fn {node_id, entry} ->
      {node_id, entry, best_confidence(entry)}
    end)
    |> Enum.sort_by(fn {_, _, conf} -> conf end, :desc)
  end

  defp do_find_sentant_in_hive(directory, hive_identifier, sentant_name) do
    # hive_identifier can be a UUID (hive_id) or a name
    is_uuid = uuid?(hive_identifier)

    directory.nodes
    |> Enum.filter(fn {_node_id, entry} ->
      entry.status == :active and
      hive_matches?(entry, hive_identifier, is_uuid) and
      Enum.any?(Map.get(entry, :sentants, []), fn s ->
        Map.get(s, :name) == sentant_name or Map.get(s, "name") == sentant_name
      end)
    end)
    |> Enum.map(fn {node_id, entry} ->
      {node_id, entry, best_confidence(entry)}
    end)
    |> Enum.sort_by(fn {_, _, conf} -> conf end, :desc)
  end

  defp hive_matches?(entry, identifier, true = _is_uuid) do
    Map.get(entry, :hive_id) == identifier
  end

  defp hive_matches?(entry, identifier, false = _is_uuid) do
    # Check if node's hive name matches
    # For own hive nodes, check directory hive_name
    # For foreign nodes, this would require hive_name in the entry
    Map.get(entry, :hive_name) == identifier
  end

  defp best_confidence(entry) do
    reach = Map.get(entry, :reachability, default_reachability())
    Enum.max([
      get_in_safe(reach, [:wifi, :confidence], 0),
      get_in_safe(reach, [:internet, :confidence], 0),
      get_in_safe(reach, [:ble, :confidence], 0),
      get_in_safe(reach, [:lora, :confidence], 0)
    ])
  end

  defp do_best_transport_for(directory, node_id) do
    case Map.get(directory.nodes, node_id) do
      nil -> {:error, :unreachable}
      entry ->
        reach = Map.get(entry, :reachability, default_reachability())

        # Score each transport
        transports = [
          {:wifi, Map.get(reach, :wifi, %{})},
          {:internet, Map.get(reach, :internet, %{})},
          {:ble, Map.get(reach, :ble, %{})},
          {:lora, Map.get(reach, :lora, %{})}
        ]
        |> Enum.map(fn {t, info} -> {t, info, Map.get(info, :confidence, 0)} end)
        |> Enum.filter(fn {_, _, conf} -> conf >= @confidence_minimum end)
        |> Enum.sort_by(fn {_, _, conf} -> conf end, :desc)

        case transports do
          [] -> {:error, :unreachable}
          [{transport, info, _conf} | _] -> {:ok, transport, info}
        end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Confidence Decay & Pruning
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp decay_all_confidence(directory) do
    new_nodes = Map.new(directory.nodes, fn {node_id, entry} ->
      reach = Map.get(entry, :reachability, default_reachability())
      new_reach = Map.new(reach, fn {transport, info} ->
        conf = Map.get(info, :confidence, 0)
        new_conf = trunc(conf * @confidence_decay_rate)
        {transport, %{info | confidence: new_conf}}
      end)
      {node_id, %{entry | reachability: new_reach}}
    end)

    %{directory | nodes: new_nodes}
  end

  defp prune_absent_nodes(directory) do
    cutoff = DateTime.utc_now()
    |> DateTime.add(-@prune_absent_days * 24 * 60 * 60, :second)
    |> DateTime.to_iso8601()

    new_nodes = Enum.reject(directory.nodes, fn {node_id, entry} ->
      # Never prune self
      node_id != directory.my_node_id and
      entry.status == :absent and
      best_confidence(entry) == 0 and
      compare_timestamps(Map.get(entry, :updated_at, ""), cutoff) == :lt
    end)
    |> Map.new()

    %{directory | nodes: new_nodes}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Persistence
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_data_dir do
    Application.get_env(:ai_reality2_transnet, :hive_data_dir, ".hive")
  end

  defp directory_path(data_dir) do
    Path.join(data_dir, @directory_filename)
  end

  defp persist_directory(directory, data_dir) do
    File.mkdir_p!(data_dir)
    path = directory_path(data_dir)

    export = export_directory(directory)

    case Jason.encode(export, pretty: true) do
      {:ok, json} ->
        File.write!(path, json)
        File.chmod(path, 0o600)
        Logger.debug("[HiveDirectory] Persisted directory to #{path}")

      {:error, reason} ->
        Logger.error("[HiveDirectory] Failed to encode directory: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.error("[HiveDirectory] Failed to persist: #{inspect(e)}")
  end

  defp export_directory(directory) do
    # Convert binary compressed IDs to hex strings for JSON
    nodes = Map.new(directory.nodes, fn {node_id, entry} ->
      exported_entry = entry
      |> Map.update(:compressed_id, nil, fn
        cid when is_binary(cid) and byte_size(cid) == 4 -> HiveIdentity.compressed_id_to_hex(cid)
        other -> other
      end)
      |> Map.update(:status, :active, &to_string/1)
      |> Map.update(:reachability, %{}, fn reach ->
        Map.new(reach, fn {transport, info} ->
          {transport, Map.update(info, :via, nil, fn
            v when is_binary(v) and byte_size(v) == 4 -> HiveIdentity.compressed_id_to_hex(v)
            other -> other
          end)}
        end)
      end)

      {node_id, exported_entry}
    end)

    %{
      hive_id: directory.hive_id,
      hive_name: directory.hive_name,
      my_node_id: directory.my_node_id,
      directory_version: directory.directory_version,
      nodes: nodes,
      trusted_hives: directory.trusted_hives,
      persisted_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp load_directory(data_dir) do
    path = directory_path(data_dir)

    with {:ok, json} <- File.read(path),
         {:ok, data} <- Jason.decode(json, keys: :atoms) do

      nodes = Map.get(data, :nodes, %{})
      |> ensure_string_keys()
      |> Map.new(fn {node_id, entry} ->
        imported_entry = entry
        |> Map.put(:compressed_id, import_compressed_id(Map.get(entry, :compressed_id), node_id))
        |> Map.put(:status, import_status(Map.get(entry, :status, "active")))
        |> Map.put(:reachability, import_reachability(Map.get(entry, :reachability, %{})))
        |> Map.put_new(:sentants, [])
        |> Map.put_new(:hive_id, nil)

        {node_id, imported_entry}
      end)

      directory = %{
        hive_id: Map.get(data, :hive_id),
        hive_name: Map.get(data, :hive_name, "DefaultHive"),
        my_node_id: Map.get(data, :my_node_id),
        directory_version: Map.get(data, :directory_version, 1),
        nodes: nodes,
        trusted_hives: Map.get(data, :trusted_hives, %{}) |> ensure_string_keys(),
        foreign_nodes: Map.get(data, :foreign_nodes, %{}) |> ensure_string_keys()
      }

      {:ok, directory}
    else
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  defp import_compressed_id(nil, node_id), do: HiveIdentity.compressed_id(node_id)
  defp import_compressed_id("0x" <> hex, _node_id) do
    case Integer.parse(hex, 16) do
      {value, ""} -> <<value::32>>
      _ -> HiveIdentity.compressed_id(_node_id)
    end
  end
  defp import_compressed_id(cid, _node_id) when is_binary(cid) and byte_size(cid) == 4, do: cid
  defp import_compressed_id(_, node_id), do: HiveIdentity.compressed_id(node_id)

  defp import_status("active"), do: :active
  defp import_status("absent"), do: :absent
  defp import_status("revoked"), do: :revoked
  defp import_status(atom) when is_atom(atom), do: atom
  defp import_status(_), do: :active

  defp import_reachability(reach) when is_map(reach) do
    Map.new([:ble, :wifi, :lora, :internet], fn transport ->
      key = transport
      str_key = to_string(transport)
      info = Map.get(reach, key) || Map.get(reach, str_key) || %{}

      imported = %{
        last_seen: Map.get(info, :last_seen) || Map.get(info, "last_seen"),
        confidence: Map.get(info, :confidence) || Map.get(info, "confidence") || 0,
        rssi: Map.get(info, :rssi) || Map.get(info, "rssi"),
        ip: Map.get(info, :ip) || Map.get(info, "ip"),
        via: Map.get(info, :via) || Map.get(info, "via")
      }

      {transport, imported}
    end)
  end
  defp import_reachability(_), do: default_reachability()

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Compressed ID Map
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp build_compressed_id_map(directory) do
    directory.nodes
    |> Enum.reduce(%{}, fn {node_id, entry}, acc ->
      case Map.get(entry, :compressed_id) do
        cid when is_binary(cid) and byte_size(cid) == 4 ->
          Map.put(acc, cid, node_id)
        _ ->
          acc
      end
    end)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp compare_timestamps(nil, _), do: :lt
  defp compare_timestamps(_, nil), do: :gt
  defp compare_timestamps(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end

  defp uuid?(str) when is_binary(str) do
    case UUID.info(str) do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp ensure_string_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
  defp ensure_string_keys(other), do: other

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_update(map, _key, nil), do: map
  defp maybe_update(map, key, value), do: Map.put(map, key, value)

  defp get_in_safe(map, keys, default) do
    Enum.reduce_while(keys, map, fn key, acc ->
      case acc do
        %{} -> {:cont, Map.get(acc, key)}
        _ -> {:halt, default}
      end
    end) || default
  end

  defp schedule_persist do
    Process.send_after(self(), :persist, @persist_interval_ms)
  end

  defp schedule_decay do
    Process.send_after(self(), :decay, @decay_interval_ms)
  end
end
