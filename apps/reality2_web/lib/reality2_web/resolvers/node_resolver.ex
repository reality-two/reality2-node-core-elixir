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
      node_name: node_name,
      version: Application.spec(:reality2, :vsn) |> to_string()
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
              address: Map.get(peer, :address) |> to_string_safe(),
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
  # Mutations — hive lifecycle
  # -------------------------------------------------------------------------

  def create_hive(_, %{name: name}, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :reset_hive, [name]) do
        :ok -> {:ok, get_hive_info_result()}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def mark_established(_, _, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :mark_established, []) do
        :ok -> {:ok, get_hive_info_result()}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def generate_join_code(_, _, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :generate_join_code, []) do
        {:ok, code} -> {:ok, %{code: code, expires_in: 300}}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def export_key(_, %{passphrase: passphrase}, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :export_key, [passphrase]) do
        {:ok, encrypted_data} -> {:ok, %{encrypted_data: Base.encode64(encrypted_data)}}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def import_key(_, %{encrypted_data: encrypted_data, passphrase: passphrase}, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case Base.decode64(encrypted_data) do
        {:ok, binary_data} ->
          case apply(AiReality2Transnet.HiveIdentity, :import_key, [binary_data, passphrase]) do
            :ok -> {:ok, get_hive_info_result()}
            {:error, reason} -> {:error, inspect(reason)}
          end
        :error ->
          {:error, "Invalid base64 data"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  # -------------------------------------------------------------------------
  # Mutations — hive joining
  # -------------------------------------------------------------------------

  def get_public_key(_, _, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :get_public_key, []) do
        {:ok, key} -> {:ok, Base.encode64(key)}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def process_join_request(_, %{code: code, node_name: node_name, node_public_key: node_public_key_b64}, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case Base.decode64(node_public_key_b64) do
        {:ok, node_public_key} ->
          node_id = Reality2.Bootstrap.get(:node_id)
          case apply(AiReality2Transnet.HiveIdentity, :process_join_request, [node_id, code, node_name, node_public_key]) do
            {:ok, cert} ->
              # Also return hive public info so the joiner can verify and store it
              case apply(AiReality2Transnet.HiveIdentity, :get_identity, []) do
                {:ok, identity} ->
                  hive_public_info = %{
                    hive_id: identity.hive_id,
                    name: identity.name,
                    public_key: Base.encode64(identity.public_key),
                    created_at: DateTime.to_iso8601(identity.created_at)
                  }
                  {:ok, %{certificate: stringify_keys(cert), hive_public_info: stringify_keys(hive_public_info)}}
                _ ->
                  {:error, "Failed to get hive identity"}
              end
            {:error, reason} -> {:error, inspect(reason)}
          end
        :error ->
          {:error, "Invalid base64 public key"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def join_as_member(_, %{hive_public_info: hive_public_info, certificate: certificate}, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      # Convert string keys from JSON to atoms for HiveIdentity
      hive_info = atomize_keys(hive_public_info)
      cert = atomize_keys(certificate)

      # Convert permissions list from strings to atoms if present
      cert = case Map.get(cert, :permissions) do
        perms when is_list(perms) ->
          Map.put(cert, :permissions, Enum.map(perms, fn
            p when is_binary(p) -> String.to_existing_atom(p)
            p -> p
          end))
        _ -> cert
      end

      # Convert type from string to atom if needed
      cert = case Map.get(cert, :type) do
        t when is_binary(t) -> Map.put(cert, :type, String.to_existing_atom(t))
        _ -> cert
      end

      case apply(AiReality2Transnet.HiveIdentity, :join_as_member, [hive_info, cert]) do
        :ok -> {:ok, get_hive_info_result()}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  # -------------------------------------------------------------------------
  # Mutations — approval-based joining
  # -------------------------------------------------------------------------

  def submit_join_request(_, %{node_name: node_name, node_public_key: node_public_key}, _) do
    request = Reality2Web.JoinRequests.submit(node_name, node_public_key)
    {:ok, %{
      id: request.id,
      node_name: request.node_name,
      node_public_key: request.node_public_key,
      status: Atom.to_string(request.status),
      submitted_at: request.submitted_at
    }}
  end

  def pending_join_requests(_, _, _) do
    requests = Reality2Web.JoinRequests.list_pending()
    result = Enum.map(requests, fn req ->
      %{
        id: req.id,
        node_name: req.node_name,
        node_public_key: req.node_public_key,
        status: Atom.to_string(req.status),
        submitted_at: req.submitted_at
      }
    end)
    {:ok, result}
  end

  def approve_join_request(_, %{request_id: request_id}, _) do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case Reality2Web.JoinRequests.get_status(request_id) do
        {:ok, %{status: :pending, node_name: node_name, node_public_key: node_public_key_b64}} ->
          case Base.decode64(node_public_key_b64) do
            {:ok, node_public_key} ->
              case apply(AiReality2Transnet.HiveIdentity, :issue_cert, [node_name, node_public_key]) do
                {:ok, cert} ->
                  case apply(AiReality2Transnet.HiveIdentity, :get_identity, []) do
                    {:ok, identity} ->
                      hive_public_info = %{
                        hive_id: identity.hive_id,
                        name: identity.name,
                        public_key: Base.encode64(identity.public_key),
                        created_at: DateTime.to_iso8601(identity.created_at)
                      }
                      cert_str = stringify_keys(cert)
                      info_str = stringify_keys(hive_public_info)
                      Reality2Web.JoinRequests.set_result(request_id, cert_str, info_str)
                      {:ok, %{certificate: cert_str, hive_public_info: info_str}}
                    _ ->
                      {:error, "Failed to get hive identity"}
                  end
                {:error, reason} -> {:error, inspect(reason)}
              end
            :error ->
              {:error, "Invalid public key"}
          end

        {:ok, _} -> {:error, "Request is not pending"}
        :not_found -> {:error, "Request not found"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def deny_join_request(_, %{request_id: request_id}, _) do
    case Reality2Web.JoinRequests.deny(request_id) do
      {:ok, _} -> {:ok, true}
      :not_found -> {:error, "Request not found"}
    end
  end

  def join_request_status(_, %{request_id: request_id}, _) do
    case Reality2Web.JoinRequests.get_status(request_id) do
      {:ok, req} ->
        {:ok, %{
          status: Atom.to_string(req.status),
          certificate: req.certificate,
          hive_public_info: req.hive_public_info
        }}
      :not_found ->
        {:error, "Request not found"}
    end
  end

  # -------------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------------

  defp get_hive_info_result do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :get_identity, []) do
        {:ok, identity} ->
          %{
            hive_id: identity.hive_id,
            hive_name: identity.name,
            hive_mode: Atom.to_string(identity.mode),
            is_provisional: Map.get(identity, :provisional, false)
          }

        _ ->
          %{hive_id: nil, hive_name: nil, hive_mode: nil, is_provisional: false}
      end
    else
      %{hive_id: nil, hive_name: nil, hive_mode: nil, is_provisional: false}
    end
  end

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
            hive_compressed_id: compressed,
            is_provisional: Map.get(identity, :provisional, false)
          }

        _ ->
          %{hive_id: nil, hive_name: nil, hive_mode: nil, hive_compressed_id: nil, is_provisional: false}
      end
    else
      %{hive_id: nil, hive_name: nil, hive_mode: nil, hive_compressed_id: nil, is_provisional: false}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {k, stringify_value(v)}
    end)
  end

  defp stringify_value(v) when is_atom(v) and not is_nil(v) and not is_boolean(v), do: Atom.to_string(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v), do: v

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
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
