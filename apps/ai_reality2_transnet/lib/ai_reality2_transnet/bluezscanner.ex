defmodule AiReality2Transnet.Bluetooth.BlueZScanner do
  @moduledoc """
  BlueZ scanner (system bus) that:
  - starts discovery
  - listens to InterfacesAdded/Removed + PropertiesChanged
  - maintains a device table
  - notifies subscribers on arrival/drop-off
  """

  use GenServer
  require Logger

  @type device_path :: String.t()
  @type mac :: String.t()

  @type device :: %{
          path: device_path(),
          address: mac() | nil,
          alias: String.t() | nil,
          name: String.t() | nil,
          rssi: integer() | nil,
          last_seen_ms: non_neg_integer(),
          props: map()
        }

  # --- Public API

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  def subscribe(server \\ __MODULE__) do
    GenServer.call(server, {:subscribe, self()})
  end

  def unsubscribe(server \\ __MODULE__) do
    GenServer.call(server, {:unsubscribe, self()})
  end

  def list_devices(server \\ __MODULE__) do
    GenServer.call(server, :list_devices)
  end

  # --- GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      adapter: opts[:adapter] || "hci0",
      transport: opts[:transport] || "le",
      scan_interval_ms: opts[:scan_interval_ms] || 30_000,
      stale_after_ms: opts[:stale_after_ms] || 120_000,
      subscribers: MapSet.new(),
      bus: nil,
      # devices keyed by BlueZ object path (stable identifier)
      devices: %{}
    }

    with {:ok, bus} <- dbus_connect_system(),
         :ok <- bluez_configure_and_start_discovery(bus, state.adapter, state.transport),
         :ok <- dbus_subscribe_signals(bus, state.adapter),
         {:ok, devices} <- snapshot_devices(bus, state.adapter) do
      now = now_ms()

      devices =
        devices
        |> Map.new(fn {path, dev} -> {path, Map.put(dev, :last_seen_ms, now)} end)

      state = %{state | bus: bus, devices: devices}

      schedule_tick(state.scan_interval_ms)
      {:ok, state}
    else
      {:error, reason} ->
        Logger.error("BlueZScanner init failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call(:list_devices, _from, state) do
    {:reply, Map.values(state.devices), state}
  end

  @impl true
  def handle_info(:tick, state) do
    # Polling is a safety net. “Drop-off” is computed via our own staleness rule,
    # because BlueZ device objects can persist after discovery.
    now = now_ms()

    state =
      case snapshot_devices(state.bus, state.adapter) do
        {:ok, snap} ->
          state
          |> merge_snapshot(snap, now)
          |> expire_stale(now)

        {:error, reason} ->
          Logger.warning("snapshot_devices failed: #{inspect(reason)}")
          state
      end

    schedule_tick(state.scan_interval_ms)
    {:noreply, state}
  end

  # D-Bus signal: ObjectManager.InterfacesAdded
  # Sent when new objects appear; we care about org.bluez.Device1. :contentReference[oaicite:5]{index=5}
  @impl true
  def handle_info({:dbus_signal, :interfaces_added, path, ifaces_props}, state) do
    case Map.get(ifaces_props, "org.bluez.Device1") do
      nil ->
        {:noreply, state}

      props ->
        now = now_ms()
        dev = normalize_device(path, props, now)

        {state, event} =
          if Map.has_key?(state.devices, path) do
            {%{state | devices: Map.put(state.devices, path, dev)}, {:update, dev}}
          else
            {%{state | devices: Map.put(state.devices, path, dev)}, {:up, dev}}
          end

        notify(state, event)
        {:noreply, state}
    end
  end

  # D-Bus signal: ObjectManager.InterfacesRemoved
  @impl true
  def handle_info({:dbus_signal, :interfaces_removed, path, removed_ifaces}, state) do
    if "org.bluez.Device1" in removed_ifaces and Map.has_key?(state.devices, path) do
      dev = state.devices[path]
      state = %{state | devices: Map.delete(state.devices, path)}
      notify(state, {:down, dev})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # D-Bus signal: Properties.PropertiesChanged for org.bluez.Device1
  # Use this as the primary “seen” indicator. :contentReference[oaicite:6]{index=6}
  @impl true
  def handle_info(
        {:dbus_signal, :properties_changed, path, "org.bluez.Device1", changed, _invalidated},
        state
      ) do
    now = now_ms()

    dev =
      state.devices
      |> Map.get(path, %{
        path: path,
        props: %{},
        last_seen_ms: now,
        address: nil,
        alias: nil,
        name: nil,
        rssi: nil
      })
      |> apply_changed_props(changed, now)

    state = %{state | devices: Map.put(state.devices, path, dev)}
    notify(state, {:update, dev})
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  # --- Internals (device merge / expiry)

  defp merge_snapshot(state, snap, now) do
    # treat snapshot presence as “seen now”
    {added, updated, devices} =
      Enum.reduce(snap, {[], [], state.devices}, fn {path, dev}, {a, u, acc} ->
        dev = Map.put(dev, :last_seen_ms, now)

        if Map.has_key?(acc, path) do
          {a, [dev | u], Map.put(acc, path, merge_dev(acc[path], dev))}
        else
          {[dev | a], u, Map.put(acc, path, dev)}
        end
      end)

    state = %{state | devices: devices}

    Enum.each(added, &notify(state, {:up, &1}))
    Enum.each(updated, &notify(state, {:update, &1}))

    state
  end

  defp expire_stale(state, now) do
    {down, keep} =
      Enum.split_with(state.devices, fn {_path, dev} ->
        now - dev.last_seen_ms > state.stale_after_ms
      end)

    Enum.each(down, fn {_path, dev} -> notify(state, {:down, dev}) end)
    %{state | devices: Map.new(keep)}
  end

  defp merge_dev(old, new) do
    old
    |> Map.merge(new)
    |> Map.update(:props, new.props, &Map.merge(&1, new.props))
  end

  defp apply_changed_props(dev, changed, now) do
    dev =
      dev
      |> Map.update(:props, changed, &Map.merge(&1, changed))
      |> Map.put(:last_seen_ms, now)

    # pull out commonly used fields from the variant map
    dev
    |> maybe_put(:address, changed["Address"])
    |> maybe_put(:name, changed["Name"])
    |> maybe_put(:alias, changed["Alias"])
    |> maybe_put(:rssi, changed["RSSI"])
  end

  defp normalize_device(path, props, now) do
    %{
      path: path,
      address: props["Address"],
      name: props["Name"],
      alias: props["Alias"],
      rssi: props["RSSI"],
      last_seen_ms: now,
      props: props
    }
  end

  defp maybe_put(dev, _k, nil), do: dev
  defp maybe_put(dev, k, v), do: Map.put(dev, k, v)

  defp notify(state, {:up, dev}),
    do: Enum.each(state.subscribers, &send(&1, {:ble_device_up, dev}))

  defp notify(state, {:down, dev}),
    do: Enum.each(state.subscribers, &send(&1, {:ble_device_down, dev}))

  defp notify(state, {:update, dev}),
    do: Enum.each(state.subscribers, &send(&1, {:ble_device_update, dev}))

  defp schedule_tick(ms), do: Process.send_after(self(), :tick, ms)
  defp now_ms(), do: System.monotonic_time(:millisecond)

  # --- BlueZ + D-Bus glue (you implement with your chosen Erlang/Elixir D-Bus binding)

  defp dbus_connect_system() do
    # erlang-dbus example shows getting a bus handle from dbus_bus_reg :contentReference[oaicite:7]{index=7}
    # Adapt to your binding:
    #
    {:ok, bus} = :dbus_bus_reg.get_bus(:system)
    #
    # {:error, :not_implemented}
  end

  defp bluez_configure_and_start_discovery(bus, adapter, transport) do
    adapter_path = "/org/bluez/#{adapter}"

    # Recommended: SetDiscoveryFilter before StartDiscovery :contentReference[oaicite:8]{index=8}
    filters: Transport="le" (BLE-only), DuplicateData=true for more adv updates :contentReference[oaicite:9]{index=9}
    #
    call(bus, "org.bluez", adapter_path, "org.bluez.Adapter1", "SetDiscoveryFilter", [filters])
    call(bus, "org.bluez", adapter_path, "org.bluez.Adapter1", "StartDiscovery", [])

    :ok = bus
    :ok = adapter_path
    :ok = transport
    # {:error, :not_implemented}
  end

  defp snapshot_devices(bus, adapter) do
    _root = "/"
    _service = "org.bluez"
    _iface = "org.freedesktop.DBus.ObjectManager"

    # ObjectManager.GetManagedObjects returns a{oa{sa{sv}}} :contentReference[oaicite:10]{index=10}
    # You then filter objects where map has "org.bluez.Device1". :contentReference[oaicite:11]{index=11}
    :ok = {bus, adapter}
    {:error, :not_implemented}
  end

  defp dbus_subscribe_signals(bus, adapter) do
    # AddMatch rules are the typical mechanism for selecting signals. :contentReference[oaicite:12]{index=12}
    #
    # Suggested match rules (system bus):
    #
    # 1) InterfacesAdded/Removed for org.bluez on "/"
    # "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager',member='InterfacesAdded',path='/'"
    # "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager',member='InterfacesRemoved',path='/'"
    #
    # 2) PropertiesChanged for Device1 within adapter namespace:
    # "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/org/bluez/#{adapter}',arg0='org.bluez.Device1'"
    #
    # Your binding should route incoming signals to this GenServer as:
    # {:dbus_signal, :interfaces_added, path, ifaces_props}
    # {:dbus_signal, :interfaces_removed, path, removed_ifaces}
    # {:dbus_signal, :properties_changed, path, iface_name, changed, invalidated}
    #
    :ok = {bus, adapter}
    {:error, :not_implemented}
  end
end
