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
        "http_port": 8080,
        "instructions": "Query sentants via HTTP: GET http://[ipv6]:port/sentants"
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
  Encodes WiFi mesh connection details for GATT transmission.

  Returns mesh_id, IPv6 address, and HTTP port for Sentant queries.

  ## Returns
  JSON string with mesh connection info
  """
  @spec encode_mesh_details() :: String.t()
  def encode_mesh_details do
    mesh_info = get_mesh_info()

    payload = %{
      mesh_active: mesh_info.active,
      mesh_id: Map.get(mesh_info, :mesh_id),
      ipv6_link_local: Map.get(mesh_info, :ipv6_link_local),
      http_port: Application.get_env(:ai_reality2_transnet, :wifi_server_port, 8080),
      instructions: "Query sentants: GET http://[ipv6]:port/sentants",
      timestamp: System.system_time(:millisecond)
    }

    Jason.encode!(payload)
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
  Decodes WiFi mesh details received via GATT.

  ## Parameters
  - `json_data` - JSON string from GATT read

  ## Returns
  - `{:ok, mesh_details}` - Successfully decoded
  - `{:error, reason}` - Failed to decode
  """
  @spec decode_mesh_details(String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_mesh_details(json_data) do
    case Jason.decode(json_data) do
      {:ok, data} when is_map(data) ->
        mesh_details = %{
          mesh_active: Map.get(data, "mesh_active", false),
          mesh_id: Map.get(data, "mesh_id"),
          ipv6_link_local: Map.get(data, "ipv6_link_local"),
          http_port: Map.get(data, "http_port", 8080),
          instructions: Map.get(data, "instructions"),
          timestamp: Map.get(data, "timestamp")
        }

        {:ok, mesh_details}

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
        result = %{
          command: String.to_existing_atom(command),
          parameters: Map.get(data, "parameters", %{}),
          timestamp: Map.get(data, "timestamp")
        }

        {:ok, result}

      {:ok, _} ->
        {:error, "invalid_command_format"}

      {:error, reason} ->
        {:error, "json_decode_failed: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, "decode_exception: #{inspect(error)}"}
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
  Handles a GATT read request for WiFi mesh details.

  Returns mesh connection information for HTTP queries.

  ## Returns
  Binary data containing mesh details
  """
  @spec handle_mesh_details_read() :: binary()
  def handle_mesh_details_read do
    json = encode_mesh_details()
    Logger.debug("[GATT Protocol] Mesh details read: #{byte_size(json)} bytes")
    json
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

  # Get mesh network info
  defp get_mesh_info do
    case AiReality2Transnet.Wifi.list_adapters() do
      {:ok, adapters} ->
        # Look for mesh interface
        mesh_adapter = Enum.find(adapters, fn adapter ->
          Map.get(adapter, :mesh_interface) != nil
        end)

        if mesh_adapter do
          # Get IPv6 link-local address
          case AiReality2Transnet.Wifi.get_ipv6_link_local(mesh_adapter.mesh_interface) do
            {:ok, ipv6} ->
              %{
                active: true,
                mesh_id: "R2MESH",
                interface: mesh_adapter.mesh_interface,
                ipv6_link_local: ipv6
              }

            {:error, _} ->
              %{
                active: true,
                mesh_id: "R2MESH",
                interface: mesh_adapter.mesh_interface,
                ipv6_link_local: nil
              }
          end
        else
          %{active: false}
        end

      {:error, _} ->
        %{active: false}
    end
  end

  # Safely convert binary to string
  defp safe_to_string(data) when is_binary(data) do
    case String.valid?(data) do
      true -> {:ok, data}
      false -> {:error, "invalid_utf8"}
    end
  end

  defp safe_to_string(_), do: {:error, "not_binary"}

  # Execute a mesh command
  defp execute_mesh_command(%{command: command, parameters: params}) do
    case command do
      :join_mesh ->
        mesh_id = Map.get(params, :mesh_id, "R2MESH")
        AiReality2Transnet.TransportManager.initiate_wifi_upgrade(nil, mesh_id)

      :leave_mesh ->
        # TODO: Implement mesh leave logic
        {:ok, :not_implemented}

      _ ->
        {:error, :unknown_command}
    end
  end
end
