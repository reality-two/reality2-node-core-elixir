defmodule AiReality2Wfs do
  @moduledoc """
  Reality2 Waggle Finding Service (WFS) - Location-transparent routing for Sentants.

  The WFS provides a unified API for sending events to Sentants regardless of
  their location (local node, remote via GATT, remote via GraphQL, etc.).

  ## Quick Start

      # Send to any Sentant (automatically routed)
      AiReality2Wfs.send_to(sentant_id, "event_name", %{param: "value"})

      # Broadcast to all Sentants
      AiReality2Wfs.broadcast("*", "event_name")

      # Find where a Sentant is located
      AiReality2Wfs.locate(sentant_id)
      #=> {:ok, :local} or {:ok, {:remote, node_id}}

  ## Testing

      # Show routing table
      AiReality2Wfs.Test.show_routing_table()

      # Run integration tests
      AiReality2Wfs.Test.test_integration()

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  @doc """
  Send an event to a Sentant, automatically routing to local or remote.

  ## Parameters
  - `sentant_identifier` - UUID, name, or %{id: uuid} / %{name: name}
  - `event` - Event name string
  - `parameters` - Optional parameters map (default: %{})
  - `passthrough` - Optional passthrough data (default: nil)

  ## Returns
  - `{:ok, :local}` - Sent to local Sentant
  - `{:ok, {:remote, node_id}}` - Sent to remote Sentant
  - `{:error, reason}` - Error occurred

  ## Examples

      # Send by ID
      AiReality2Wfs.send_to("a1b2c3...", "turn_on")

      # Send by name
      AiReality2Wfs.send_to("device1_sensor", "read_temperature", %{unit: "celsius"})

      # Send with passthrough
      AiReality2Wfs.send_to(sentant_id, "ping", %{}, %{source: "test"})
  """
  defdelegate send_to(sentant_identifier, event, parameters \\ %{}, passthrough \\ nil),
    to: AiReality2Wfs.Router,
    as: :send_to_sentant

  @doc """
  Broadcast an event to all Sentants matching a pattern.

  ## Parameters
  - `pattern` - "*" for all, "name_pattern*" for wildcard, or list of IDs/names
  - `event` - Event name
  - `parameters` - Optional parameters (default: %{})
  - `passthrough` - Optional passthrough data (default: nil)

  ## Returns
  - `{:ok, %{local: count, remote: count}}` - Number sent to each type

  ## Examples

      # Broadcast to all
      AiReality2Wfs.broadcast("*", "shutdown")

      # Broadcast to devices matching pattern
      AiReality2Wfs.broadcast("sensor_*", "read_data")

      # Broadcast to specific list
      AiReality2Wfs.broadcast([id1, id2, id3], "sync")
  """
  defdelegate broadcast(pattern, event, parameters \\ %{}, passthrough \\ nil),
    to: AiReality2Wfs.Router

  @doc """
  Find where a Sentant is located.

  ## Parameters
  - `sentant_identifier` - UUID, name, or %{id: uuid} / %{name: name}

  ## Returns
  - `{:ok, :local}` - Sentant is on this node
  - `{:ok, {:remote, node_id}}` - Sentant is on remote node
  - `{:error, :not_found}` - Sentant not found

  ## Example

      case AiReality2Wfs.locate("device1_sensor") do
        {:ok, :local} ->
          IO.puts("Local Sentant")

        {:ok, {:remote, node_id}} ->
          IO.puts("Remote on node: \#{node_id}")

        {:error, :not_found} ->
          IO.puts("Not found")
      end
  """
  defdelegate locate(sentant_identifier), to: AiReality2Wfs.Router

  @doc """
  Get the current routing table with statistics.

  ## Returns
  Map containing:
  - `sentant_locations` - Map of sentant_id => location
  - `peer_sentants` - Map of node_id => [sentant_ids]
  - `stats` - Routing statistics
  - `local_sentant_count` - Number of local Sentants
  - `remote_sentant_count` - Number of remote Sentants
  """
  defdelegate routing_table, to: AiReality2Wfs.Router, as: :get_routing_table

  @doc """
  Force a refresh of the peer topology cache.

  Useful after peer discovery or when testing.
  """
  defdelegate refresh, to: AiReality2Wfs.Router, as: :refresh_topology
end

