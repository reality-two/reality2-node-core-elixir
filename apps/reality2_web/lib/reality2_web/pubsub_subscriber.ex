defmodule Reality2Web.PubSubSubscriber do
  @moduledoc """
  GenServer that subscribes to Phoenix.PubSub events and republishes them
  to Absinthe GraphQL subscriptions.

  This acts as a bridge between the internal PubSub system and GraphQL subscriptions,
  allowing signals from Sentants to be broadcast to both GraphQL and GATT clients.
  """
  use GenServer
  require Logger

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Server Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    # Subscribe to sentant signals
    Phoenix.PubSub.subscribe(Reality2.PubSub, "sentant:signals")
    Logger.info("[Reality2Web.PubSubSubscriber] Subscribed to sentant:signals")

    # Subscribe to trust group join requests (for key holder notifications)
    Phoenix.PubSub.subscribe(Reality2.PubSub, "trust_group:join_requests")
    Logger.info("[Reality2Web.PubSubSubscriber] Subscribed to trust_group:join_requests")

    # Subscribe to proximity events (for key holder proximity prompts)
    Phoenix.PubSub.subscribe(Reality2.PubSub, "trust_group:proximity")
    Logger.info("[Reality2Web.PubSubSubscriber] Subscribed to trust_group:proximity")

    # Subscribe to backup prompts (for key holder first-device notification)
    Phoenix.PubSub.subscribe(Reality2.PubSub, "trust_group:backup_prompt")
    Logger.info("[Reality2Web.PubSubSubscriber] Subscribed to trust_group:backup_prompt")

    # Subscribe to watched signals (cross-node signal forwarding)
    Phoenix.PubSub.subscribe(Reality2.PubSub, "watched:signals")
    Logger.info("[Reality2Web.PubSubSubscriber] Subscribed to watched:signals")

    {:ok, %{}}
  end

  @impl true
  def handle_info({:sentant_signal, signal_data}, state) do
    # Extract data (sender may or may not be present)
    id = Map.get(signal_data, :id)
    sentant = Map.get(signal_data, :sentant)
    event = Map.get(signal_data, :event)
    parameters = Map.get(signal_data, :parameters)
    passthrough = Map.get(signal_data, :passthrough)
    sender = Map.get(signal_data, :sender)

    # Prepare subscription data for Absinthe (includes sender for @sender routing)
    subscription_data = %{
      sentant: sentant,
      event: event,
      parameters: parameters,
      passthrough: passthrough,
      sender: sender
    }

    # Publish to GraphQL subscribers
    Absinthe.Subscription.publish(
      Reality2Web.Endpoint,
      subscription_data,
      await_signal: id <> "|" <> event
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:trust_group_join_request_received, request_id, data}, state) do
    # A new join request has arrived - notify key holder UI
    subscription_data = %{
      request_id: request_id,
      node_id: Map.get(data, :node_id),
      node_name: Map.get(data, :node_name),
      node_public_key: Map.get(data, :node_public_key),
      submitted_at: Map.get(data, :submitted_at),
      source: Atom.to_string(Map.get(data, :source, :unknown))
    }

    # Publish to GraphQL subscribers
    Absinthe.Subscription.publish(
      Reality2Web.Endpoint,
      subscription_data,
      join_request_received: "trust_group:join_requests"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:proximity_device_detected, node_id, data}, state) do
    # A very close device was detected - notify key holder UI for proximity prompting
    subscription_data = %{
      node_id: node_id,
      node_name: Map.get(data, :node_name),
      rssi: Map.get(data, :rssi),
      proximity: Atom.to_string(Map.get(data, :proximity, :unknown)),
      timestamp: Map.get(data, :timestamp)
    }

    # Publish to GraphQL subscribers
    Absinthe.Subscription.publish(
      Reality2Web.Endpoint,
      subscription_data,
      proximity_device_detected: "trust_group:proximity"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:first_device_approved, data}, state) do
    # First device approved - prompt key holder to backup their key
    subscription_data = %{
      device_name: Map.get(data, :device_name),
      trust_group_name: Map.get(data, :trust_group_name),
      trust_group_id: Map.get(data, :trust_group_id),
      timestamp: Map.get(data, :timestamp)
    }

    # Publish to GraphQL subscribers
    Absinthe.Subscription.publish(
      Reality2Web.Endpoint,
      subscription_data,
      backup_prompt_received: "trust_group:backup_prompt"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:watched_signal, signal_data}, state) do
    # A watched signal was received from a remote node - dispatch to GraphQL subscribers
    class = Map.get(signal_data, :class, "*")
    event = Map.get(signal_data, :event, "*")

    # Publish to all matching topic patterns so subscribers with different
    # filter combinations (class only, signal only, both, neither) all receive it
    topics = [
      {"watched:signals:*", true},
      {"watched:signals:#{class}", class != "*"},
      {"watched:signals:*:#{event}", event != "*"},
      {"watched:signals:#{class}:#{event}", class != "*" && event != "*"}
    ]

    Enum.each(topics, fn {topic, should_publish} ->
      if should_publish do
        Absinthe.Subscription.publish(
          Reality2Web.Endpoint,
          signal_data,
          watched_signal: topic
        )
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Ignore unknown messages
    {:noreply, state}
  end
end
