defmodule Reality2Web.NodeResolver do
  @moduledoc false
  # Resolver for node identity, peers, and trust group directory queries.

  # -------------------------------------------------------------------------
  # nodeInfo — this node's identity and trust group membership
  # -------------------------------------------------------------------------

  def node_info(_, _, _) do
    node_id = Reality2.Bootstrap.get(:node_id)
    node_name = Reality2.Bootstrap.get(:node_name)

    trust_group_info = get_trust_group_info()

    {:ok, Map.merge(%{
      node_id: node_id,
      node_name: node_name,
      version: Application.spec(:reality2, :vsn) |> to_string(),
      build_id: read_build_id()
    }, trust_group_info)}
  end

  @git_commit (case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
    {hash, 0} -> String.trim(hash)
    _ -> "unknown"
  end)

  defp read_build_id do
    # In a release, GIT_COMMIT is written by make_runtime into the release root.
    # In dev mode, fall back to the git commit captured at compile time.
    release_root = Application.app_dir(:reality2_web, "../..") |> Path.expand()
    path = Path.join(release_root, "GIT_COMMIT")
    case File.read(path) do
      {:ok, content} -> String.trim(content)
      _ -> @git_commit
    end
  end

  # -------------------------------------------------------------------------
  # peers — discovered peers from the mesh (PeerManager)
  # -------------------------------------------------------------------------

  def peers(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.PeerManager) do
      case apply(Reality2Transnet.PeerManager, :get_all_peers, []) do
        peers when is_map(peers) ->
          result = Enum.map(peers, fn {peer_id, peer} ->
            %{
              node_id: peer_id,
              node_name: Map.get(peer, :node_name),
              transport: peer |> Map.get(:transport) |> to_string_safe(),
              address: Map.get(peer, :address) |> to_string_safe(),
              rssi: Map.get(peer, :rssi),
              connection_state: peer |> Map.get(:connection_state) |> to_string_safe(),
              trust_group_id: Map.get(peer, :trust_group_id),
              is_same_trust_group: Map.get(peer, :is_same_trust_group, false),
              trust_group_verified: Map.get(peer, :trust_group_verified, false),
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
  # trustGroupDirectory — distributed directory of all known trust group nodes
  # -------------------------------------------------------------------------

  def trust_group_directory(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroupDirectory) do
      case apply(Reality2Transnet.TrustGroupDirectory, :get_directory, []) do
        dir when is_map(dir) ->
          nodes_map = Map.get(dir, :nodes, %{})

          nodes = Enum.map(nodes_map, fn {node_id, entry} ->
            %{
              node_id: node_id,
              name: Map.get(entry, :name),
              status: entry |> Map.get(:status, :active) |> to_string_safe(),
              trust_group_id: Map.get(entry, :trust_group_id),
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
            trust_group_id: Map.get(dir, :trust_group_id),
            trust_group_name: Map.get(dir, :trust_group_name),
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
  # Mutations — trust group lifecycle
  # -------------------------------------------------------------------------

  def create_trust_group(_, %{name: name}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :reset_trust_group, [name]) do
        :ok -> {:ok, get_trust_group_info_result()}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def mark_established(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :mark_established, []) do
        :ok -> {:ok, get_trust_group_info_result()}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def generate_join_code(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :generate_join_code, []) do
        {:ok, code} -> {:ok, %{code: code, expires_in: 300}}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def export_key(_, %{passphrase: passphrase}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :export_key, [passphrase]) do
        {:ok, encrypted_data} -> {:ok, %{encrypted_data: Base.encode64(encrypted_data)}}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def import_key(_, %{encrypted_data: encrypted_data, passphrase: passphrase}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case Base.decode64(encrypted_data) do
        {:ok, binary_data} ->
          case apply(Reality2Transnet.TrustGroup, :import_key, [binary_data, passphrase]) do
            :ok -> {:ok, get_trust_group_info_result()}
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
  # Mutations — trust group joining
  # -------------------------------------------------------------------------

  def get_public_key(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :get_public_key, []) do
        {:ok, key} -> {:ok, Base.encode64(key)}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def process_join_request(_, %{code: code, node_name: node_name, node_public_key: node_public_key_b64}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case Base.decode64(node_public_key_b64) do
        {:ok, node_public_key} ->
          node_id = Reality2.Bootstrap.get(:node_id)
          case apply(Reality2Transnet.TrustGroup, :process_join_request, [node_id, code, node_name, node_public_key]) do
            {:ok, cert} ->
              # Also return trust group public info so the joiner can verify and store it
              case apply(Reality2Transnet.TrustGroup, :get_identity, []) do
                {:ok, identity} ->
                  trust_group_public_info = %{
                    trust_group_id: identity.trust_group_id,
                    name: identity.name,
                    public_key: Base.encode64(identity.public_key),
                    created_at: DateTime.to_iso8601(identity.created_at)
                  }
                  {:ok, %{certificate: stringify_keys(cert), trustGroupInfo: stringify_keys(trust_group_public_info)}}
                _ ->
                  {:error, "Failed to get trust group identity"}
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

  def join_as_member(_, %{trustGroupInfo: trust_group_public_info, certificate: certificate}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      # Convert string keys from JSON to atoms for TrustGroup
      trust_group_info = atomize_keys(trust_group_public_info)
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

      case apply(Reality2Transnet.TrustGroup, :join_as_member, [trust_group_info, cert]) do
        :ok -> {:ok, get_trust_group_info_result()}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  # -------------------------------------------------------------------------
  # Mutations — approval-based joining
  # -------------------------------------------------------------------------

  @join_requests Reality2Transnet.JoinRequests

  def submit_join_request(_, %{node_name: node_name, node_public_key: node_public_key}, _) do
    case apply(@join_requests, :submit, [node_name, node_public_key]) do
      {:error, :rate_limited} ->
        {:error, "Too many pending join requests"}

      request when is_map(request) ->
        # Broadcast to notify key holder UI of new join request
        Phoenix.PubSub.broadcast(Reality2.PubSub, "trust_group:join_requests", {
          :trust_group_join_request_received, request.id, %{
            node_id: nil,  # Not available in GraphQL flow
            node_name: request.node_name,
            node_public_key: request.node_public_key,
            submitted_at: request.submitted_at,
            source: :graphql
          }
        })

        {:ok, %{
          id: request.id,
          node_name: request.node_name,
          node_public_key: request.node_public_key,
          status: Atom.to_string(request.status),
          submitted_at: request.submitted_at
        }}
    end
  end

  def pending_join_requests(_, _, _) do
    requests = apply(@join_requests, :list_pending, [])
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
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(@join_requests, :get_status, [request_id]) do
        {:ok, %{status: :pending, node_name: node_name, node_public_key: node_public_key_b64}} ->
          case Base.decode64(node_public_key_b64) do
            {:ok, node_public_key} ->
              case apply(Reality2Transnet.TrustGroup, :issue_cert, [node_name, node_public_key]) do
                {:ok, cert} ->
                  case apply(Reality2Transnet.TrustGroup, :get_identity, []) do
                    {:ok, identity} ->
                      trust_group_public_info = %{
                        trust_group_id: identity.trust_group_id,
                        name: identity.name,
                        public_key: Base.encode64(identity.public_key),
                        created_at: DateTime.to_iso8601(identity.created_at)
                      }
                      cert_str = stringify_keys(cert)
                      info_str = stringify_keys(trust_group_public_info)
                      apply(@join_requests, :set_result, [request_id, cert_str, info_str])

                      # Register as trust group member (viewer type for BLE-joined devices)
                      node_id = Map.get(cert, :node_id) || request_id
                      if Code.ensure_loaded?(Reality2Transnet.TrustGroupMembers) do
                        apply(Reality2Transnet.TrustGroupMembers, :add_member, [
                          node_id,
                          node_name,
                          node_public_key_b64,
                          cert_str,
                          :viewer
                        ])

                        # Check if this is the first device approved - prompt for backup
                        members = apply(Reality2Transnet.TrustGroupMembers, :list_members, [])
                        if length(members) == 1 do
                          Phoenix.PubSub.broadcast(Reality2.PubSub, "trust_group:backup_prompt", {
                            :first_device_approved, %{
                              device_name: node_name,
                              trust_group_name: identity.name,
                              trust_group_id: identity.trust_group_id,
                              timestamp: System.system_time(:second)
                            }
                          })
                        end
                      end

                      # Broadcast result via PubSub so Bluetooth can relay over GATT
                      Phoenix.PubSub.broadcast(Reality2.PubSub, "trust_group:join_results", {
                        :trust_group_join_result, request_id, %{
                          status: "approved",
                          certificate: cert_str,
                          trustGroupInfo: info_str,
                          trust_group_id: identity.trust_group_id
                        }
                      })
                      {:ok, %{certificate: cert_str, trustGroupInfo: info_str}}
                    _ ->
                      {:error, "Failed to get trust group identity"}
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
    case apply(@join_requests, :deny, [request_id]) do
      {:ok, _} ->
        # Broadcast denial via PubSub so Bluetooth can relay over GATT
        Phoenix.PubSub.broadcast(Reality2.PubSub, "trust_group:join_results", {
          :trust_group_join_result, request_id, %{
            status: "denied",
            message: "Join request denied by trust group owner"
          }
        })
        {:ok, true}
      :not_found -> {:error, "Request not found"}
    end
  end

  def join_request_status(_, %{request_id: request_id}, _) do
    case apply(@join_requests, :get_status, [request_id]) do
      {:ok, req} ->
        {:ok, %{
          status: Atom.to_string(req.status),
          certificate: req.certificate,
          trustGroupInfo: req.trust_group_info
        }}
      :not_found ->
        {:error, "Request not found"}
    end
  end

  # -------------------------------------------------------------------------
  # BLE-based trust group join
  # -------------------------------------------------------------------------

  def ble_submit_join_request(_, %{peer_id: peer_id, node_name: node_name}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroupJoinBle) do
      case apply(Reality2Transnet.TrustGroupJoinBle, :submit_join_request, [peer_id, node_name]) do
        {:ok, result} ->
          {:ok, %{
            status: Map.get(result, :status, "pending"),
            trust_group_id: Map.get(result, :trust_group_id),
            message: Map.get(result, :message, "Join request sent via BLE")
          }}

        {:error, reason} ->
          {:error, "BLE join request failed: #{inspect(reason)}"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def ble_join_request_status(_, %{peer_id: peer_id}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroupJoinBle) do
      case apply(Reality2Transnet.TrustGroupJoinBle, :check_status, [peer_id]) do
        {:ok, result} ->
          {:ok, %{
            status: Map.get(result, :status, "pending"),
            trust_group_id: Map.get(result, :trust_group_id),
            message: Map.get(result, :message)
          }}

        {:error, reason} ->
          {:error, "BLE status check failed: #{inspect(reason)}"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def trust_group_members(_, args, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroupMembers) do
      members = case Map.get(args, :member_type) do
        nil -> apply(Reality2Transnet.TrustGroupMembers, :list_members, [])
        type_str ->
          type = String.to_existing_atom(type_str)
          apply(Reality2Transnet.TrustGroupMembers, :list_by_type, [type])
      end

      result = Enum.map(members, fn m ->
        %{
          node_id: m.node_id,
          node_name: m.node_name,
          node_public_key: m.node_public_key,
          member_type: Atom.to_string(m.member_type),
          approved_at: m.approved_at
        }
      end)
      {:ok, result}
    else
      {:ok, []}
    end
  end

  # -------------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------------

  defp get_trust_group_info_result do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :get_identity, []) do
        {:ok, identity} ->
          %{
            trust_group_id: identity.trust_group_id,
            trust_group_name: identity.name,
            trust_group_mode: Atom.to_string(identity.mode),
            is_provisional: Map.get(identity, :provisional, false)
          }

        _ ->
          %{trust_group_id: nil, trust_group_name: nil, trust_group_mode: nil, is_provisional: false}
      end
    else
      %{trust_group_id: nil, trust_group_name: nil, trust_group_mode: nil, is_provisional: false}
    end
  end

  defp get_trust_group_info do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :get_identity, []) do
        {:ok, identity} ->
          compressed = case apply(Reality2Transnet.TrustGroup, :get_trust_group_compressed_id, []) do
            {:ok, cid} -> Base.encode16(cid, case: :lower)
            _ -> nil
          end

          %{
            trust_group_id: identity.trust_group_id,
            trust_group_name: identity.name,
            trust_group_mode: Atom.to_string(identity.mode),
            trust_group_compressed_id: compressed,
            is_provisional: Map.get(identity, :provisional, false)
          }

        _ ->
          %{trust_group_id: nil, trust_group_name: nil, trust_group_mode: nil, trust_group_compressed_id: nil, is_provisional: false}
      end
    else
      %{trust_group_id: nil, trust_group_name: nil, trust_group_mode: nil, trust_group_compressed_id: nil, is_provisional: false}
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

  # -------------------------------------------------------------------------
  # trustGroupDirectoryClearStale — remove stale entries from trust group directory
  # -------------------------------------------------------------------------

  def clear_stale_directory(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroupDirectory) do
      case apply(Reality2Transnet.TrustGroupDirectory, :clear_stale, []) do
        {:ok, removed_count} ->
          {:ok, removed_count}

        {:error, reason} ->
          {:error, "Failed to clear stale entries: #{inspect(reason)}"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  # -------------------------------------------------------------------------
  # trustGroupRemoveMember — remove a member from the trust group (key holder only)
  # -------------------------------------------------------------------------

  def remove_trust_group_member(_, %{node_id: node_id}, _) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroupMembers) do
      case apply(Reality2Transnet.TrustGroupMembers, :remove_member, [node_id]) do
        :ok ->
          {:ok, true}

        {:error, :not_found} ->
          {:error, "Member not found"}

        {:error, reason} ->
          {:error, "Failed to remove member: #{inspect(reason)}"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  # -------------------------------------------------------------------------
  # Key Holders
  # -------------------------------------------------------------------------

  def list_key_holders(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.KeyHolders) do
      key_holders = apply(Reality2Transnet.KeyHolders, :list_key_holders, [])

      result = Enum.map(key_holders, fn kh ->
        %{
          node_id: kh.node_id,
          node_name: kh.node_name,
          device_name: kh.device_name,
          registered_at: kh.registered_at,
          last_seen: kh.last_seen,
          is_local: kh.is_local
        }
      end)

      {:ok, result}
    else
      {:error, "Transnet not loaded"}
    end
  end

  # -------------------------------------------------------------------------
  # Inter-Group Trust Federation
  # -------------------------------------------------------------------------

  def list_trusted_groups(_, _, _) do
    if Code.ensure_loaded?(Reality2Transnet.InterGroupTrust) do
      trusted = apply(Reality2Transnet.InterGroupTrust, :list_trusted_groups, [])

      result = Enum.map(trusted, fn th ->
        %{
          trust_group_id: th.trust_group_id,
          name: th.name,
          public_key: th.public_key,
          permissions: th.permissions,
          established_at: th.established_at,
          expires_at: Map.get(th, :expires_at),
          sentant_filter: Map.get(th, :shared_sentant_filter, []),
          status: to_string(Map.get(th, :status, :active))
        }
      end)

      {:ok, result}
    else
      {:error, "Transnet not loaded"}
    end
  end

  def generate_trust_token(_, args, _) do
    if Code.ensure_loaded?(Reality2Transnet.InterGroupTrust) do
      permissions = Map.get(args, :permissions, ["read_only"])
                    |> Enum.map(&String.to_atom/1)

      opts = [permissions: permissions]

      case apply(Reality2Transnet.InterGroupTrust, :generate_trust_token, [opts]) do
        {:ok, token_data} ->
          now = System.system_time(:second)
          {:ok, %{
            token: token_data.token,
            trust_group_id: token_data.trust_group_id,
            trust_group_name: token_data.trust_group_name,
            expires_at: token_data.expires_at,
            expires_in: max(0, token_data.expires_at - now)
          }}

        {:error, reason} ->
          {:error, "Failed to generate trust token: #{inspect(reason)}"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def establish_trust(_, args, _) do
    if Code.ensure_loaded?(Reality2Transnet.InterGroupTrust) do
      trust_group_id = args.trust_group_id
      trust_group_public_key = args.trust_group_public_key
      trust_group_name = Map.get(args, :trust_group_name, "Unknown")
      permissions = Map.get(args, :permissions, ["read_only"])
                    |> Enum.map(&String.to_atom/1)

      opts = [
        trust_group_name: trust_group_name,
        permissions: permissions
      ]

      case apply(Reality2Transnet.InterGroupTrust, :establish_trust, [trust_group_id, trust_group_public_key, opts]) do
        {:ok, trust_entry} ->
          {:ok, %{
            trust_group_id: trust_group_id,
            name: trust_entry.name,
            public_key: trust_entry.public_key,
            permissions: trust_entry.permissions,
            established_at: trust_entry.established_at,
            expires_at: Map.get(trust_entry, :expires_at),
            sentant_filter: Map.get(trust_entry, :shared_sentant_filter, []),
            status: to_string(Map.get(trust_entry, :status, :active))
          }}

        {:error, reason} ->
          {:error, "Failed to establish trust: #{inspect(reason)}"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end

  def revoke_trust(_, %{trust_group_id: trust_group_id}, _) do
    if Code.ensure_loaded?(Reality2Transnet.InterGroupTrust) do
      case apply(Reality2Transnet.InterGroupTrust, :revoke_trust, [trust_group_id]) do
        :ok -> {:ok, true}
        {:error, :not_found} -> {:error, "Trust relationship not found"}
        {:error, reason} -> {:error, "Failed to revoke trust: #{inspect(reason)}"}
      end
    else
      {:error, "Transnet not loaded"}
    end
  end
end
