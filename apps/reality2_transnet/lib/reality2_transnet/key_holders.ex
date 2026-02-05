defmodule Reality2Transnet.KeyHolders do
  @moduledoc """
  Tracks known trust group key holders across the mesh.

  This module provides visibility into which devices have access to the trust group private key.
  Key holders are discovered via:
  - Local key import (automatically registered)
  - Mesh announcements from other key holders
  - Manual registration via GraphQL

  ## Purpose

  - **Visibility**: Know who can issue certificates
  - **Coordination**: Key holders can coordinate for sensitive operations
  - **Foundation**: Lays groundwork for future consensus requirements

  ## Data Structure

  Key holders are stored in `.r2/key_holders.json`:

      %{
        "node_id" => %{
          node_name: "R2Node_A1B2",
          device_name: "Living Room Hub",
          registered_at: "2024-01-15T10:30:00Z",
          last_seen: "2024-01-15T12:45:00Z",
          is_local: true
        }
      }
  """
  use GenServer
  require Logger

  @filename "key_holders.json"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register the local node as a key holder.
  Called automatically when key is imported or when identity is loaded as key_holder.
  """
  def register_local do
    GenServer.call(__MODULE__, :register_local)
  end

  @doc """
  Register a remote key holder discovered via mesh.
  """
  def register_remote(node_id, node_name, device_name \\ nil) do
    GenServer.call(__MODULE__, {:register_remote, node_id, node_name, device_name})
  end

  @doc """
  Update the last_seen timestamp for a key holder.
  """
  def update_last_seen(node_id) do
    GenServer.call(__MODULE__, {:update_last_seen, node_id})
  end

  @doc """
  Remove a key holder from the registry.
  """
  def remove_key_holder(node_id) do
    GenServer.call(__MODULE__, {:remove, node_id})
  end

  @doc """
  List all known key holders.
  """
  def list_key_holders do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Get the count of known key holders.
  """
  def key_holder_count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Check if a node is a known key holder.
  """
  def is_key_holder?(node_id) do
    GenServer.call(__MODULE__, {:is_key_holder, node_id})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Server Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    data_dir = get_data_dir()
    key_holders = load_key_holders(data_dir)

    Logger.info("[KeyHolders] Initialized with #{map_size(key_holders)} key holder(s)")
    {:ok, %{key_holders: key_holders, data_dir: data_dir}}
  end

  @impl true
  def handle_call(:register_local, _from, state) do
    # Trust the caller - only TrustGroup should call this, and it only calls
    # when it knows it's a key holder. Checking back would cause a deadlock.
    node_id = Reality2.Bootstrap.get(:node_id)
    node_name = Reality2.Bootstrap.get(:node_name)

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Get existing registered_at if this key holder was already registered
    existing = Map.get(state.key_holders, node_id)
    registered_at = if existing, do: Map.get(existing, :registered_at, now), else: now

    entry = %{
      node_name: node_name,
      device_name: nil,
      registered_at: registered_at,
      last_seen: now,
      is_local: true
    }

    updated = Map.put(state.key_holders, node_id, entry)
    save_key_holders(updated, state.data_dir)

    Logger.info("[KeyHolders] Registered local key holder: #{node_name}")
    {:reply, :ok, %{state | key_holders: updated}}
  end

  @impl true
  def handle_call({:register_remote, node_id, node_name, device_name}, _from, state) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    entry = %{
      node_name: node_name,
      device_name: device_name,
      registered_at: Map.get(state.key_holders[node_id], :registered_at, now),
      last_seen: now,
      is_local: false
    }

    updated = Map.put(state.key_holders, node_id, entry)
    save_key_holders(updated, state.data_dir)

    Logger.info("[KeyHolders] Registered remote key holder: #{node_name} (#{node_id})")
    {:reply, :ok, %{state | key_holders: updated}}
  end

  @impl true
  def handle_call({:update_last_seen, node_id}, _from, state) do
    case Map.get(state.key_holders, node_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        updated_entry = %{entry | last_seen: now}
        updated = Map.put(state.key_holders, node_id, updated_entry)
        save_key_holders(updated, state.data_dir)
        {:reply, :ok, %{state | key_holders: updated}}
    end
  end

  @impl true
  def handle_call({:remove, node_id}, _from, state) do
    if Map.has_key?(state.key_holders, node_id) do
      updated = Map.delete(state.key_holders, node_id)
      save_key_holders(updated, state.data_dir)
      Logger.info("[KeyHolders] Removed key holder: #{node_id}")
      {:reply, :ok, %{state | key_holders: updated}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    # Convert to list format for external use
    list = Enum.map(state.key_holders, fn {node_id, entry} ->
      Map.merge(entry, %{node_id: node_id})
    end)
    |> Enum.sort_by(& &1.registered_at)

    {:reply, list, state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, map_size(state.key_holders), state}
  end

  @impl true
  def handle_call({:is_key_holder, node_id}, _from, state) do
    {:reply, Map.has_key?(state.key_holders, node_id), state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_data_dir do
    base = Reality2.Bootstrap.get(:data_dir) || Application.get_env(:reality2, :data_dir) || "."
    Path.join(base, ".r2")
  end

  defp load_key_holders(data_dir) do
    path = Path.join(data_dir, @filename)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, data} when is_map(data) ->
            Logger.info("[KeyHolders] Loaded #{map_size(data)} key holder(s) from #{path}")
            data

          _ ->
            Logger.warning("[KeyHolders] Invalid JSON in #{path}, starting empty")
            %{}
        end

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Logger.warning("[KeyHolders] Failed to read #{path}: #{inspect(reason)}")
        %{}
    end
  end

  defp save_key_holders(key_holders, data_dir) do
    path = Path.join(data_dir, @filename)

    # Ensure directory exists
    File.mkdir_p!(data_dir)

    case Jason.encode(key_holders, pretty: true) do
      {:ok, json} ->
        File.write!(path, json)
        # Set restrictive permissions
        File.chmod(path, 0o600)

      {:error, reason} ->
        Logger.error("[KeyHolders] Failed to encode key holders: #{inspect(reason)}")
    end
  end
end
