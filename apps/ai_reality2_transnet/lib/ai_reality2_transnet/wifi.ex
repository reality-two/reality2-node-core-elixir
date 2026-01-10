defmodule AiReality2Transnet.Wifi do
  @moduledoc """
  WiFi Hotspot and Client Networking for Reality2 Transient Networks.

  This module implements standard WiFi hotspot (AP mode) and client (station mode) operations
  for Reality2 transient networking. It replaces the previous 802.11s mesh implementation,
  which had poor hardware compatibility.

  ## Architecture Overview

  Reality2 uses a **hotspot-based mobility model**:

  ```
  Phase 1: BLE Discovery (Low Power)
  ┌─────────────────────────────────────────┐
  │  Beacon Broadcasting + Scanning         │
  │  - Always on, low power                 │
  │  - Discovers nearby Reality2 nodes      │
  │  - Advertises: can_host_ap flag         │
  │  - Provides node UUID and RSSI          │
  └─────────────────────────────────────────┘
                    ↓
  Phase 2: WiFi Hotspot Connection (High Bandwidth)
  ┌─────────────────────────────────────────┐
  │  Standard WPA2-PSK Hotspot              │
  │  - Fixed/anchor nodes host hotspots     │
  │  - Mobile nodes connect as clients      │
  │  - HTTP/GraphQL over standard WiFi      │
  │  - Automatic handover between hotspots  │
  └─────────────────────────────────────────┘
  ```

  ## Node Roles

  **Hotspot Host (AP Mode)**:
  - Fixed anchors (POS machines) always host
  - Mobile nodes with good upstream can host
  - Broadcasts WPA2-PSK network
  - Runs HTTP server for sentantAll exchange
  - Can support multiple clients

  **Client (Station Mode)**:
  - Mobile nodes connect to best available hotspot
  - Single association at a time
  - Continuous assessment for handover
  - Re-authenticates after handover

  ## Why Standard WiFi Instead of Mesh?

  **802.11s mesh problems**:
  - Poor hardware support (needs specific drivers)
  - Complex setup and configuration
  - Unreliable on many adapters
  - Not supported on most mobile devices

  **Standard WiFi advantages**:
  - Universal hardware support
  - Well-tested and reliable
  - Works on all platforms
  - Standard WPA2-PSK security
  - Easy troubleshooting

  ## Implementation: NetworkManager D-Bus API

  This module uses NetworkManager's D-Bus API for:
  - Creating and managing hotspots
  - Connecting to networks as a client
  - Monitoring connection status
  - Handling handovers

  Alternatively, falls back to:
  - `nmcli` command-line tool
  - Direct `hostapd` + `wpa_supplicant` for embedded systems

  ## Typical Usage Flow

  **As Hotspot Host:**
  ```elixir
  # 1. Generate unique credentials
  node_id = Reality2.Bootstrap.get(:node_id)
  ssid = Wifi.generate_ssid(node_id)  # => "R2-WAIROA-A3F7"
  psk = Wifi.generate_psk()

  # 2. Start hotspot
  {:ok, connection_uuid} = Wifi.start_hotspot("wlan0", ssid, psk)

  # 3. Get assigned IP
  {:ok, ip} = Wifi.get_hotspot_ip("wlan0")
  # => "192.168.42.1"

  # 4. Wait for clients
  {:ok, clients} = Wifi.get_connected_clients("wlan0")
  # => ["aa:bb:cc:dd:ee:ff"]
  ```

  **As Client:**
  ```elixir
  # 1. Receive join offer via GATT
  %{ssid: ssid, psk: psk, rendezvous: host_ip} = join_offer

  # 2. Connect to hotspot
  {:ok, connection_uuid} = Wifi.connect_to_network("wlan0", ssid, psk)

  # 3. Wait for IP assignment
  {:ok, my_ip} = Wifi.get_interface_ip("wlan0")
  # => "192.168.42.15"

  # 4. Query host's GraphQL endpoint
  # (host_ip comes from join_offer.rendezvous_ip)
  # Example: POST http://192.168.42.1:4005/reality2
  ```

  ## Requirements

  **System packages:**
  - NetworkManager (nmcli) - Preferred method
  - OR hostapd + wpa_supplicant - Fallback for embedded
  - dnsmasq or systemd-resolved - For DHCP server

  **Permissions:**
  - NetworkManager access via D-Bus (usually automatic)
  - OR root/sudo for hostapd/wpa_supplicant

  **Hardware:**
  - WiFi adapter with AP mode support (most adapters)
  - Check with: `iw list | grep "AP$"`

  ## Installation

  ```bash
  # Debian/Ubuntu
  sudo apt-get install network-manager dnsmasq

  # Fedora/RHEL
  sudo dnf install NetworkManager dnsmasq

  # Check NetworkManager is running
  systemctl status NetworkManager
  ```

  ## Security Note

  Hotspots use WPA2-PSK with:
  - Unique SSID per node (includes node_id)
  - Time-bounded PSK (rotates every session)
  - Credentials transmitted via GATT (BLE encrypted)
  - Optional: mTLS on HTTP layer after connection

  ## Related Modules

  - `AiReality2Transnet.Bluetooth` - BLE discovery layer
  - `AiReality2Transnet.ConnectionManager` - Hotspot/client connection management
  - `AiReality2Transnet.ConnectionAssessor` - Connection quality assessment and handover
  - `AiReality2Transnet.GattProtocol` - Join offer transmission
  - `Reality2Web` - GraphQL endpoint (port 4005) for sentantAll exchange

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  require Logger

  @type wifi_adapter :: %{
          transport: String.t(),
          interface: String.t(),
          address: String.t(),
          mode: :ap | :station | :inactive,
          current_ssid: String.t() | nil,
          ip_address: String.t() | nil
        }

  @type hotspot_config :: %{
          ssid: String.t(),
          psk: String.t(),
          channel: integer(),
          ip_address: String.t(),
          dhcp_range_start: String.t(),
          dhcp_range_end: String.t()
        }

  @type connection_status :: %{
          state: :connected | :connecting | :disconnected,
          ssid: String.t() | nil,
          ip_address: String.t() | nil,
          signal_strength: integer() | nil
        }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public API - Adapter Management
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Lists all WiFi adapters available on the system.

  Uses NetworkManager to enumerate WiFi devices and their current state.

  ## Returns

  - `{:ok, [adapter]}` - List of WiFi adapters with metadata
  - `{:error, reason}` - Failed to list adapters

  ## Adapter Information

  Each adapter map contains:
  - `:transport` - Always "wifi"
  - `:interface` - Physical interface name (e.g., "wlan0", "wlp3s0")
  - `:address` - MAC address of the WiFi adapter
  - `:mode` - Current mode (:ap, :station, :inactive)
  - `:current_ssid` - Connected network name if in station mode
  - `:ip_address` - Current IP address if assigned

  ## Examples

      iex> AiReality2Transnet.Wifi.list_adapters()
      {:ok, [
        %{
          transport: "wifi",
          interface: "wlan0",
          address: "aa:bb:cc:dd:ee:ff",
          mode: :inactive,
          current_ssid: nil,
          ip_address: nil
        }
      ]}
  """
  @spec list_adapters() :: {:ok, [wifi_adapter()]} | {:error, String.t()}
  def list_adapters do
    case System.cmd("nmcli", ["-t", "-f", "DEVICE,TYPE,STATE", "device"], stderr_to_stdout: true) do
      {output, 0} ->
        adapters =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(fn line ->
            parts = String.split(line, ":")
            Enum.at(parts, 1) == "wifi"
          end)
          |> Enum.map(fn line ->
            [interface, _type, state] = String.split(line, ":")

            %{
              transport: "wifi",
              interface: interface,
              address: get_mac_address(interface),
              mode: parse_device_mode(state),
              current_ssid: get_current_ssid(interface),
              ip_address: extract_ip(get_interface_ip(interface))
            }
          end)

        {:ok, adapters}

      {error, _code} ->
        {:error, "nmcli_failed: #{String.trim(error)}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Checks if an adapter supports AP (hotspot) mode.

  ## Parameters
  - `interface` - WiFi interface name

  ## Returns
  - `{:ok, true/false}` - Whether AP mode is supported
  - `{:error, reason}` - Failed to check

  ## Example

      iex> Wifi.supports_ap_mode("wlan0")
      {:ok, true}
  """
  @spec supports_ap_mode(String.t()) :: {:ok, boolean()} | {:error, String.t()}
  def supports_ap_mode(_interface) do
    case System.cmd("iw", ["list"], stderr_to_stdout: true) do
      {output, 0} ->
        # Check for "* AP" in supported interface modes
        supports_ap = String.contains?(output, "* AP\n") or String.contains?(output, "\t* AP")
        {:ok, supports_ap}

      {error, _} ->
        {:error, "iw_list_failed: #{error}"}
    end
  rescue
    _ -> {:error, "iw_command_not_found"}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public API - Hotspot Operations (AP Mode)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Starts a WiFi hotspot on the specified interface.

  Creates a WPA2-PSK access point that other devices can connect to.

  ## Parameters
  - `interface` - WiFi interface (e.g., "wlan0")
  - `ssid` - Network name (e.g., "R2-abc123")
  - `psk` - WPA2 password (must be 8-63 characters)
  - `channel` - WiFi channel (default: 6 for 2.4GHz)

  ## Returns
  - `{:ok, connection_uuid}` - Hotspot started successfully
  - `{:error, reason}` - Failed to start hotspot

  ## IP Assignment
  - Hotspot automatically gets IP based on SSID hash
  - Subnet: `192.168.X.0/24` where X = hash(ssid) mod 254
  - Hotspot IP: `192.168.X.1`
  - DHCP range: `.10` to `.250`

  ## Examples

      iex> Wifi.start_hotspot("wlan0", "R2-node123", "secretpass", 6)
      {:ok, "uuid-1234-5678"}

  ## Note
  This automatically handles:
  - IP address assignment
  - DHCP server configuration
  - Firewall rules for client access
  """
  @spec start_hotspot(String.t(), String.t(), String.t(), integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  def start_hotspot(interface, ssid, psk, _channel \\ 6) do
    # Disconnect from any current WiFi network on this interface
    # Most adapters can't be client + AP simultaneously
    Logger.info("[Wifi] Disconnecting #{interface} from current network to start hotspot...")
    System.cmd("nmcli", ["device", "disconnect", interface], stderr_to_stdout: true)
    # Brief pause to let the interface settle
    Process.sleep(500)

    # Use the simpler nmcli hotspot command - handles everything automatically
    # Note: We don't specify channel to avoid "channel requires band" errors
    # nmcli will auto-select an appropriate channel
    args = [
      "device", "wifi", "hotspot",
      "ifname", interface,
      "ssid", ssid,
      "password", psk
    ]

    Logger.info("[Wifi] Starting hotspot: SSID=#{ssid}")

    case System.cmd("nmcli", args, stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("[Wifi] Hotspot started successfully: #{ssid}")
        # Extract connection info from output if available
        uuid = extract_connection_uuid(output) || "hotspot-#{ssid}"

        # Configure NAT so hotspot clients can access the internet
        configure_nat_for_hotspot(interface)

        {:ok, uuid}

      {error, exit_code} ->
        Logger.error("[Wifi] Hotspot creation failed (exit #{exit_code}): #{error}")
        {:error, "hotspot_creation_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Stops a currently running hotspot.

  ## Parameters
  - `interface` - WiFi interface

  ## Returns
  - `:ok` - Hotspot stopped
  - `{:error, reason}` - Failed to stop hotspot
  """
  @spec stop_hotspot(String.t()) :: :ok | {:error, String.t()}
  def stop_hotspot(interface) do
    # Clean up NAT rules first
    cleanup_nat_for_hotspot(interface)

    # Get active connection on interface
    case get_active_connection(interface) do
      {:ok, connection_name} ->
        case System.cmd("nmcli", ["connection", "down", connection_name], stderr_to_stdout: true) do
          {_, 0} ->
            # Delete the connection profile
            System.cmd("nmcli", ["connection", "delete", connection_name], stderr_to_stdout: true)
            Logger.info("[Wifi] Hotspot stopped on #{interface}")
            :ok

          {error, _} ->
            {:error, "hotspot_stop_failed: #{error}"}
        end

      {:error, :no_active_connection} ->
        :ok

      error ->
        error
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Gets the hotspot IP address for an interface.

  ## Parameters
  - `interface` - WiFi interface

  ## Returns
  - `{:ok, ip_address}` - Hotspot IP (e.g., "192.168.42.1")
  - `{:error, reason}` - Not in hotspot mode or no IP
  """
  @spec get_hotspot_ip(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_hotspot_ip(interface) do
    get_interface_ip(interface)
  end

  @doc """
  Gets list of currently connected clients to the hotspot.

  ## Parameters
  - `interface` - WiFi interface running hotspot

  ## Returns
  - `{:ok, [client_mac]}` - List of connected client MAC addresses
  - `{:error, reason}` - Failed to get clients

  ## Example

      iex> Wifi.get_connected_clients("wlan0")
      {:ok, ["aa:bb:cc:dd:ee:ff", "11:22:33:44:55:66"]}
  """
  @spec get_connected_clients(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def get_connected_clients(interface) do
    # Use iw to get station info
    case System.cmd("iw", ["dev", interface, "station", "dump"], stderr_to_stdout: true) do
      {output, 0} ->
        clients =
          output
          |> String.split("\n")
          |> Enum.filter(&String.starts_with?(&1, "Station "))
          |> Enum.map(fn line ->
            line
            |> String.trim_leading("Station ")
            |> String.split()
            |> List.first()
          end)

        {:ok, clients}

      {error, _} ->
        {:error, "station_dump_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public API - Client Operations (Station Mode)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Connects to a WiFi network as a client.

  ## Parameters
  - `interface` - WiFi interface
  - `ssid` - Network name to connect to
  - `psk` - WPA2 password

  ## Returns
  - `{:ok, connection_uuid}` - Connected successfully
  - `{:error, reason}` - Failed to connect

  ## Examples

      iex> Wifi.connect_to_network("wlan0", "R2-node123", "secretpass")
      {:ok, "uuid-1234-5678"}

  ## Note
  This will:
  - Disconnect from any current network
  - Create a new connection profile
  - Wait for DHCP IP assignment
  """
  @spec connect_to_network(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def connect_to_network(interface, ssid, psk) do
    # First, disconnect from any current connection
    disconnect_from_network(interface)

    # Use nmcli to connect
    args = [
      "device", "wifi", "connect",
      ssid,
      "password", psk,
      "ifname", interface
    ]

    case System.cmd("nmcli", args, stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("[Wifi] Connected to network: SSID=#{ssid}")

        # Wait for IP assignment with retries
        case wait_for_ip_assignment(interface, 5) do
          {:ok, ip} ->
            Logger.info("[Wifi] IP assigned: #{ip}")
            {:ok, ip}

          {:error, :timeout} ->
            Logger.error("[Wifi] Connected but DHCP failed - no IP assigned after retries")
            {:error, "dhcp_timeout"}
        end

      {error, _} ->
        {:error, "connect_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Disconnects from the current WiFi network.

  ## Parameters
  - `interface` - WiFi interface

  ## Returns
  - `:ok` - Disconnected or already disconnected
  - `{:error, reason}` - Failed to disconnect
  """
  @spec disconnect_from_network(String.t()) :: :ok | {:error, String.t()}
  def disconnect_from_network(interface) do
    case get_active_connection(interface) do
      {:ok, connection_name} ->
        case System.cmd("nmcli", ["connection", "down", connection_name], stderr_to_stdout: true) do
          {_, 0} ->
            Logger.info("[Wifi] Disconnected from #{connection_name}")
            :ok

          {error, _} ->
            {:error, "disconnect_failed: #{error}"}
        end

      {:error, :no_active_connection} ->
        :ok

      error ->
        error
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Gets the current connection status for an interface.

  ## Parameters
  - `interface` - WiFi interface

  ## Returns
  - `{:ok, status}` - Connection status details
  - `{:error, reason}` - Failed to get status

  ## Example

      iex> Wifi.get_connection_status("wlan0")
      {:ok, %{
        state: :connected,
        ssid: "R2-node123",
        ip_address: "192.168.42.15",
        signal_strength: -45
      }}
  """
  @spec get_connection_status(String.t()) :: {:ok, connection_status()} | {:error, String.t()}
  def get_connection_status(interface) do
    with {:ok, device_state} <- get_device_state(interface),
         {:ok, ssid} <- get_current_ssid_result(interface),
         {:ok, ip} <- get_interface_ip(interface),
         {:ok, signal} <- get_signal_strength(interface) do

      status = %{
        state: parse_connection_state(device_state),
        ssid: ssid,
        ip_address: ip,
        signal_strength: signal
      }

      {:ok, status}
    else
      error -> error
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Scans for available WiFi networks.

  ## Parameters
  - `interface` - WiFi interface

  ## Returns
  - `{:ok, [network]}` - List of available networks
  - `{:error, reason}` - Failed to scan

  ## Example

      iex> Wifi.scan_networks("wlan0")
      {:ok, [
        %{ssid: "R2-node123", signal: -45, security: "WPA2"},
        %{ssid: "R2-node456", signal: -67, security: "WPA2"}
      ]}
  """
  @spec scan_networks(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def scan_networks(interface) do
    # Request rescan
    System.cmd("nmcli", ["device", "wifi", "rescan", "ifname", interface], stderr_to_stdout: true)

    # Wait for scan to complete
    Process.sleep(2000)

    case System.cmd("nmcli", ["-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "ifname", interface], stderr_to_stdout: true) do
      {output, 0} ->
        networks =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            case String.split(line, ":") do
              [ssid, signal, security] ->
                %{
                  ssid: ssid,
                  signal: String.to_integer(signal),
                  security: security
                }

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, networks}

      {error, _} ->
        {:error, "scan_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Scans for and returns Reality2 node hotspots.

  Filters scan results to only include SSIDs matching R2Node_ pattern
  (or custom R2 node names).

  ## Parameters
  - `interface` - WiFi interface name (e.g., "wlan0")

  ## Returns
  - `{:ok, hotspots}` - List of R2 hotspot maps with ssid and psk (derived)
  - `{:error, reason}` - Scan failed

  ## Example

      iex> Wifi.find_r2_hotspots("wlan0")
      {:ok, [
        %{ssid: "R2Node_A3F7", signal: -45, psk: "derived_psk_here"},
        %{ssid: "R2Node_B2C1", signal: -67, psk: "derived_psk_here"}
      ]}
  """
  @spec find_r2_hotspots(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def find_r2_hotspots(interface) do
    case scan_networks(interface) do
      {:ok, networks} ->
        r2_hotspots =
          networks
          |> Enum.filter(fn net -> String.starts_with?(net.ssid, "R2Node_") or String.starts_with?(net.ssid, "R2-") end)
          |> Enum.map(fn net ->
            Map.put(net, :psk, generate_psk_for_node(net.ssid))
          end)
          |> Enum.sort_by(fn net -> net.signal end, :desc)  # Best signal first

        {:ok, r2_hotspots}

      error ->
        error
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public API - Utility Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Generates a secure random PSK for hotspot use.

  ## Parameters
  - `length` - Password length (default: 16, min: 8, max: 63)

  ## Returns
  - String with random alphanumeric password

  ## Example

      iex> Wifi.generate_psk()
      "aB3dE7gH9kL2nP5q"
  """
  @spec generate_psk(integer()) :: String.t()
  def generate_psk(length \\ 16) do
    length = max(8, min(63, length))

    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
  end

  @doc """
  Generates a deterministic PSK from a node name.

  This allows nodes to predict each other's hotspot credentials based on
  the SSID (node_name). Uses HMAC-SHA256 with a shared secret to derive
  the password deterministically.

  ## Parameters
  - `node_name` - The node's name (same as SSID)

  ## Returns
  - 16-character alphanumeric PSK derived from the node name

  ## Security Note
  This provides predictable credentials for auto-discovery. For higher
  security deployments, use GATT credential exchange with random PSK.

  ## Example

      iex> Wifi.generate_psk_for_node("R2Node_A3F7")
      "xY9kL2mN3pQ4rS5t"
  """
  @spec generate_psk_for_node(String.t()) :: String.t()
  def generate_psk_for_node(node_name) do
    # Shared secret - in production this could come from config
    secret = Application.get_env(:ai_reality2_transnet, :psk_secret, "R2TransnetSharedSecret2024")

    # Derive PSK using HMAC-SHA256
    :crypto.mac(:hmac, :sha256, secret, node_name)
    |> Base.encode64()
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> binary_part(0, 16)
  end

  @doc """
  Generates the SSID for the WiFi hotspot using the node name.

  The SSID is the node's name, which is determined by:
  1. Environment variable `R2_NODE_NAME` (if set)
  2. Auto-generated name in format "R2Node_XXXX" (4 random alphanumeric chars)

  This ensures each Reality2 node has a unique, identifiable SSID.

  ## Returns
  - SSID string (e.g., "R2Node_A3F7" or custom name from R2_NODE_NAME env var)

  ## Examples

      # With R2_NODE_NAME env var set to "MyNode"
      iex> Wifi.generate_ssid()
      "MyNode"

      # Without R2_NODE_NAME env var (auto-generated)
      iex> Wifi.generate_ssid()
      "R2Node_A3F7"
  """
  @spec generate_ssid() :: String.t()
  def generate_ssid do
    # Use the node_name from Bootstrap as the SSID
    # This is either set via R2_NODE_NAME env var or auto-generated as "R2Node_XXXX"
    Reality2.Bootstrap.get(:node_name, "R2Node")
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Get MAC address for interface
  defp get_mac_address(interface) do
    case System.cmd("cat", ["/sys/class/net/#{interface}/address"], stderr_to_stdout: true) do
      {address, 0} -> String.trim(address)
      _ -> "unknown"
    end
  end

  # Extract IP from result tuple, returning nil on error
  defp extract_ip({:ok, ip}), do: ip
  defp extract_ip({:error, _}), do: nil

  # Wait for IP assignment with retries (DHCP can take time)
  defp wait_for_ip_assignment(interface, retries_left) when retries_left > 0 do
    case get_interface_ip(interface) do
      {:ok, ip} ->
        {:ok, ip}

      {:error, _} ->
        Logger.debug("[Wifi] Waiting for DHCP IP assignment (#{retries_left} retries left)...")
        Process.sleep(2_000)
        wait_for_ip_assignment(interface, retries_left - 1)
    end
  end

  defp wait_for_ip_assignment(_interface, 0), do: {:error, :timeout}

  # Parse device mode from nmcli state
  defp parse_device_mode("connected (externally)"), do: :ap
  defp parse_device_mode("connected"), do: :station
  defp parse_device_mode(_), do: :inactive

  # Get current SSID if connected
  defp get_current_ssid(interface) do
    case System.cmd("nmcli", ["-t", "-f", "ACTIVE,SSID", "device", "wifi", "list", "ifname", interface], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.find_value(fn line ->
          case String.split(line, ":") do
            ["yes", ssid] -> ssid
            _ -> nil
          end
        end)

      _ ->
        nil
    end
  end

  # Get current SSID (result variant)
  defp get_current_ssid_result(interface) do
    case get_current_ssid(interface) do
      nil -> {:error, :not_connected}
      ssid -> {:ok, ssid}
    end
  end

  @doc """
  Gets the current IP address of an interface.

  ## Parameters
  - `interface` - Network interface name (e.g., "wlan0")

  ## Returns
  - `{:ok, ip}` - IP address string
  - `{:error, reason}` - Failed to get IP
  """
  @spec get_interface_ip(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_interface_ip(interface) do
    case System.cmd("ip", ["-4", "addr", "show", interface], stderr_to_stdout: true) do
      {output, 0} ->
        case parse_ip_from_output(output) do
          nil -> {:error, :no_ip_address}
          ip -> {:ok, ip}
        end

      _ ->
        {:error, :interface_not_found}
    end
  end

  # Parse IP from ip addr output
  defp parse_ip_from_output(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      if String.contains?(line, "inet ") do
        line
        |> String.trim()
        |> String.split()
        |> Enum.at(1)
        |> String.split("/")
        |> List.first()
      end
    end)
  end

  # Get active connection name for interface
  defp get_active_connection(interface) do
    case System.cmd("nmcli", ["-t", "-f", "DEVICE,NAME", "connection", "show", "--active"], stderr_to_stdout: true) do
      {output, 0} ->
        result =
          output
          |> String.split("\n", trim: true)
          |> Enum.find_value(fn line ->
            case String.split(line, ":") do
              [^interface, name] -> name
              _ -> nil
            end
          end)

        case result do
          nil -> {:error, :no_active_connection}
          name -> {:ok, name}
        end

      {error, _} ->
        {:error, "query_failed: #{error}"}
    end
  end

  # Extract connection UUID from nmcli output
  defp extract_connection_uuid(output) do
    case Regex.run(~r/\(([a-f0-9-]+)\)/, output) do
      [_, uuid] -> uuid
      _ -> "unknown"
    end
  end

  # Get device state
  defp get_device_state(interface) do
    case System.cmd("nmcli", ["-t", "-f", "STATE", "device", "show", interface], stderr_to_stdout: true) do
      {output, 0} ->
        state = output |> String.trim() |> String.split(":") |> List.last()
        {:ok, state}

      {error, _} ->
        {:error, "device_query_failed: #{error}"}
    end
  end

  # Parse connection state
  defp parse_connection_state("100 (connected)"), do: :connected
  defp parse_connection_state("connecting"), do: :connecting
  defp parse_connection_state(_), do: :disconnected

  # Get signal strength
  defp get_signal_strength(interface) do
    case System.cmd("nmcli", ["-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "ifname", interface], stderr_to_stdout: true) do
      {output, 0} ->
        signal =
          output
          |> String.split("\n", trim: true)
          |> Enum.find_value(fn line ->
            case String.split(line, ":") do
              ["*", signal] -> String.to_integer(signal)
              _ -> nil
            end
          end)

        case signal do
          nil -> {:error, :no_signal}
          sig -> {:ok, sig}
        end

      {error, _} ->
        {:error, "signal_query_failed: #{error}"}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # System Dependency Checks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Checks if required system commands are available.

  ## Returns
  - `{:ok, :all_available}` - All required commands found
  - `{:error, missing_commands}` - List of missing commands

  ## Example

      iex> Wifi.check_dependencies()
      {:ok, :all_available}
  """
  @spec check_dependencies() :: {:ok, :all_available} | {:error, list(map())}
  def check_dependencies do
    required = [
      %{
        command: "nmcli",
        debian: "sudo apt install network-manager",
        fedora: "sudo dnf install NetworkManager",
        arch: "sudo pacman -S networkmanager"
      },
      %{
        command: "iw",
        debian: "sudo apt install iw",
        fedora: "sudo dnf install iw",
        arch: "sudo pacman -S iw"
      }
    ]

    missing =
      Enum.filter(required, fn %{command: cmd} ->
        case System.cmd("which", [cmd], stderr_to_stdout: true) do
          {_, 0} -> false
          _ -> true
        end
      end)

    case missing do
      [] -> {:ok, :all_available}
      commands -> {:error, commands}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Host Capability Checking
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Checks if this node has internet access.

  Performs a quick connectivity test to a reliable external endpoint.

  ## Returns
  - `true` - Internet is reachable
  - `false` - No internet access
  """
  @spec has_internet_access?() :: boolean()
  def has_internet_access? do
    # Try to ping a reliable DNS server (Google's 8.8.8.8)
    # Using a short timeout to avoid blocking
    case System.cmd("ping", ["-c", "1", "-W", "2", "8.8.8.8"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Checks if this node has a wired (non-WiFi) interface with actual internet access.

  This is important because:
  - A node with Ethernet + WiFi can host a hotspot AND keep internet
  - A node with only WiFi loses internet when it becomes a hotspot

  Note: Excludes virtual bridges (virbr0, docker0, br-*, veth*, etc.) which
  are "wired" but only provide internal VM/container networking.

  ## Returns
  - `true` - Has real wired internet (Ethernet, USB, etc.)
  - `false` - Only has WiFi, virtual bridges, or no internet
  """
  @spec has_wired_internet?() :: boolean()
  def has_wired_internet? do
    # Get the interface that's actually used for internet traffic
    case get_internet_interface() do
      {:ok, interface} ->
        # Check if it's a real wired interface (not WiFi, not virtual)
        is_real_wired_interface?(interface)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  # Get the interface that's actually used for internet traffic
  defp get_internet_interface do
    # Use ip route get to find which interface reaches the internet
    case System.cmd("ip", ["route", "get", "8.8.8.8"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output like: "8.8.8.8 via 192.168.1.1 dev eth0 src 192.168.1.67"
        case Regex.run(~r/dev\s+(\S+)/, output) do
          [_, interface] -> {:ok, interface}
          _ -> {:error, :no_interface}
        end

      _ ->
        {:error, :route_failed}
    end
  end

  # Check if an interface is a real wired interface (not WiFi, not virtual)
  defp is_real_wired_interface?(interface) do
    # WiFi interfaces - start with wl
    is_wifi = String.starts_with?(interface, "wl")

    # Virtual/bridge interfaces to exclude:
    # - virbr* : libvirt virtual bridges
    # - docker* : Docker bridges
    # - br-* : Docker/bridge networks
    # - veth* : Virtual ethernet (containers)
    # - lo : Loopback
    # - tun* : VPN tunnels
    # - tap* : VPN/VM interfaces
    is_virtual = String.starts_with?(interface, "virbr") ||
                 String.starts_with?(interface, "docker") ||
                 String.starts_with?(interface, "br-") ||
                 String.starts_with?(interface, "veth") ||
                 String.starts_with?(interface, "tun") ||
                 String.starts_with?(interface, "tap") ||
                 interface == "lo"

    # Real wired = not WiFi and not virtual
    !is_wifi && !is_virtual
  end

  @doc """
  Checks if this node has multiple WiFi adapters.

  With 2+ WiFi adapters, one can stay connected to internet (station mode)
  while the other runs as a hotspot (AP mode).

  ## Returns
  - `true` - Has 2 or more WiFi adapters
  - `false` - Has 0 or 1 WiFi adapter
  """
  @spec has_multiple_wifi_adapters?() :: boolean()
  def has_multiple_wifi_adapters? do
    case list_adapters() do
      {:ok, adapters} when length(adapters) >= 2 -> true
      _ -> false
    end
  end

  @doc """
  Checks if this node can provide NAT (has multiple network interfaces with one having internet).

  A node can provide NAT if:
  1. It has at least 2 network interfaces (e.g., eth0 + wlan0)
  2. One interface has internet access
  3. The WiFi interface can run as a hotspot

  ## Returns
  - `true` - Can provide NAT for hotspot clients
  - `false` - Cannot provide NAT
  """
  @spec can_provide_nat?() :: boolean()
  def can_provide_nat? do
    # Count non-loopback interfaces with IP addresses
    case System.cmd("ip", ["-4", "-o", "addr", "show"], stderr_to_stdout: true) do
      {output, 0} ->
        interfaces = output
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            case Regex.run(~r/^\d+:\s+(\S+)\s+/, line) do
              [_, interface] -> interface
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == "lo"))  # Exclude loopback
          |> Enum.uniq()

        # Need at least 2 interfaces and internet access
        length(interfaces) >= 2 && has_internet_access?()

      _ ->
        false
    end
  rescue
    _ -> false
  end

  @doc """
  Gets a hosting priority score for this node.

  Higher score = better host candidate.

  ## Scoring:
  - 100: Has WIRED internet + WiFi, OR has 2+ WiFi adapters with internet - BEST
         (can NAT and keeps internet as host)
  - 75: Has internet + multiple interfaces but single WiFi (may lose internet)
  - 50: Has internet but single interface (will lose internet as host)
  - 10: No internet but has WiFi (can still host locally)
  - 0: No WiFi capability

  The key distinction is whether the node can maintain internet while hosting:
  - Wired internet (Ethernet) is retained when WiFi becomes a hotspot
  - Multiple WiFi adapters: one for internet, one for hotspot
  - Single WiFi: loses internet when it becomes a hotspot

  ## Returns
  - Integer score (0-100)
  """
  @spec get_hosting_priority() :: integer()
  def get_hosting_priority do
    has_wifi = case list_adapters() do
      {:ok, [_ | _]} -> true
      _ -> false
    end

    has_wired = has_wired_internet?()
    has_multi_wifi = has_multiple_wifi_adapters?()
    has_internet = has_internet_access?()
    can_nat = can_provide_nat?()

    # Can maintain internet while hosting if:
    # - Has wired internet (Ethernet stays connected)
    # - Has 2+ WiFi adapters (one for internet, one for hotspot)
    can_host_with_internet = (has_wired || has_multi_wifi) && has_internet

    cond do
      !has_wifi -> 0
      can_host_with_internet && can_nat -> 100  # Best: keeps internet while hosting
      can_nat -> 75                              # Good: can NAT but may lose internet
      has_internet -> 50                         # OK: has internet but single interface
      true -> 10                                 # Basic: can host but no internet
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # NAT Configuration for Hotspot Internet Sharing
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Configures NAT to allow hotspot clients to access the internet through the host.

  This enables IP forwarding and sets up iptables MASQUERADE rules so that
  clients connected to the R2 hotspot can reach external networks.
  """
  defp configure_nat_for_hotspot(hotspot_interface) do
    # Find the upstream interface (the one with internet access)
    case find_upstream_interface(hotspot_interface) do
      {:ok, upstream_interface} ->
        Logger.info("[Wifi] Configuring NAT: #{hotspot_interface} -> #{upstream_interface}")

        # Get the hotspot subnet (typically 10.42.0.0/24 for NetworkManager hotspots)
        hotspot_subnet = get_hotspot_subnet(hotspot_interface)

        # Enable IP forwarding
        case System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"], stderr_to_stdout: true) do
          {_, 0} ->
            Logger.debug("[Wifi] IP forwarding enabled")

          {error, _} ->
            Logger.warning("[Wifi] Failed to enable IP forwarding: #{error}")
        end

        # Add iptables MASQUERADE rule for NAT
        # This allows hotspot clients to access the internet through the upstream interface
        iptables_args = [
          "-t", "nat",
          "-A", "POSTROUTING",
          "-s", hotspot_subnet,
          "-o", upstream_interface,
          "-j", "MASQUERADE"
        ]

        case System.cmd("iptables", iptables_args, stderr_to_stdout: true) do
          {_, 0} ->
            Logger.info("[Wifi] NAT configured: clients on #{hotspot_subnet} can access internet via #{upstream_interface}")

          {error, _} ->
            Logger.warning("[Wifi] Failed to configure NAT iptables rule: #{error}")
        end

        # Allow forwarding between interfaces
        forward_args = [
          "-A", "FORWARD",
          "-i", hotspot_interface,
          "-o", upstream_interface,
          "-j", "ACCEPT"
        ]
        System.cmd("iptables", forward_args, stderr_to_stdout: true)

        reverse_forward_args = [
          "-A", "FORWARD",
          "-i", upstream_interface,
          "-o", hotspot_interface,
          "-m", "state",
          "--state", "RELATED,ESTABLISHED",
          "-j", "ACCEPT"
        ]
        System.cmd("iptables", reverse_forward_args, stderr_to_stdout: true)

        :ok

      {:error, reason} ->
        Logger.warning("[Wifi] Cannot configure NAT - no upstream interface: #{reason}")
        :ok
    end
  end

  @doc """
  Cleans up NAT rules when stopping the hotspot.
  """
  defp cleanup_nat_for_hotspot(hotspot_interface) do
    case find_upstream_interface(hotspot_interface) do
      {:ok, upstream_interface} ->
        hotspot_subnet = get_hotspot_subnet(hotspot_interface)

        Logger.info("[Wifi] Cleaning up NAT rules for #{hotspot_interface}")

        # Remove MASQUERADE rule
        iptables_args = [
          "-t", "nat",
          "-D", "POSTROUTING",
          "-s", hotspot_subnet,
          "-o", upstream_interface,
          "-j", "MASQUERADE"
        ]
        System.cmd("iptables", iptables_args, stderr_to_stdout: true)

        # Remove FORWARD rules
        forward_args = [
          "-D", "FORWARD",
          "-i", hotspot_interface,
          "-o", upstream_interface,
          "-j", "ACCEPT"
        ]
        System.cmd("iptables", forward_args, stderr_to_stdout: true)

        reverse_forward_args = [
          "-D", "FORWARD",
          "-i", upstream_interface,
          "-o", hotspot_interface,
          "-m", "state",
          "--state", "RELATED,ESTABLISHED",
          "-j", "ACCEPT"
        ]
        System.cmd("iptables", reverse_forward_args, stderr_to_stdout: true)

        :ok

      {:error, _} ->
        :ok
    end
  end

  # Find the upstream interface that has internet access
  # This is typically the interface with a default route, excluding the hotspot interface
  defp find_upstream_interface(hotspot_interface) do
    case System.cmd("ip", ["route", "show", "default"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output like: "default via 192.168.1.1 dev eth0 proto dhcp metric 100"
        # There may be multiple default routes, find one that's not the hotspot interface
        interfaces = output
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            case Regex.run(~r/dev\s+(\S+)/, line) do
              [_, interface] -> interface
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == hotspot_interface))

        case interfaces do
          [upstream | _] -> {:ok, upstream}
          [] -> {:error, :no_upstream_interface}
        end

      {error, _} ->
        {:error, "ip_route_failed: #{error}"}
    end
  end

  # Get the subnet for the hotspot interface
  # NetworkManager typically uses 10.42.0.0/24 for hotspots
  defp get_hotspot_subnet(interface) do
    case get_interface_ip(interface) do
      {:ok, ip} ->
        # Convert IP to subnet (e.g., 10.42.0.1 -> 10.42.0.0/24)
        parts = String.split(ip, ".")
        if length(parts) == 4 do
          [a, b, c, _d] = parts
          "#{a}.#{b}.#{c}.0/24"
        else
          "10.42.0.0/24"  # Default fallback
        end

      {:error, _} ->
        "10.42.0.0/24"  # Default fallback
    end
  end
end
