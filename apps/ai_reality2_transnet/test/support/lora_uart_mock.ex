defmodule AiReality2Transnet.LoRaUartMock do
  @moduledoc """
  Mock for Circuits.UART used in LoRa transport tests.

  Simulates a serial port connection to a LoRa modem (e.g., Arduino MKR WAN 1310).
  Records sent data and can replay received data for testing encode/decode roundtrips.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Returns all data sent to this mock UART"
  def get_sent_data(pid \\ __MODULE__) do
    GenServer.call(pid, :get_sent_data)
  end

  @doc "Simulates receiving data from the UART (LoRa radio)"
  def inject_received(pid \\ __MODULE__, data) do
    GenServer.cast(pid, {:inject, data})
  end

  @doc "Clears all recorded data"
  def reset(pid \\ __MODULE__) do
    GenServer.cast(pid, :reset)
  end

  @doc "Simulates UART.write/2"
  def write(pid \\ __MODULE__, data) do
    GenServer.call(pid, {:write, data})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{sent: [], received: [], listeners: []}}
  end

  @impl true
  def handle_call(:get_sent_data, _from, state) do
    {:reply, Enum.reverse(state.sent), state}
  end

  @impl true
  def handle_call({:write, data}, _from, state) do
    {:reply, :ok, %{state | sent: [data | state.sent]}}
  end

  @impl true
  def handle_cast({:inject, data}, state) do
    # Notify listeners of received data
    Enum.each(state.listeners, fn pid ->
      send(pid, {:circuits_uart, __MODULE__, data})
    end)
    {:noreply, %{state | received: [data | state.received]}}
  end

  @impl true
  def handle_cast(:reset, _state) do
    {:noreply, %{sent: [], received: [], listeners: []}}
  end
end
