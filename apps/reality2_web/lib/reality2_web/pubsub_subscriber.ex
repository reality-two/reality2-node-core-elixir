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
    {:ok, %{}}
  end

  @impl true
  def handle_info({:sentant_signal, signal_data}, state) do
    # Extract data
    %{
      id: id,
      sentant: sentant,
      event: event,
      parameters: parameters,
      passthrough: passthrough
    } = signal_data

    # Prepare subscription data for Absinthe
    subscription_data = %{
      sentant: sentant,
      event: event,
      parameters: parameters,
      passthrough: passthrough
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
  def handle_info(_msg, state) do
    # Ignore unknown messages
    {:noreply, state}
  end
end
