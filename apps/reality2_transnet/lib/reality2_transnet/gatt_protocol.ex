defmodule Reality2Transnet.GattProtocol do
  @moduledoc """
  GATT Protocol for Reality2 Transient Networking.

  **MINIMAL PROTOCOL FOR DISCOVERY ONLY**

  BLE GATT is used for node discovery and WiFi hotspot coordination.
  All Sentant queries and commands happen over WiFi HTTP/GraphQL protocol.

  ## Protocol Architecture

  ### Service UUID
  `00001234-0000-1000-8000-00805f9b34fb` - Reality2 Transient Network Service

  ### Characteristics

  1. **Node Info** (Read)
     - UUID: `00001237-0000-1000-8000-00805f9b34fb`
     - Returns minimal node metadata and WiFi capability info
     - DOES NOT include full Sentant list (use WiFi HTTP for that)

  2. **WiFi Join Offer** (Read, Notify)
     - UUID: `00001235-0000-1000-8000-00805f9b34fb`
     - Returns WiFi hotspot connection credentials
     - Includes: SSID, PSK, rendezvous IP/port

  3. **Network Command** (Write)
     - UUID: `00001236-0000-1000-8000-00805f9b34fb`
     - Send network commands (join_network, leave_network)

  ## Message Format

      # Node Info Response (Minimal):
      {
        "node_id": "uuid",
        "version": "0.1.13",
        "capabilities": {
          "bluetooth": true,
          "wifi_hotspot": true,
          "sentant_count": 5
        }
      }

      # WiFi Join Offer Response:
      {
        "hotspot_available": true,
        "ssid": "R2-NODE-A3F7",
        "psk": "secure_password",
        "rendezvous_ip": "192.168.42.1",
        "rendezvous_port": 4005
      }

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  require Logger

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GATT Service and Characteristic UUIDs
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @reality2_service_uuid "00001234-0000-1000-8000-00805f9b34fb"
  # WiFi hotspot join offer (SSID, PSK, rendezvous info)
  @join_offer_char_uuid "00001235-0000-1000-8000-00805f9b34fb"
  # Network commands (join_network, leave_network)
  @network_command_char_uuid "00001236-0000-1000-8000-00805f9b34fb"
  # Minimal node info
  @node_info_char_uuid "00001237-0000-1000-8000-00805f9b34fb"
  # Hive join requests/responses
  @hive_join_char_uuid "00001238-0000-1000-8000-00805f9b34fb"

  def service_uuid, do: @reality2_service_uuid
  def join_offer_uuid, do: @join_offer_char_uuid
  def network_command_uuid, do: @network_command_char_uuid
  def node_info_uuid, do: @node_info_char_uuid
  def hive_join_uuid, do: @hive_join_char_uuid

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Encoding Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Encodes minimal node information for GATT transmission.

  Returns ONLY basic node info and Sentant count, NOT full Sentant list.
  Clients should query Sentants via WiFi mesh HTTP.

  ## Returns
  JSON string with minimal node info
  """
  @spec encode_node_info(String.t()) :: String.t()
  def encode_node_info(node_id) do
    node_name = Reality2.Bootstrap.get(:node_name, "R2Node")

    payload = %{
      node_id: node_id,
      node_name: node_name,
      version: "0.1.13",
      capabilities: %{
        bluetooth: true,
        wifi_hotspot: wifi_available?(),
        sentant_count: Reality2.Metadata.all(:SentantIDs) |> map_size()
      },
      timestamp: System.system_time(:millisecond),
      message: "Use WiFi HTTP for Sentant queries - connect to hotspot first"
    }

    Jason.encode!(payload)
  end

  @doc """
  Encodes a WiFi hotspot join offer for GATT transmission.

  Returns complete connection credentials and rendezvous information.

  ## Returns
  JSON string with join offer details
  """
  @spec encode_join_offer(map() | nil) :: String.t()
  def encode_join_offer(config) when is_map(config) do
    node_id = Reality2.Bootstrap.get(:node_id)

    payload = %{
      hotspot_available: true,
      ssid: config.ssid,
      psk: config.psk,
      channel: config.channel,
      security: "WPA2-PSK",
      rendezvous_ip: config.ip_address,
      rendezvous_port: config.port,
      offer_expiry: System.system_time(:second) + 300,
      host_node_id: node_id,
      timestamp: System.system_time(:millisecond)
    }

    Jason.encode!(payload)
  end

  def encode_join_offer(_) do
    # Even when not hosting a hotspot, include the node's IP for direct queries
    # if the Android device happens to be on the same network
    node_ip = get_local_ip()
    port = Application.get_env(:reality2_web, :http_port, 4005)

    payload = %{
      hotspot_available: false,
      message: "This node is not hosting a hotspot",
      rendezvous_ip: node_ip,
      rendezvous_port: port,
      timestamp: System.system_time(:millisecond)
    }

    Jason.encode!(payload)
  end

  # Get the node's local IP address (first non-loopback IPv4)
  defp get_local_ip do
    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        ifaddrs
        |> Enum.flat_map(fn {_name, opts} ->
          opts
          |> Keyword.get_values(:addr)
          |> Enum.filter(fn addr ->
            case addr do
              {a, _, _, _} when a != 127 -> true  # IPv4, not loopback
              _ -> false
            end
          end)
        end)
        |> List.first()
        |> case do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          nil -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Encodes a network coordination command.

  ## Parameters
  - `command` - Command type (:join_network, :leave_network)
  - `parameters` - Command parameters

  ## Returns
  JSON string ready for GATT write
  """
  @spec encode_network_command(atom(), map()) :: String.t()
  def encode_network_command(command, parameters \\ %{}) do
    payload = %{
      command: to_string(command),
      parameters: parameters,
      timestamp: System.system_time(:millisecond)
    }

    Jason.encode!(payload)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Decoding Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Decodes minimal node information received via GATT.

  ## Parameters
  - `json_data` - JSON string from GATT read

  ## Returns
  - `{:ok, node_info}` - Successfully decoded
  - `{:error, reason}` - Failed to decode
  """
  @spec decode_node_info(String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_node_info(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"node_id" => node_id} = data} ->
        node_info = %{
          node_id: node_id,
          node_name: Map.get(data, "node_name"),
          version: Map.get(data, "version"),
          capabilities: Map.get(data, "capabilities", %{}),
          timestamp: Map.get(data, "timestamp"),
          message: Map.get(data, "message")
        }

        {:ok, node_info}

      {:ok, _} ->
        {:error, "invalid_node_info_format"}

      {:error, reason} ->
        {:error, "json_decode_failed: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, "decode_exception: #{inspect(error)}"}
  end

  @doc """
  Decodes a WiFi hotspot join offer received via GATT.

  ## Parameters
  - `json_data` - JSON string from GATT read

  ## Returns
  - `{:ok, join_offer}` - Successfully decoded
  - `{:error, reason}` - Failed to decode
  """
  @spec decode_join_offer(String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_join_offer(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"hotspot_available" => true} = data} ->
        join_offer = %{
          hotspot_available: true,
          ssid: Map.get(data, "ssid"),
          psk: Map.get(data, "psk"),
          channel: Map.get(data, "channel", 6),
          security: Map.get(data, "security", "WPA2-PSK"),
          rendezvous_ip: Map.get(data, "rendezvous_ip"),
          rendezvous_port: Map.get(data, "rendezvous_port", 4005),
          offer_expiry: Map.get(data, "offer_expiry"),
          host_node_id: Map.get(data, "host_node_id"),
          timestamp: Map.get(data, "timestamp")
        }

        {:ok, join_offer}

      {:ok, %{"hotspot_available" => false} = data} ->
        {:error, "hotspot_not_available: #{Map.get(data, "message", "unknown")}"}

      {:ok, _} ->
        {:error, "invalid_join_offer_format"}

      {:error, reason} ->
        {:error, "json_decode_failed: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, "decode_exception: #{inspect(error)}"}
  end

  @doc """
  Decodes a network command received via GATT.

  ## Parameters
  - `json_data` - JSON string from GATT write

  ## Returns
  - `{:ok, command}` - Successfully decoded
  - `{:error, reason}` - Failed to decode
  """
  @spec decode_network_command(String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_network_command(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"command" => command} = data} ->
        with {:ok, command_atom} <- decode_command_atom(command) do
          result = %{
            command: command_atom,
            parameters: Map.get(data, "parameters", %{}),
            timestamp: Map.get(data, "timestamp")
          }

          {:ok, result}
        end

      {:ok, _} ->
        {:error, "invalid_command_format"}

      {:error, reason} ->
        {:error, "json_decode_failed: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, "decode_exception: #{inspect(error)}"}
  end

  # Convert command strings to atoms using an explicit allow-list.
  # This avoids `String.to_existing_atom/1` raising on unexpected inputs.
  defp decode_command_atom(command) when is_binary(command) do
    case command do
      # Hotspot commands
      "join_network" -> {:ok, :join_network}
      "leave_network" -> {:ok, :leave_network}
      other -> {:error, "unknown_command: #{other}"}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Hive Join GATT Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Encodes a hive join request for GATT transmission.

  ## Parameters
  - `params` - Map with :action and action-specific fields

  ## Returns
  JSON string ready for GATT write
  """
  @spec encode_hive_join(map()) :: String.t()
  def encode_hive_join(params) do
    Jason.encode!(params)
  end

  @doc """
  Constructs the canonical signable string for a join request.

  Used by both the joiner (to sign) and the hive owner (to verify).
  """
  @spec join_request_signable(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def join_request_signable(node_id, node_name, node_public_key_b64, ephemeral_public_key_b64) do
    "join_request|node_id=#{node_id}|node_name=#{node_name}|node_public_key=#{node_public_key_b64}|ephemeral_public_key=#{ephemeral_public_key_b64}"
  end

  @doc """
  Encrypts a join result payload for a specific recipient using ECDH.

  Generates an ephemeral X25519 keypair, performs DH with the recipient's
  X25519 public key, and encrypts with AES-256-GCM.

  ## Parameters
  - `payload_map` - The join result map to encrypt
  - `recipient_x25519_pub` - Recipient's X25519 public key (32 bytes)

  ## Returns
  Map with encrypted data and ephemeral public key for decryption
  """
  @spec encrypt_join_result(map(), binary()) :: map()
  def encrypt_join_result(payload_map, recipient_x25519_pub) do
    require Logger
    {sender_pub, sender_priv} = :crypto.generate_key(:ecdh, :x25519)
    shared = :crypto.compute_key(:ecdh, recipient_x25519_pub, sender_priv, :x25519)
    key = :crypto.hash(:sha256, shared)
    iv = :crypto.strong_rand_bytes(12)
    plaintext = Jason.encode!(payload_map)
    Logger.debug("[GattProtocol] Encrypting join result JSON: #{plaintext}")

    {ciphertext, tag} = :crypto.crypto_one_time_aead(
      :aes_256_gcm, key, iv, plaintext, <<>>, 16, true
    )

    %{
      action: "join_result_encrypted",
      ephemeral_public_key: Base.encode64(sender_pub),
      iv: Base.encode64(iv),
      tag: Base.encode64(tag),
      ciphertext: Base.encode64(ciphertext)
    }
  end

  @doc """
  Decrypts an encrypted join result using our X25519 private key.

  ## Parameters
  - `encrypted_msg` - Map with encrypted fields
  - `my_x25519_priv` - Our ephemeral X25519 private key (32 bytes)

  ## Returns
  - `{:ok, decrypted_map}` - Successfully decrypted
  - `{:error, reason}` - Failed to decrypt
  """
  @spec decrypt_join_result(map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def decrypt_join_result(encrypted_msg, my_x25519_priv) do
    with {:ok, sender_pub} <- decode_field(encrypted_msg, :ephemeral_public_key),
         {:ok, iv} <- decode_field(encrypted_msg, :iv),
         {:ok, tag} <- decode_field(encrypted_msg, :tag),
         {:ok, ciphertext} <- decode_field(encrypted_msg, :ciphertext) do
      shared = :crypto.compute_key(:ecdh, sender_pub, my_x25519_priv, :x25519)
      key = :crypto.hash(:sha256, shared)

      case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, <<>>, tag, false) do
        plaintext when is_binary(plaintext) ->
          case Jason.decode(plaintext, keys: :atoms) do
            {:ok, map} -> {:ok, map}
            _ -> {:error, "json_decode_failed_after_decrypt"}
          end

        :error ->
          {:error, "decryption_failed"}
      end
    end
  rescue
    error -> {:error, "decrypt_exception: #{inspect(error)}"}
  end

  @doc """
  Decodes a hive join message received via GATT.

  ## Parameters
  - `data` - Binary data from GATT read/write/notify

  ## Returns
  - `{:ok, message}` - Successfully decoded with :action field
  - `{:error, reason}` - Failed to decode
  """
  @spec decode_hive_join(binary() | list()) :: {:ok, map()} | {:error, String.t()}
  def decode_hive_join(data) do
    with {:ok, json} <- safe_to_string(data),
         {:ok, decoded} <- Jason.decode(json) do
      case decoded do
        %{"action" => "join_request"} = msg ->
          {:ok, %{
            action: :join_request,
            node_id: Map.get(msg, "node_id"),
            node_name: Map.get(msg, "node_name"),
            node_public_key: Map.get(msg, "node_public_key"),
            ephemeral_public_key: Map.get(msg, "ephemeral_public_key"),
            signature: Map.get(msg, "signature")
          }}

        %{"action" => "join_result_encrypted"} = msg ->
          {:ok, %{
            action: :join_result_encrypted,
            ephemeral_public_key: Map.get(msg, "ephemeral_public_key"),
            iv: Map.get(msg, "iv"),
            tag: Map.get(msg, "tag"),
            ciphertext: Map.get(msg, "ciphertext")
          }}

        %{"action" => "join_result"} = msg ->
          {:ok, %{
            action: :join_result,
            status: Map.get(msg, "status"),
            hive_id: Map.get(msg, "hive_id"),
            cert: Map.get(msg, "cert"),
            hive_public_info: Map.get(msg, "hive_public_info"),
            message: Map.get(msg, "message")
          }}

        _ ->
          {:error, "unknown_hive_join_action"}
      end
    else
      {:error, reason} -> {:error, "hive_join_decode_failed: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, "hive_join_decode_exception: #{inspect(error)}"}
  end

  @doc """
  Handles a GATT write for hive join requests.
  Called on the hive owner when a remote device writes a join request.

  ## Parameters
  - `data` - Binary data written by the client

  ## Returns
  - `{:ok, result}` - Request processed
  - `{:error, reason}` - Failed to process
  """
  @spec handle_hive_join_write(binary()) :: {:ok, map()} | {:error, String.t()}
  def handle_hive_join_write(data) do
    Logger.debug("[GATT Protocol] Received hive join write: #{byte_size(data)} bytes")

    case decode_hive_join(data) do
      {:ok, %{action: :join_request} = request} ->
        Logger.info("[GATT Protocol] Hive join request from node: #{request.node_name} (#{request.node_id})")
        {:ok, request}

      {:ok, other} ->
        Logger.warning("[GATT Protocol] Unexpected hive join action: #{inspect(other)}")
        {:error, "unexpected_action"}

      {:error, reason} ->
        Logger.error("[GATT Protocol] Hive join decode failed: #{reason}")
        {:error, reason}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Decode a base64 field from a map (supports both atom and string keys)
  defp decode_field(map, key) do
    value = Map.get(map, key) || Map.get(map, to_string(key))
    case value do
      nil -> {:error, "missing_field: #{key}"}
      b64 -> Base.decode64(b64)
    end
  end

  # Check if WiFi is available
  defp wifi_available? do
    case Reality2Transnet.Wifi.list_adapters() do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  # Safely convert GATT payloads (binary or list-of-bytes) into UTF-8 strings.
  @spec safe_to_string(binary() | list() | any()) :: {:ok, String.t()} | {:error, String.t()}
  defp safe_to_string(data) when is_list(data) do
    data |> :binary.list_to_bin() |> safe_to_string()
  end

  defp safe_to_string(data) when is_binary(data) do
    case String.valid?(data) do
      true -> {:ok, data}
      false -> {:error, "invalid_utf8"}
    end
  end

  defp safe_to_string(_), do: {:error, "not_binary"}
end
