defmodule AiReality2Transnet.HiveJoinBle do
  @moduledoc """
  Joiner-side BLE client for hive join requests.

  Handles submitting join requests to a remote hive owner via BLE GATT,
  and polling for the result (approved/denied).

  ## Security

  - Join requests include the joiner's Ed25519 public key and are signed
    to prove key ownership.
  - An ephemeral X25519 keypair is generated per request for ECDH encryption.
  - The hive owner encrypts the join result (containing the certificate) so
    only the intended recipient can decrypt it.
  - The joiner verifies the returned hive_id matches the expected peer's hive
    before installing the certificate.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer, restart: :transient
  require Logger

  @hive_join_uuid AiReality2Transnet.GattProtocol.hive_join_uuid()

  # Timeout for GATT operations
  @gatt_timeout_ms 15_000

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Submit a hive join request to a remote peer via BLE GATT.

  The request includes this node's Ed25519 public key (for certificate binding),
  an ephemeral X25519 public key (for result encryption), and an Ed25519 signature
  (proving key ownership).

  ## Parameters
  - `peer_id` - The node ID of the hive owner peer
  - `node_name` - Our node's display name

  ## Returns
  - `{:ok, %{request_id: id, status: "pending"}}` - Request submitted
  - `{:error, reason}` - Failed to submit
  """
  def submit_join_request(peer_id, node_name) do
    GenServer.call(__MODULE__, {:submit_join_request, peer_id, node_name}, @gatt_timeout_ms + 5_000)
  end

  @doc """
  Check the status of a pending BLE join request by reading the remote GATT characteristic.

  ## Parameters
  - `peer_id` - The node ID of the hive owner peer

  ## Returns
  - `{:ok, %{status: status, ...}}` - Current status
  - `{:error, reason}` - Failed to check
  """
  def check_status(peer_id) do
    GenServer.call(__MODULE__, {:check_status, peer_id}, @gatt_timeout_ms + 5_000)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(state) do
    {:ok, Map.merge(state, %{pending_requests: %{}, pending_ops: %{}})}
  end

  @impl true
  def handle_call({:submit_join_request, peer_id, node_name}, from, state) do
    case get_peer_address(peer_id) do
      {:ok, address} ->
        node_id = Reality2.Bootstrap.get(:node_id)

        # Get our Ed25519 public key for certificate binding
        node_public_key_b64 = get_node_public_key_b64()

        # Generate ephemeral X25519 keypair for encrypting the result
        {ephemeral_pub, ephemeral_priv} = :crypto.generate_key(:ecdh, :x25519)
        ephemeral_public_key_b64 = Base.encode64(ephemeral_pub)

        # Sign the request to prove we hold the Ed25519 private key
        signature_b64 = sign_join_request(
          node_id, node_name, node_public_key_b64, ephemeral_public_key_b64
        )

        payload = AiReality2Transnet.GattProtocol.encode_hive_join(%{
          action: "join_request",
          node_id: node_id,
          node_name: node_name,
          node_public_key: node_public_key_b64,
          ephemeral_public_key: ephemeral_public_key_b64,
          signature: signature_b64
        })

        adapter_name = get_adapter_name()

        # Write to remote peer's hive_join characteristic
        AiReality2Transnet.Action.gatt_write_to_device(
          self(),
          address,
          @hive_join_uuid,
          :binary.bin_to_list(payload),
          adapter_name
        )

        # Store pending operation to reply when we get the NIF callback
        ref = make_ref()
        pending_ops = Map.put(state.pending_ops, {:write, peer_id}, {from, ref, :submit})

        # Get the expected hive_id from the peer info for later verification
        expected_hive_id = get_peer_hive_id(peer_id)

        pending_requests = Map.put(state.pending_requests, peer_id, %{
          address: address,
          status: :writing,
          submitted_at: System.system_time(:second),
          ephemeral_private_key: ephemeral_priv,
          expected_hive_id: expected_hive_id
        })

        # Set a timeout
        Process.send_after(self(), {:op_timeout, {:write, peer_id}, ref}, @gatt_timeout_ms)

        {:noreply, %{state | pending_ops: pending_ops, pending_requests: pending_requests}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:check_status, peer_id}, from, state) do
    case get_peer_address(peer_id) do
      {:ok, address} ->
        adapter_name = get_adapter_name()

        # Read the remote peer's hive_join characteristic
        AiReality2Transnet.Action.gatt_read_characteristic(
          self(),
          address,
          @hive_join_uuid,
          adapter_name
        )

        ref = make_ref()
        pending_ops = Map.put(state.pending_ops, {:read, peer_id}, {from, ref, :check})

        Process.send_after(self(), {:op_timeout, {:read, peer_id}, ref}, @gatt_timeout_ms)

        {:noreply, %{state | pending_ops: pending_ops}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(_msg, _from, state), do: {:reply, {:error, :unknown}, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_info - NIF callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info(:gatt_write_success, state) do
    # Find the pending write operation and reply
    case find_pending_op(state.pending_ops, :write) do
      {key, {from, _ref, :submit}} ->
        # Write succeeded, now read back to get the request_id from the ack
        {_peer_id_key, peer_id} = parse_op_key(key)
        pending_ops = Map.delete(state.pending_ops, key)

        # Schedule a read to get the ack with request_id
        case Map.get(state.pending_requests, peer_id) do
          %{address: address} ->
            adapter_name = get_adapter_name()
            AiReality2Transnet.Action.gatt_read_characteristic(
              self(),
              address,
              @hive_join_uuid,
              adapter_name
            )

            ref = make_ref()
            pending_ops = Map.put(pending_ops, {:read_ack, peer_id}, {from, ref, :submit_ack})
            Process.send_after(self(), {:op_timeout, {:read_ack, peer_id}, ref}, @gatt_timeout_ms)

            {:noreply, %{state | pending_ops: pending_ops}}

          _ ->
            GenServer.reply(from, {:ok, %{status: "pending", message: "Request sent"}})
            {:noreply, %{state | pending_ops: pending_ops}}
        end

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:gatt_read, data}, state) do
    raw = if is_list(data), do: :binary.list_to_bin(data), else: data

    # Try to find a pending read operation
    case find_pending_op(state.pending_ops, :read_ack) || find_pending_op(state.pending_ops, :read) do
      {key, {from, _ref, op_type}} ->
        pending_ops = Map.delete(state.pending_ops, key)
        {_key_type, peer_id} = parse_op_key(key)

        case AiReality2Transnet.GattProtocol.decode_hive_join(raw) do
          {:ok, %{action: :join_result_encrypted} = encrypted} ->
            # Decrypt using our ephemeral X25519 private key
            handle_encrypted_result(from, encrypted, peer_id, state, pending_ops)

          {:ok, %{action: :join_result, status: status} = result} ->
            # Unencrypted result (legacy or fallback)
            if status == "approved" do
              apply_join_result(result, peer_id, state)
            end

            GenServer.reply(from, {:ok, %{
              status: status,
              hive_id: Map.get(result, :hive_id),
              message: Map.get(result, :message)
            }})
            {:noreply, %{state | pending_ops: pending_ops}}

          {:ok, %{action: :join_request}} ->
            # This is the ack from our join request submission
            GenServer.reply(from, {:ok, %{status: "pending", message: "Request submitted"}})
            {:noreply, %{state | pending_ops: pending_ops}}

          {:ok, _other} ->
            case op_type do
              :submit_ack ->
                GenServer.reply(from, {:ok, %{status: "pending", message: "Request submitted"}})
              _ ->
                GenServer.reply(from, {:ok, %{status: "pending", message: "Waiting for approval"}})
            end
            {:noreply, %{state | pending_ops: pending_ops}}

          {:error, _reason} ->
            if raw == "" or raw == <<>> do
              GenServer.reply(from, {:ok, %{status: "pending", message: "No response yet"}})
            else
              case op_type do
                :submit_ack ->
                  GenServer.reply(from, {:ok, %{status: "pending", message: "Request submitted"}})
                _ ->
                  GenServer.reply(from, {:ok, %{status: "pending", message: "Waiting for response"}})
              end
            end
            {:noreply, %{state | pending_ops: pending_ops}}
        end

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:op_timeout, key, ref}, state) do
    case Map.get(state.pending_ops, key) do
      {from, ^ref, _op_type} ->
        GenServer.reply(from, {:error, "GATT operation timed out"})
        pending_ops = Map.delete(state.pending_ops, key)
        {:noreply, %{state | pending_ops: pending_ops}}

      _ ->
        # Already completed or different ref
        {:noreply, state}
    end
  end

  def handle_info({:error, reason}, state) do
    Logger.error("[HiveJoinBle] GATT error: #{inspect(reason)}")

    # Reply to any pending operation with the error
    {replied_ops, remaining_ops} =
      Enum.split_with(state.pending_ops, fn {_key, _val} -> true end)

    Enum.each(replied_ops, fn {_key, {from, _ref, _type}} ->
      GenServer.reply(from, {:error, "GATT error: #{inspect(reason)}"})
    end)

    {:noreply, %{state | pending_ops: Map.new(remaining_ops)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_peer_address(peer_id) do
    case AiReality2Transnet.PeerManager.get_peer(peer_id) do
      {:ok, peer} ->
        case Map.get(peer, :address) do
          nil -> {:error, "Peer has no BLE address"}
          address -> {:ok, address}
        end

      {:error, :not_found} ->
        {:error, "Peer not found"}
    end
  end

  defp get_peer_hive_id(peer_id) do
    case AiReality2Transnet.PeerManager.get_peer(peer_id) do
      {:ok, peer} -> Map.get(peer, :hive_id)
      _ -> nil
    end
  end

  defp get_adapter_name do
    case AiReality2Transnet.Bluetooth.get_state() do
      %{adapter_name: name} -> name
      _ -> "hci0"
    end
  end

  defp find_pending_op(ops, type_prefix) do
    Enum.find(ops, fn
      {{^type_prefix, _peer_id}, _val} -> true
      _ -> false
    end)
  end

  defp parse_op_key({_type, peer_id}), do: {:peer_id, peer_id}

  # Get this node's Ed25519 public key as base64 for the join request
  defp get_node_public_key_b64 do
    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :get_public_key, []) do
        {:ok, public_key} -> Base.encode64(public_key)
        _ -> ""
      end
    else
      ""
    end
  end

  # Sign the join request payload with our Ed25519 private key
  defp sign_join_request(node_id, node_name, node_public_key_b64, ephemeral_public_key_b64) do
    message = AiReality2Transnet.GattProtocol.join_request_signable(
      node_id, node_name, node_public_key_b64, ephemeral_public_key_b64
    )

    if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
      case apply(AiReality2Transnet.HiveIdentity, :sign_data, [message]) do
        {:ok, signature} -> Base.encode64(signature)
        _ -> ""
      end
    else
      ""
    end
  end

  # Handle an encrypted join result — decrypt and process
  defp handle_encrypted_result(from, encrypted, peer_id, state, pending_ops) do
    case Map.get(state.pending_requests, peer_id) do
      %{ephemeral_private_key: priv_key} when not is_nil(priv_key) ->
        case AiReality2Transnet.GattProtocol.decrypt_join_result(encrypted, priv_key) do
          {:ok, decrypted} ->
            status = Map.get(decrypted, :status) || Map.get(decrypted, "status")

            if status == "approved" do
              # Convert to the expected format for apply_join_result
              result = %{
                cert: Map.get(decrypted, :cert) || Map.get(decrypted, "cert"),
                hive_id: Map.get(decrypted, :hive_id) || Map.get(decrypted, "hive_id"),
                hive_public_info: Map.get(decrypted, :hive_public_info) || Map.get(decrypted, "hive_public_info"),
                message: Map.get(decrypted, :message) || Map.get(decrypted, "message")
              }
              apply_join_result(result, peer_id, state)
            end

            GenServer.reply(from, {:ok, %{
              status: status,
              hive_id: Map.get(decrypted, :hive_id) || Map.get(decrypted, "hive_id"),
              message: Map.get(decrypted, :message) || Map.get(decrypted, "message")
            }})

          {:error, reason} ->
            Logger.error("[HiveJoinBle] Failed to decrypt join result: #{reason}")
            GenServer.reply(from, {:error, "Failed to decrypt join result"})
        end

      _ ->
        Logger.error("[HiveJoinBle] No ephemeral key found for peer #{peer_id}")
        GenServer.reply(from, {:error, "No encryption key available"})
    end

    {:noreply, %{state | pending_ops: pending_ops}}
  end

  # Apply an approved join result — verify hive_id and install certificate
  defp apply_join_result(%{cert: cert, hive_id: hive_id} = result, peer_id, state) when not is_nil(cert) do
    hive_public_info = Map.get(result, :hive_public_info)

    # Verify the hive_id matches what we expected from the peer
    expected_hive_id = case Map.get(state.pending_requests, peer_id) do
      %{expected_hive_id: id} -> id
      _ -> nil
    end

    if expected_hive_id != nil and hive_id != nil and expected_hive_id != hive_id do
      Logger.error("[HiveJoinBle] Hive ID mismatch! Expected #{expected_hive_id}, got #{hive_id}. Rejecting certificate.")
    else
      if Code.ensure_loaded?(AiReality2Transnet.HiveIdentity) do
        case apply(AiReality2Transnet.HiveIdentity, :join_as_member, [cert, hive_public_info]) do
          {:ok, _} ->
            Logger.info("[HiveJoinBle] Successfully joined hive #{hive_id}")

          :ok ->
            Logger.info("[HiveJoinBle] Successfully joined hive #{hive_id}")

          {:error, reason} ->
            Logger.error("[HiveJoinBle] Failed to join hive: #{inspect(reason)}")
        end
      end
    end
  end

  defp apply_join_result(_, _, _), do: :ok
end
