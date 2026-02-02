defmodule Reality2Web.NodeResolver do
  @moduledoc false
  # Resolver for node identity, peers, and hive directory queries.

  # -------------------------------------------------------------------------
  # nodeInfo — this node's identity and hive membership
  # -------------------------------------------------------------------------

  def node_info(_, _, _) do
    node_id = Reality2.Bootstrap.get(:node_id)
    node_name = Reality2.Bootstrap.get(:node_name)

    hive_info = get_hive_info()

    {:ok, Map.merge(%{
      node_id: node_id,
      node_name: node_name
    }, hive_info)}
  end

  # -------------------------------------------------------------------------
  # peers — discovered peers from the mesh (PeerManager)
  # -------------------------------------------------------------------------

  def peers(_, _, _) do
    if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
      case apply(AiReality2Transnet.PeerManager, :get_all_peers, []) do
        peers when is_map(peers) ->
          result = Enum.map(peers, fn {peer_id, peer} ->
            %{
              node_id: peer_id,
              node_name: Map.get(peer, :node_name),
              transport: peer |> Map.get(:transport) |> to_string_safe(),
              rssi: Map.get(peer, :rssi),
              connection_state: peer |> Map.get(:connection_state) |> to_string_safe(),
              hive_id: Map.get(peer, :hive_id),
              is_same_hive: Map.get(peer, :is_same_hive, false),
              hive_verified: Map.get(peer, :hive_verified, false),
              sentant_count: peer |> Map.get(:sentants, []) |> length(),
              last_seen: format_timestamp(Map.get(peer, :last_seen)),
              reachability: format_reachability(Map.get(peer, :reachability))
            }
          end)
          {:ok, result}

        _ ->
          {:ok, []}
      end
    else
      {:ok, []}
    end
  end

  # -------------------------------------------------------------------------
  # hiveDirectory — distributed directory of all known hive nodes
  # -------------------------------------------------------------------------

  def hive_directory(_, _, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveDirectory) do
      case apply(AiReality2Transnet.HiveDirectory, :get_directory, []) do
        dir when is_map(dir) ->
          nodes_map = Map.get(dir, :nodes, %{})

          nodes = Enum.map(nodes_map, fn {node_id, entry} ->
            %{
              node_id: node_id,
              name: Map.get(entry, :name),
              status: entry |> Map.get(:status, :active) |> to_string_safe(),
              hive_id: Map.get(entry, :hive_id),
              sentants: Enum.map(Map.get(entry, :sentants, []), fn s ->
                %{
                  id: Map.get(s, :id) || Map.get(s, "id", ""),
                  name: Map.get(s, :name) || Map.get(s, "name", "")
                }
              end),
              reachability: format_reachability(Map.get(entry, :reachability)),
              updated_at: Map.get(entry, :updated_at)
            }
          end)

          {:ok, %{
            hive_id: Map.get(dir, :hive_id),
            hive_name: Map.get(dir, :hive_name),
            my_node_id: Map.get(dir, :my_node_id),
            directory_version: Map.get(dir, :directory_version, 0),
            nodes: nodes
          }}

        _ ->
          {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  # -------------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------------

  defp get_hive_info do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :get_identity, []) do
        {:ok, identity} ->
          compressed = case apply(AiReality2Transnet.HiveIdentity, :get_hive_compressed_id, []) do
            {:ok, cid} -> Base.encode16(cid, case: :lower)
            _ -> nil
          end

          %{
            hive_id: identity.hive_id,
            hive_name: identity.name,
            hive_mode: Atom.to_string(identity.mode),
            hive_compressed_id: compressed
          }

        _ ->
          %{hive_id: nil, hive_name: nil, hive_mode: nil, hive_compressed_id: nil}
      end
    else
      %{hive_id: nil, hive_name: nil, hive_mode: nil, hive_compressed_id: nil}
    end
  end

  defp to_string_safe(nil), do: nil
  defp to_string_safe(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp to_string_safe(str) when is_binary(str), do: str
  defp to_string_safe(other), do: inspect(other)

  # Convert unix millisecond timestamp to ISO8601
  defp format_timestamp(nil), do: nil
  defp format_timestamp(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_iso8601()
  end
  defp format_timestamp(str) when is_binary(str), do: str

  defp format_reachability(nil), do: nil
  defp format_reachability(reach) when is_map(reach) do
    %{
      ble: format_transport(Map.get(reach, :ble)),
      wifi: format_transport(Map.get(reach, :wifi)),
      lora: format_transport(Map.get(reach, :lora)),
      internet: format_transport(Map.get(reach, :internet))
    }
  end

  defp format_transport(nil), do: nil
  defp format_transport(t) when is_map(t) do
    %{
      last_seen: Map.get(t, :last_seen),
      confidence: Map.get(t, :confidence, 0),
      rssi: Map.get(t, :rssi),
      ip: Map.get(t, :ip)
    }
  end
end
