defmodule AiReality2Transnet.Bluetooth do
  # *******************************************************************************************************************************************
  @moduledoc """
  Bluetooth module for Transient Networks.  Calls into the Rust NIFs detailed in AiReality2Transnet.Action.

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  alias Reality2.Sentants, as: Sentants
  alias Reality2.Helpers.R2Map, as: R2Map
  use GenServer, restart: :transient

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    # Find the bluetooth adapter
    adapter =
      case AiReality2Transnet.Action.list_adapters() do
        [] -> nil
        [a | _] -> a
      end

    state = Map.put(state, :adapter, adapter)

    # Find the bluetooth adapter name, defaulting to hci0
    adapter_name =
      case adapter do
        %{id: id} when is_binary(id) -> id
        _ -> "hci0"
      end

    # Start the AltBeacon
    state =
      case start_beacon(state, %{adapter: adapter_name}) do
        {:ok, s} ->
          s

        {:error, reason} ->
          IO.puts("start_beacon failed: #{inspect(reason)}")
          state
      end

    # Start watching for Reality2 Device AltBeacons
    state =
      case start_watch(state, %{adapter: adapter_name}) do
        {:ok, s} ->
          s

        {:error, reason} ->
          IO.puts("start_watch failed: #{inspect(reason)}")
          state
      end

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Stop watcher + beacon using the keys you actually store.
    if h = state[:r2_watch], do: AiReality2Transnet.Action.stop_r2_watch(h)
    if h = state[:altbeacon], do: AiReality2Transnet.Action.stop_altbeacon(h)
    :ok
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_call
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call(%{command: "list_adapters"}, _from, state) do
    {:reply, list_adapters(state), state}
  end

  def handle_call(%{command: "scan_devices", parameters: parameters}, _from, state) do
    {:reply, scan_devices(state, parameters), state}
  end

  def handle_call(%{command: "start_beacon", parameters: parameters}, _from, state) do
    case start_beacon(state, parameters) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(%{command: "stop_beacon", parameters: parameters}, _from, state) do
    {:ok, new_state} = stop_beacon(state, parameters)
    {:reply, :ok, new_state}
  end

  def handle_call(%{command: "start_watch", parameters: parameters}, _from, state) do
    case start_watch(state, parameters) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(%{command: "stop_watch", parameters: parameters}, _from, state) do
    {:ok, new_state} = stop_watch(state, parameters)
    {:reply, :ok, new_state}
  end

  def handle_call(_request, _from, state) do
    IO.puts("Unknown Command #{inspect(state, pretty: true)}")
    {:reply, {:error, :unknown_command}, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_cast
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_cast(%{command: "list_adapters"}, state) do
    list_adapters(state)
    {:noreply, state}
  end

  def handle_cast(%{command: "scan_devices", parameters: parameters}, state) do
    scan_devices(state, parameters)
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_info
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info({:r2_ble_found, node_id, info}, state) do
    IO.puts("Node found: #{node_id}")

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        transport: :bluetooth,
        activity: "r2_node_found",
        node_id: node_id,
        info: info
      }
    })

    {:noreply, state}
  end

  def handle_info({:r2_ble_lost, node_id}, state) do
    IO.puts("Node lost: #{node_id}")

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{transport: :bluetooth, activity: "r2_node_lost", node_id: node_id}
    })

    {:noreply, state}
  end

  def handle_info({:r2_nodes, devices}, state) do
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{transport: :bluetooth, devices: devices}
    })

    {:noreply, Map.put(state, :last_scan, devices)}
  end

  def handle_info(msg, state) do
    IO.warn("Unexpected message received: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def list_adapters(state) do
    adapters = AiReality2Transnet.Action.list_adapters()

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{transport: :bluetooth, adapters: adapters}
    })

    {:ok, state}
  end

  def start_beacon(state, params) do
    node_id = Reality2.Bootstrap.get(:node_id)
    adapter = Map.get(params, :adapter, "hci0")

    case AiReality2Transnet.Action.start_altbeacon(
           0xFFFF,
           node_id,
           1,
           2,
           -59,
           adapter
         ) do
      {:ok, h} ->
        IO.puts("|-- Node ID: #{node_id} beacon started on #{adapter}")
        {:ok, Map.put(state, :altbeacon, h)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop_beacon(state, _params) do
    case Map.get(state, :altbeacon) do
      nil ->
        {:ok, state}

      h ->
        AiReality2Transnet.Action.stop_altbeacon(h)
        {:ok, Map.put(state, :altbeacon, nil)}
    end
  end

  def start_watch(state, params) do
    adapter = Map.get(params, :adapter, "hci0")
    company_id = 0xFFFF
    lost_after_ms = 30_000

    case AiReality2Transnet.Action.start_r2_watch(self(), company_id, adapter, lost_after_ms) do
      {:ok, h} ->
        IO.puts("|-- R2 watch started on #{adapter}")
        {:ok, Map.put(state, :r2_watch, h)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop_watch(state, _params) do
    case Map.get(state, :r2_watch) do
      nil ->
        {:ok, state}

      h ->
        AiReality2Transnet.Action.stop_r2_watch(h)
        {:ok, Map.put(state, :r2_watch, nil)}
    end
  end

  def scan_devices(state, parameters) do
    timeout = R2Map.get(parameters, :timeout, 30000)

    AiReality2Transnet.Action.scan_devices(self(), timeout)

    {:ok, state}
  end
end
