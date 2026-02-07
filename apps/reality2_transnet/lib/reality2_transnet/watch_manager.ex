defmodule Reality2Transnet.WatchManager do
  @moduledoc """
  Lease-based cross-node signal watch manager.

  Manages watches that allow remote nodes to subscribe to signals from sentants
  of a particular class on this node. Watches have transport-dependent lease
  durations and expire automatically if not renewed.

  ## Lease Durations
  - BLE: 90 seconds
  - WiFi: 120 seconds
  - LoRa: 300 seconds

  ## Reserved Events
  - `__watch` / `__unwatch` - internal events for watch lifecycle

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  @cleanup_interval_ms 30_000

  # Lease durations per transport (milliseconds)
  @lease_durations %{
    ble: 90_000,
    wifi: 120_000,
    lora: 300_000
  }

  @default_lease_ms 120_000

  # -------------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a watch: the watcher node wants to receive signals matching
  the given class and signal name from sentants on this node.

  ## Returns
  - `{:ok, watch_id}` - Watch registered
  """
  @spec watch(String.t(), String.t(), String.t(), atom()) :: {:ok, String.t()}
  def watch(watcher_node_id, class, signal, transport \\ :wifi) do
    GenServer.call(__MODULE__, {:watch, watcher_node_id, class, signal, transport})
  end

  @doc "Remove a specific watch."
  @spec unwatch(String.t(), String.t(), String.t()) :: :ok
  def unwatch(watcher_node_id, class, signal) do
    GenServer.cast(__MODULE__, {:unwatch, watcher_node_id, class, signal})
  end

  @doc "Renew all watches from a given node (piggybacked on transport keepalive)."
  @spec renew(String.t()) :: :ok
  def renew(watcher_node_id) do
    GenServer.cast(__MODULE__, {:renew, watcher_node_id})
  end

  @doc "Remove all watches for a node (cleanup on disconnect)."
  @spec remove_all_for_node(String.t()) :: :ok
  def remove_all_for_node(watcher_node_id) do
    GenServer.cast(__MODULE__, {:remove_all_for_node, watcher_node_id})
  end

  @doc """
  Find all watchers interested in signals from the given class+signal.

  ## Returns
  List of `%{watcher_node_id, watch_id, transport}` maps.
  """
  @spec watchers_for(String.t(), String.t()) :: [map()]
  def watchers_for(class, signal) do
    GenServer.call(__MODULE__, {:watchers_for, class, signal})
  end

  @doc "List all active watches."
  @spec list_watches() :: [map()]
  def list_watches do
    GenServer.call(__MODULE__, :list_watches)
  end

  # -------------------------------------------------------------------------
  # GenServer Callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    schedule_cleanup()
    Logger.info("[WatchManager] Started")
    {:ok, %{watches: %{}}}
  end

  @impl true
  def handle_call({:watch, watcher_node_id, class, signal, transport}, _from, state) do
    watch_id = UUID.uuid4()
    lease_ms = Map.get(@lease_durations, transport, @default_lease_ms)
    now = System.system_time(:millisecond)

    watch = %{
      watch_id: watch_id,
      watcher_node_id: watcher_node_id,
      class: class,
      signal: signal,
      transport: transport,
      lease_ms: lease_ms,
      expires_at: now + lease_ms,
      created_at: now
    }

    new_watches = Map.put(state.watches, watch_id, watch)
    Logger.info("[WatchManager] Watch created: #{watcher_node_id} -> #{class}/#{signal} (lease #{div(lease_ms, 1000)}s)")
    {:reply, {:ok, watch_id}, %{state | watches: new_watches}}
  end

  @impl true
  def handle_call({:watchers_for, class, signal}, _from, state) do
    now = System.system_time(:millisecond)

    watchers = state.watches
    |> Map.values()
    |> Enum.filter(fn w ->
      w.class == class and w.signal == signal and w.expires_at > now
    end)
    |> Enum.map(fn w ->
      %{watcher_node_id: w.watcher_node_id, watch_id: w.watch_id, transport: w.transport}
    end)

    {:reply, watchers, state}
  end

  @impl true
  def handle_call(:list_watches, _from, state) do
    now = System.system_time(:millisecond)
    watches = state.watches
    |> Map.values()
    |> Enum.filter(fn w -> w.expires_at > now end)
    {:reply, watches, state}
  end

  @impl true
  def handle_cast({:unwatch, watcher_node_id, class, signal}, state) do
    new_watches = state.watches
    |> Enum.reject(fn {_id, w} ->
      w.watcher_node_id == watcher_node_id and w.class == class and w.signal == signal
    end)
    |> Map.new()

    {:noreply, %{state | watches: new_watches}}
  end

  @impl true
  def handle_cast({:renew, watcher_node_id}, state) do
    now = System.system_time(:millisecond)

    new_watches = Map.new(state.watches, fn {id, w} ->
      if w.watcher_node_id == watcher_node_id do
        {id, %{w | expires_at: now + w.lease_ms}}
      else
        {id, w}
      end
    end)

    {:noreply, %{state | watches: new_watches}}
  end

  @impl true
  def handle_cast({:remove_all_for_node, watcher_node_id}, state) do
    {removed, remaining} = Map.split_with(state.watches, fn {_id, w} ->
      w.watcher_node_id == watcher_node_id
    end)

    if map_size(removed) > 0 do
      Logger.info("[WatchManager] Removed #{map_size(removed)} watches for disconnected node #{String.slice(watcher_node_id, 0..7)}...")
    end

    {:noreply, %{state | watches: Map.new(remaining)}}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = System.system_time(:millisecond)
    {expired, active} = Map.split_with(state.watches, fn {_id, w} ->
      w.expires_at <= now
    end)

    if map_size(expired) > 0 do
      Logger.debug("[WatchManager] Expired #{map_size(expired)} watches")
    end

    schedule_cleanup()
    {:noreply, %{state | watches: Map.new(active)}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -------------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------------

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end
end
