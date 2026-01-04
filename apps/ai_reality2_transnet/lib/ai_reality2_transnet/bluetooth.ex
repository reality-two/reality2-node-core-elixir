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

  # Default Company ID for R2 manufacturer data.
  # TODO: Replace with an assigned company ID.
  @r2_company_id 0xFFFF

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    # Find the bluetooth adapter (taking the first one)
    # TODO: Handle multiple adapters and/or set adapter to use as an Environment variable
    adapter =
      case AiReality2Transnet.Action.list_adapters_seq() do
        [] -> nil
        [a | _] -> a
      end

    state = Map.put(state, :adapter, adapter)

    # Find the bluetooth adapter name, defaulting to hci0
    adapter_name =
      case adapter do
        %{name: id} when is_binary(id) -> id
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

    # Start watching for other Reality2 Device AltBeacons
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
    # Stop watcher + beacon using the stored keys
    if h = state[:r2_watch], do: AiReality2Transnet.Action.stop_watching(h)
    if h = state[:r2_beacon], do: AiReality2Transnet.Action.stop_broadcast(h)
    :ok
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_call
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true

  def handle_call(_request, _from, state), do: {:reply, {:error, :unknown_command}, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_cast
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_cast(%{command: "list_adapters"}, state) do
    list_adapters(state)
  end

  def handle_cast(%{command: "scan_devices", parameters: parameters}, state) do
    _ = scan_devices(state, parameters)
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_info (mostly return values from calling the Rust NIFs)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true

  # The details of a Reality2 node that has been found nearby.
  def handle_info({:r2_ble_found, id, info}, state) do
    # TODO: notify the pathing Plugin.

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        transport: :bluetooth,
        activity: "r2_node_found",
        id: id,
        info: info
      }
    })

    {:noreply, state}
  end

  # Notice that a Reality2 node is now out of range.
  def handle_info({:r2_ble_lost, id}, state) do
    # TODO: notify the pathing Plugin.

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{transport: :bluetooth, activity: "r2_node_lost", id: id}
    })

    {:noreply, state}
  end

  # List of nodes found during a scan.
  def handle_info({:r2_nodes, devices}, state) do
    # TODO: notify the pathing Plugin (useful for checking and updating).

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{transport: :bluetooth, devices: devices}
    })

    {:noreply, Map.put(state, :last_scan, devices)}
  end

  # Result of asking for a list of adapters.
  def handle_info({:adapters, adapters}, state) do
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{
        transport: :bluetooth,
        adapters: adapters,
        id: Reality2.Bootstrap.get(:node_id)
      }
    })

    {:noreply, state}
  end

  # Catchall error
  def handle_info(_, state), do: {:noreply, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # List the Bluetooth adapters on this device.
  def list_adapters(state) do
    AiReality2Transnet.Action.list_adapters(self())

    {:noreply, state}
  end

  # Do a manual scan for nearby Reality2 Nodes.
  # After the given time, an __internal message is sent to all Sentants with an array of R2 node IDs.
  def scan_devices(state, parameters) do
    timeout = R2Map.get(parameters, :timeout, 30000)

    AiReality2Transnet.Action.scan_devices(self(), timeout)

    {:noreply, state}
  end

  # Start up the BLE beacon on the previously found given adapter.  Uses the ALTBeacon format.
  def start_beacon(state, params) do
    node_id = Reality2.Bootstrap.get(:node_id)
    adapter = Map.get(params, :adapter, "hci0")

    case AiReality2Transnet.Action.start_broadcast(
           @r2_company_id,
           node_id,
           1,
           2,
           -59,
           adapter
         ) do
      {:ok, h} ->
        IO.puts("|-- Node ID: #{node_id} beacon started on #{adapter}")
        {:ok, Map.put(state, :r2_beacon, h)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Stop the prevously started BLE beacon.
  def stop_beacon(state, _params) do
    case Map.get(state, :r2_beacon) do
      nil ->
        {:ok, state}

      h ->
        AiReality2Transnet.Action.stop_broadcast(h)
        {:ok, Map.put(state, :r2_beacon, nil)}
    end
  end

  # Start watching for nearby Reality2 Nodes.
  def start_watch(state, params) do
    adapter = Map.get(params, :adapter, "hci0")
    company_id = 0xFFFF
    lost_after_ms = 30_000

    case AiReality2Transnet.Action.start_watching(self(), company_id, adapter, lost_after_ms) do
      {:ok, h} ->
        IO.puts("|-- R2 watch started on #{adapter}")
        {:ok, Map.put(state, :r2_watch, h)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Stop watching for nearby Reality2 Nodes.
  def stop_watch(state, _params) do
    case Map.get(state, :r2_watch) do
      nil ->
        {:ok, state}

      h ->
        AiReality2Transnet.Action.stop_watching(h)
        {:ok, Map.put(state, :r2_watch, nil)}
    end
  end
end
