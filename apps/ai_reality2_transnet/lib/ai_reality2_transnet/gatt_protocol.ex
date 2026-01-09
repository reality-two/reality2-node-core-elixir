defmodule AiReality2Transnet.GattProtocol do
  @moduledoc """
  GATT Protocol for Reality2 Transient Networking.

  **MINIMAL PROTOCOL FOR DISCOVERY ONLY**

  BLE GATT is now used ONLY for node discovery and WiFi mesh coordination.
  All Sentant queries and commands happen over WiFi mesh HTTP protocol.

  ## Protocol Architecture

  ### Service UUID
  `00001234-0000-1000-8000-00805f9b34fb` - Reality2 Transient Network Service

  ### Characteristics

  1. **Node Info** (Read)
     - UUID: `00001237-0000-1000-8000-00805f9b34fb`
     - Returns minimal node metadata and WiFi mesh info
     - DOES NOT include full Sentant list (use WiFi mesh HTTP for that)

  2. **WiFi Mesh Details** (Read, Notify)
     - UUID: `00001235-0000-1000-8000-00805f9b34fb`
     - Returns WiFi mesh connection information
     - Includes: mesh_id, IPv6 address, port for HTTP server

  3. **Mesh Command** (Write)
     - UUID: `00001236-0000-1000-8000-00805f9b34fb`
     - Send mesh coordination commands (join mesh, etc.)

  ## Message Format

      # Node Info Response (Minimal):
      {
        "node_id": "uuid",
        "version": "0.1.13",
        "capabilities": {
          "bluetooth": true,
          "wifi_mesh": true,
          "sentant_count": 5
        }
      }

      # WiFi Mesh Details Response:
      {
        "mesh_active": true,
        "mesh_id": "R2MESH_abc123",
        "ipv6_link_local": "fe80::1234:5678:90ab:cdef",
<<<<<<< Updated upstream
        "http_port": 8080,
        "instructions": "Use WiFi mesh HTTP/GraphQL for Sentant queries (e.g., POST /graphql)"
=======
        "http_port": 4005,
        "instructions": "Query sentants via HTTP: GET http://[ipv6]:port/mesh/sentants"
>>>>>>> Stashed changes
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
  @mesh_details_char_uuid "00001235-0000-1000-8000-00805f9b34fb"  # WiFi mesh connection info
  @mesh_command_char_uuid "00001236-0000-1000-8000-00805f9b34fb"  # Mesh coordination commands
  @node_info_char_uuid "00001237-0000-1000-8000-00805f9b34fb"     # Minimal node info

  def service_uuid, do: @reality2_service_uuid
  def mesh_details_uuid, do: @mesh_details_char_uuid
  def mesh_command_uuid, do: @mesh_command_char_uuid
  def node_info_uuid, do: @node_info_char_uuid

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
    payload = %{
      node_id: node_id,
      version: "0.1.13",
      capabilities: %{
        bluetooth: true,
        wifi_mesh: wifi_available?(),
        sentant_count: Reality2.Metadata.all(:SentantIDs) |> map_size()
      },
      timestamp: System.system_time(:millisecond),
      message: "Use WiFi mesh HTTP for Sentant queries - see mesh_details characteristic"
    }

    Jason.encode!(payload)
  end

  @doc """
  Encodes a WiFi hotspot join offer for GATT transmission.

  Returns complete connection credentials and rendezvous information.

  ## Returns
  JSON string with join offer details
  """
  @spec encode_join_offer() :: String.t()
  def encode_join_offer do
    # Get current hosting configuration
    case AiReality2Transnet.ConnectionManager.get_hosting_config() do
      {:ok, config} ->
        node_id = Reality2.Bootstrap.get(:node_id)

<<<<<<< Updated upstream
        payload = %{
          hotspot_available: true,
          ssid: config.ssid,
          psk: config.psk,
          channel: config.channel,
          security: "WPA2-PSK",
          rendezvous_ip: config.ip_address,
          rendezvous_port: config.port,
          offer_expiry: System.system_time(:second) + 300,  # Valid for 5 minutes
          host_node_id: node_id,
          timestamp: System.system_time(:millisecond)
        }
=======
    payload = %{
      mesh_active: mesh_info.active,
      mesh_id: Map.get(mesh_info, :mesh_id),
      ipv6_link_local: Map.get(mesh_info, :ipv6_link_local),
      http_port: Application.get_env(:ai_reality2_transnet, :wifi_server_port, 4005),
      instructions: "Query sentants: GET http://[ipv6]:port/mesh/sentants",
      timestamp: System.system_time(:millisecond)
    }
>>>>>>> Stashed changes

        Jason.encode!(payload)

      {:error, :not_hosting} ->
        # Not hosting - return unavailable
        payload = %{
          hotspot_available: false,
          message: "This node is not hosting a hotspot",
          timestamp: System.system_time(:millisecond)
        }

        Jason.encode!(payload)
    end
  end

  @doc """
  Encodes a mesh coordination command.

  ## Parameters
  - `command` - Command type (:join_mesh, :leave_mesh, etc.)
  - `parameters` - Command parameters

  ## Returns
  JSON string ready for GATT write
  """
  @spec encode_mesh_command(atom(), map()) :: String.t()
  def encode_mesh_command(command, parameters \\ %{}) do
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
<<<<<<< Updated upstream
      {:ok, %{"hotspot_available" => true} = data} ->
        join_offer = %{
          hotspot_available: true,
          ssid: Map.get(data, "ssid"),
          psk: Map.get(data, "psk"),
          channel: Map.get(data, "channel", 6),
          security: Map.get(data, "security", "WPA2-PSK"),
          rendezvous_ip: Map.get(data, "rendezvous_ip"),
          rendezvous_port: Map.get(data, "rendezvous_port", 8080),
          offer_expiry: Map.get(data, "offer_expiry"),
          host_node_id: Map.get(data, "host_node_id"),
=======
      {:ok, data} when is_map(data) ->
        mesh_details = %{
          mesh_active: Map.get(data, "mesh_active", false),
          mesh_id: Map.get(data, "mesh_id"),
          ipv6_link_local: Map.get(data, "ipv6_link_local"),
          http_port: Map.get(data, "http_port", 4005),
          instructions: Map.get(data, "instructions"),
>>>>>>> Stashed changes
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
  Decodes a mesh command received via GATT.

  ## Parameters
  - `json_data` - JSON string from GATT write

  ## Returns
  - `{:ok, command}` - Successfully decoded
  - `{:error, reason}` - Failed to decode
  """
  @spec decode_mesh_command(String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_mesh_command(json_data) do
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
  # GATT Handlers (called when GATT reads/writes occur)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Handles a GATT read request for minimal node info.

  Returns only basic node metadata and Sentant count, NOT full list.

  ## Returns
  Binary data containing minimal node info
  """
  @spec handle_node_info_read(String.t()) :: binary()
  def handle_node_info_read(node_id) do
    json = encode_node_info(node_id)
    Logger.debug("[GATT Protocol] Node info read: #{byte_size(json)} bytes")
    json
  end

  @doc """
  Handles a GATT read request for WiFi hotspot join offer.

  Returns complete connection credentials and rendezvous information.

  ## Returns
  Binary data containing join offer
  """
  @spec handle_join_offer_read() :: binary()
  def handle_join_offer_read do
    json = encode_join_offer()
    Logger.debug("[GATT Protocol] Join offer read: #{byte_size(json)} bytes")
    json
  end

  # Legacy name for compatibility
  @spec handle_mesh_details_read() :: binary()
  def handle_mesh_details_read do
    handle_join_offer_read()
  end

  @doc """
  Handles a GATT write request for mesh coordination command.

  Called when a remote device writes to the mesh command characteristic.

  ## Parameters
  - `data` - Binary data written by the client

  ## Returns
  - `:ok` - Command executed successfully
  - `{:error, reason}` - Failed to execute command
  """
  @spec handle_mesh_command_write(binary()) :: :ok | {:error, String.t()}
  def handle_mesh_command_write(data) do
    Logger.debug("[GATT Protocol] Received mesh command: #{byte_size(data)} bytes")

    with {:ok, json} <- safe_to_string(data),
         {:ok, command} <- decode_mesh_command(json),
         {:ok, _result} <- execute_mesh_command(command) do
      Logger.info("[GATT Protocol] Mesh command executed: #{command.command}")
      :ok
    else
      {:error, reason} ->
        Logger.error("[GATT Protocol] Mesh command failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Check if WiFi is available
  defp wifi_available? do
    case AiReality2Transnet.Wifi.list_adapters() do
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

  # Execute a hotspot connection command
  defp execute_mesh_command(%{command: command, parameters: params}) do
    case command do
      :join_network ->
        # Extract join offer from parameters
        join_offer = %{
          ssid: Map.get(params, :ssid) || Map.get(params, "ssid"),
          psk: Map.get(params, :psk) || Map.get(params, "psk"),
          channel: Map.get(params, :channel) || Map.get(params, "channel", 6),
          rendezvous_ip: Map.get(params, :rendezvous_ip) || Map.get(params, "rendezvous_ip"),
          rendezvous_port: Map.get(params, :rendezvous_port) || Map.get(params, "rendezvous_port", 8080),
          offer_expiry: Map.get(params, :offer_expiry) || Map.get(params, "offer_expiry") || System.system_time(:second) + 300,
          host_node_id: Map.get(params, :host_node_id) || Map.get(params, "host_node_id")
        }

        # Get peer_id from host_node_id
        peer_id = join_offer.host_node_id

        # Connect to host
        case AiReality2Transnet.ConnectionManager.connect_to_host(peer_id, join_offer) do
          {:ok, _info} -> {:ok, :connected}
          error -> error
        end

      :leave_network ->
        AiReality2Transnet.ConnectionManager.disconnect_from_current_host()

      _ ->
        {:error, :unknown_command}
    end
  end
end
