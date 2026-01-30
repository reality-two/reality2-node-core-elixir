defmodule Reality2.Signals do
  # *********************************************************************************************************************************************
  @moduledoc """
  Module for broadcasting signals from Sentants.

  This module provides a decoupled way for the core to emit signals that can be
  consumed by any subscriber (GraphQL, GATT, WebSocket, etc.) via PubSub.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """
  # *********************************************************************************************************************************************

  alias Reality2.Types

  @doc """
  Broadcast a signal from a Sentant to all subscribers.

  The signal is published to the "sentant:signals" PubSub topic where any
  interested party (web layer, GATT, etc.) can subscribe and handle it.

  ## Parameters
  - `id` - The UUID of the Sentant emitting the signal
  - `event` - The event name (e.g., "button_pressed", "debug")
  - `parameters` - Map of event parameters
  - `passthrough` - Map of passthrough data
  - `sender` - (optional) Original sender info for reply routing via @sender

  ## Returns
  - `:ok` on successful broadcast
  - `false` if the Sentant doesn't exist

  ## Example

      Reality2.Signals.broadcast(sentant_id, "status_changed", %{status: "active"}, %{})
      Reality2.Signals.broadcast(sentant_id, "response", %{result: "ok"}, %{}, sender)
  """
  @spec broadcast(Types.uuid(), any(), map(), map(), map() | nil) :: :ok | false
  def broadcast(id, event, parameters, passthrough, sender \\ nil) do
    case Reality2.Sentants.read(%{id: id}, :definition) do
      {:ok, sentant} ->
        # Add node attribution to the sentant
        sentant_with_node = Map.merge(sentant, %{
          node_id: Reality2.Bootstrap.get(:node_id),
          node_name: Reality2.Bootstrap.get(:node_name)
        })

        signal_data = %{
          id: id,
          sentant: sentant_with_node,
          event: event,
          parameters: parameters,
          passthrough: passthrough,
          sender: sender
        }

        # Publish to PubSub for all subscribers (GraphQL, GATT, etc.)
        Phoenix.PubSub.broadcast(
          Reality2.PubSub,
          "sentant:signals",
          {:sentant_signal, signal_data}
        )

      {:error, _reason} ->
        false
    end
  end
end
