defmodule Reality2.NodeClassRegistry do
  @moduledoc """
  GenServer maintaining aggregate class information from all sentants on this node.

  Tracks: `%{class_string => %{events: [...], signals: [...], sentant_ids: MapSet}}`

  Subscribes to PubSub topics to auto-rebuild when sentants change.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  # -------------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Returns the list of distinct class strings on this node."
  @spec list_classes() :: [String.t()]
  def list_classes do
    GenServer.call(__MODULE__, :list_classes)
  end

  @doc "Returns aggregate events/signals for a specific class."
  @spec class_info(String.t()) :: %{events: [String.t()], signals: [String.t()], sentant_count: non_neg_integer()} | nil
  def class_info(class) do
    GenServer.call(__MODULE__, {:class_info, class})
  end

  @doc "Returns the full class directory: `%{class => %{events, signals, sentant_count}}`."
  @spec class_directory() :: map()
  def class_directory do
    GenServer.call(__MODULE__, :class_directory)
  end

  @doc "Force rebuild from all sentants."
  @spec rebuild() :: :ok
  def rebuild do
    GenServer.cast(__MODULE__, :rebuild)
  end

  # -------------------------------------------------------------------------
  # GenServer Callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Subscribe to sentant lifecycle and class change events
    Phoenix.PubSub.subscribe(Reality2.PubSub, "sentants")
    Phoenix.PubSub.subscribe(Reality2.PubSub, "sentant:classes")

    # Build initial state from existing sentants
    state = do_rebuild()

    Logger.info("[NodeClassRegistry] Started with #{map_size(state)} classes")
    {:ok, state}
  end

  @impl true
  def handle_call(:list_classes, _from, state) do
    {:reply, Map.keys(state), state}
  end

  @impl true
  def handle_call({:class_info, class}, _from, state) do
    case Map.get(state, class) do
      nil -> {:reply, nil, state}
      info -> {:reply, export_class_info(info), state}
    end
  end

  @impl true
  def handle_call(:class_directory, _from, state) do
    directory = Map.new(state, fn {class, info} ->
      {class, export_class_info(info)}
    end)
    {:reply, directory, state}
  end

  @impl true
  def handle_cast(:rebuild, _state) do
    new_state = do_rebuild()
    broadcast_classes_updated(new_state)
    {:noreply, new_state}
  end

  # Sentant created/updated/deleted - rebuild affected classes
  @impl true
  def handle_info({:sentants, _action, _data}, state) do
    new_state = do_rebuild()
    if Map.keys(state) != Map.keys(new_state) do
      broadcast_classes_updated(new_state)
    end
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:class_changed, _data}, state) do
    new_state = do_rebuild()
    if Map.keys(state) != Map.keys(new_state) do
      broadcast_classes_updated(new_state)
    end
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -------------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------------

  defp do_rebuild do
    case Reality2.Sentants.read_all(:definition) do
      {:ok, sentants} ->
        Enum.reduce(sentants, %{}, fn sentant, acc ->
          class = Map.get(sentant, :class) || Map.get(sentant, "class") || "ai.reality2.default"
          id = Map.get(sentant, :id) || Map.get(sentant, "id")

          # Extract event names from automation transitions
          events = extract_events(sentant)
          signals = extract_signals(sentant)

          entry = Map.get(acc, class, %{events: MapSet.new(), signals: MapSet.new(), sentant_ids: MapSet.new()})

          updated = %{
            events: MapSet.union(entry.events, MapSet.new(events)),
            signals: MapSet.union(entry.signals, MapSet.new(signals)),
            sentant_ids: MapSet.put(entry.sentant_ids, id)
          }

          Map.put(acc, class, updated)
        end)

      _ ->
        %{}
    end
  end

  defp extract_events(sentant) do
    events = Map.get(sentant, :events) || Map.get(sentant, "events") || []

    Enum.map(events, fn
      %{event: name} -> name
      %{"event" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_signals(sentant) do
    signals = Map.get(sentant, :signals) || Map.get(sentant, "signals") || []

    Enum.map(signals, fn
      %{signal: name} -> name
      %{name: name} -> name
      %{"signal" => name} -> name
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp export_class_info(info) do
    %{
      events: MapSet.to_list(info.events),
      signals: MapSet.to_list(info.signals),
      sentant_count: MapSet.size(info.sentant_ids)
    }
  end

  defp broadcast_classes_updated(state) do
    class_list = Map.keys(state)
    Phoenix.PubSub.broadcast(Reality2.PubSub, "node:classes", {:classes_updated, class_list})
  end
end
