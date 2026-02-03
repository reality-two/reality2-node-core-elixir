defmodule Reality2Web.SentantResolver.PathResolver do
  @moduledoc false
  # Path parsing and node/sentant reference resolution for the SentantResolver.
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)

  require Logger

  # Parse path to determine if local or remote
  # Accepts: UUID, name, node|sentant (using names or UUIDs in either position)
  # Returns {:remote, node_ref, sentant_ref} or {:local, sentant_ref}
  @doc false
  def parse_path(path) do
    local_node_id = Reality2.Bootstrap.get(:node_id)

    case String.split(path, "|", parts: 2) do
      [node_ref, sentant_ref] ->
        # Resolve node reference to ID (could be UUID or name)
        resolved_node_id = resolve_node_ref(node_ref)

        if resolved_node_id == local_node_id do
          # Local node - resolve sentant ref
          {:local, resolve_sentant_ref(sentant_ref)}
        else
          # Remote node
          {:remote, resolved_node_id || node_ref, sentant_ref}
        end

      [sentant_ref] ->
        # No separator - local sentant (could be UUID or name)
        {:local, sentant_ref}
    end
  end

  # Resolve a node reference (UUID or name) to node ID
  @doc false
  def resolve_node_ref(ref) do
    local_node_id = Reality2.Bootstrap.get(:node_id)
    local_node_name = Reality2.Bootstrap.get(:node_name)

    cond do
      ref == local_node_id -> local_node_id
      ref == local_node_name -> local_node_id
      is_uuid?(ref) -> ref
      true ->
        # Try to look up by name in PeerManager
        if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
          case apply(Reality2Transnet.PeerManager, :get_peer_by_name, [ref]) do
            {:ok, peer} -> Map.get(peer, :node_id)
            _ -> nil
          end
        else
          nil
        end
    end
  end

  # Resolve a sentant reference (UUID or name) to sentant ID
  @doc false
  def resolve_sentant_ref(ref) do
    if is_uuid?(ref) do
      ref
    else
      # Try to look up by name locally
      case Reality2.Metadata.get(:SentantIDs, ref) do
        nil -> ref  # Return as-is, let downstream handle it
        id -> id
      end
    end
  end

  # Check if a string looks like a UUID
  @doc false
  def is_uuid?(str) do
    case UUID.info(str) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
