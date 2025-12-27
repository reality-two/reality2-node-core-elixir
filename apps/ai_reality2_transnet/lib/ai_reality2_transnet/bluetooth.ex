defmodule AiReality2Transnet.Bluetooth do
  alias Reality2.Sentants, as: Sentants
  alias Reality2.Helpers.R2Map, as: R2Map

  # *******************************************************************************************************************************************
  @moduledoc """
  A Bluetooth module for Transient Networks - acts as the
  """

  # *******************************************************************************************************************************************

  @doc false
  use GenServer, restart: :transient

  # -------------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc false
  def init(state) do
    case AiReality2Transnet.Action.list_adapters() do
      [] ->
        {:ok, Map.put(state, :adapter, nil)}

      [adapter | _] ->
        {:ok, Map.put(state, :adapter, adapter)}
    end
  end

  # -------------------------------------------------------------------------------------------------------------------------------------------

  # -------------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # start_scan/1, stop_scan/1, list_connected/0
  # start_advertising/2, stop_advertising/1
  # -------------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def handle_call(%{command: "list_adapters"}, _from, state) do
    {:reply, list_adapters(state), state}
  end

  def handle_call(%{command: "scan_devices", parameters: parameters}, _from, state) do
    {:reply, scan_devices(state, parameters), state}
  end

  def handle_call(_request, _from, state) do
    IO.puts("Unknown Command #{inspect(state, pretty: true)}")
    {:reply, {:error, :unknown_command}, state}
  end

  @doc false
  def handle_cast(%{command: "list_adapters"}, state) do
    list_adapters(state)
    {:noreply, state}
  end

  @doc false
  def handle_cast(%{command: "scan_devices", parameters: parameters}, state) do
    scan_devices(state, parameters)
    {:noreply, state}
  end

  @doc false
  def handle_cast(_, state), do: {:noreply, state}

  @doc false
  def handle_info({:ok, devices}, state) do
    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{transport: :bluetooth, devices: devices}
    })

    {:noreply, Map.put(state, :last_scan, devices)}
  end

  @doc false
  def handle_info(msg, state) do
    IO.warn("Unexpected message received: #{inspect(msg)}")
    {:noreply, state}
  end

  # -------------------------------------------------------------------------------------------------------------------------------------------

  # -------------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -------------------------------------------------------------------------------------------------------------------------------------------

  def list_adapters(state) do
    adapters = AiReality2Transnet.Action.list_adapters()

    Sentants.sendto_all(%{
      event: "__internal",
      parameters: %{transport: :bluetooth, adapters: adapters}
    })

    {:ok, state}
  end

  def scan_devices(state, parameters) do
    timeout = R2Map.get(parameters, :timeout, 10000)

    AiReality2Transnet.Action.scan_devices(self(), timeout)

    {:ok, state}
  end

  # -------------------------------------------------------------------------------------------------------------------------------------------
end
