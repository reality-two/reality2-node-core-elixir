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

  ## Returns
  - `:ok` on successful broadcast
  - `false` if the Sentant doesn't exist

  ## Example

      Reality2.Signals.broadcast(sentant_id, "status_changed", %{status: "active"}, %{})
  """
  @spec broadcast(Types.uuid(), any(), map(), map()) :: :ok | false
  def broadcast(id, event, parameters, passthrough) do
    case Reality2.Sentants.read(%{id: id}, :definition) do
      {:ok, sentant} ->
        signal_data = %{
          id: id,
          sentant: sentant,
          event: event,
          parameters: parameters,
          passthrough: passthrough
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
