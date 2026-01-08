defmodule AiReality2Transnet.Wifi do
  @moduledoc """
  WiFi Mesh Networking for Reality2 Transient Networks.

  This module implements IEEE 802.11s WiFi mesh networking using Linux kernel's built-in
  mesh capabilities. It provides high-bandwidth peer-to-peer communication to complement
  BLE discovery in the Reality2 transient networking architecture.

  ## Architecture Overview

  Reality2 uses a **two-phase discovery and communication model**:

  ```
  Phase 1: BLE Discovery (Low Power)
  ┌─────────────────────────────────────────┐
  │  Beacon Broadcasting + Scanning         │
  │  - Always on, low power                 │
  │  - Discovers nearby Reality2 nodes      │
  │  - Provides node UUID and RSSI          │
  └─────────────────────────────────────────┘
                    ↓
  Phase 2: WiFi Mesh Upgrade (High Bandwidth)
  ┌─────────────────────────────────────────┐
  │  IEEE 802.11s Mesh Networking           │
  │  - On-demand, high bandwidth            │
  │  - GraphQL queries for Sentants         │
  │  - No 512-byte BLE limit                │
  │  - Multi-hop routing (HWMP)             │
  └─────────────────────────────────────────┘
  ```

  ## IEEE 802.11s Overview

  IEEE 802.11s is a standard for self-organizing wireless mesh networks:

  - **Ad-hoc formation**: Nodes automatically discover and connect to each other
  - **No infrastructure**: No access points or routers required
  - **Multi-hop routing**: HWMP (Hybrid Wireless Mesh Protocol) finds paths through intermediate nodes
  - **Automatic addressing**: IPv6 link-local addresses (fe80::) assigned automatically
  - **Self-healing**: Routes automatically reconfigure when nodes join/leave

  ## Why Pure Elixir?

  Unlike the BLE layer (which uses Rust NIFs), WiFi mesh is implemented in pure Elixir:

  - **Simple**: Just shell out to `iw` and `ip` commands
  - **Leverages kernel**: Linux kernel handles 802.11s protocol, routing, and addressing
  - **No overhead**: Standard Linux tools, no custom protocol needed
  - **Reliable**: Battle-tested kernel implementation
  - **Maintainable**: Easy to understand and modify

  ## Typical Usage Flow

  ```elixir
  # 1. List available WiFi adapters
  {:ok, adapters} = Wifi.list_adapters()
  # => [%{interface: "wlan0", ...}]

  # 2. Create mesh interface
  :ok = Wifi.create_mesh_interface("wlan0", "mesh0")

  # 3. Join mesh network (ALL nodes must use same mesh_id!)
  :ok = Wifi.start_mesh("mesh0", "R2MESH", 2437)

  # 4. Get your IPv6 link-local address
  {:ok, ipv6} = Wifi.get_ipv6_link_local("mesh0")
  # => "fe80::aabb:ccff:fedd:eeff"

  # 5. Check for mesh peers
  {:ok, peers} = Wifi.list_mesh_peers("mesh0")
  # => [%{mac_address: "aa:bb:cc:dd:ee:ff", signal_strength: -45, ...}]
  ```

  ## Mesh ID (ESSID)

  The mesh ID acts like a network name (ESSID in traditional WiFi):
  - **Must match** on all nodes for peering to occur
  - **Case-sensitive**
  - **Typically 1-32 characters**
  - **Examples**: "R2MESH", "REALITY2_MESH", "MyMeshNetwork"

  Think of it like a "club membership" - only nodes with the same mesh ID can connect.

  ## Channels and Frequency

  Common 2.4 GHz channels (use these for widest device compatibility):
  - Channel 1: 2412 MHz
  - Channel 6: 2437 MHz (recommended - least interference)
  - Channel 11: 2462 MHz

  5 GHz channels (better performance, less range):
  - Channel 36: 5180 MHz
  - Channel 40: 5200 MHz
  - Channel 44: 5220 MHz

  **Important**: All nodes must use the **same frequency** to form a mesh.

  ## IPv6 Link-Local Addresses

  WiFi mesh uses IPv6 link-local addresses for peer communication:
  - Automatically assigned (derived from MAC address)
  - Format: `fe80::xxxx:xxxx:xxxx:xxxx`
  - Scope: Link-local (not routable beyond the mesh)
  - Usage: Specify interface with `%mesh0` suffix (e.g., `fe80::1234:5678%mesh0`)

  ## Multi-Hop Routing (HWMP)

  The kernel automatically handles routing through intermediate nodes:

  ```
  Node A ←─→ Node B ←─→ Node C
  (Can't directly reach C, routes through B)
  ```

  - **Automatic**: No configuration needed
  - **Dynamic**: Routes update as nodes move or join/leave
  - **Efficient**: Shortest path selection based on signal quality

  ## Requirements

  **System packages:**
  - `iw` - WiFi configuration tool (wireless-tools or iw package)
  - `ip` - Network interface configuration (iproute2 package)

  **Permissions:**
  - Root/sudo for interface creation (`iw dev add`)
  - Root/sudo for mesh joining (`iw dev mesh join`)

  **Hardware:**
  - WiFi adapter that supports mesh mode (IEEE 802.11s)
  - Check with: `sudo iw list | grep "mesh point"`

  ## Installation

  ```bash
  # Debian/Ubuntu
  sudo apt-get install iw iproute2

  # Fedora/RHEL
  sudo dnf install iw iproute

  # Arch Linux
  sudo pacman -S iw iproute2
  ```

  ## Troubleshooting

  **"Operation not supported"**: WiFi adapter doesn't support mesh mode
  **"Device or resource busy"**: NetworkManager is interfering, disable with:
    `sudo nmcli device set wlan0 managed no`
  **No peers appear**: Check mesh ID matches, same channel, devices in range
  **"Permission denied"**: Need root/sudo privileges

  ## Related Modules

  - `AiReality2Transnet.WifiServer` - HTTP/GraphQL server for mesh communication
  - `AiReality2Transnet.Bluetooth` - BLE discovery layer
  - `AiReality2Transnet.PeerManager` - Tracks discovered peers

  ## Further Reading

  - IEEE 802.11s: https://en.wikipedia.org/wiki/IEEE_802.11s
  - HWMP Protocol: https://en.wikipedia.org/wiki/Hybrid_Wireless_Mesh_Protocol
  - Linux Wireless: https://wireless.wiki.kernel.org/en/users/documentation/iw

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  require Logger

  @type wifi_adapter :: %{
          transport: String.t(),
          interface: String.t(),
          mesh_interface: String.t(),
          address: String.t(),
          ip_address: String.t() | nil
        }

  @type mesh_peer :: %{
          mac_address: String.t(),
          signal_strength: integer(),
          last_seen: integer()
        }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Lists all WiFi adapters available on the system.

  Uses the `iw dev` command to enumerate WiFi interfaces. Parses the output to extract
  interface names, MAC addresses, and current status.

  ## Command Used

  ```bash
  iw dev
  ```

  This lists all wireless devices managed by the kernel's cfg80211 subsystem.

  ## Returns

  - `{:ok, [adapter]}` - List of WiFi adapters with metadata
  - `{:error, reason}` - Failed to list adapters (iw not installed, permission denied, etc.)

  ## Adapter Information

  Each adapter map contains:
  - `:transport` - Always "wifi"
  - `:interface` - Physical interface name (e.g., "wlan0", "wlp3s0")
  - `:mesh_interface` - Suggested mesh interface name (e.g., "mesh0")
  - `:address` - MAC address of the WiFi adapter
  - `:ip_address` - Current IP address if assigned, otherwise `nil`

  ## Examples

      iex> AiReality2Transnet.Wifi.list_adapters()
      {:ok, [
        %{
          transport: "wifi",
          interface: "wlan0",
          mesh_interface: "mesh0",
          address: "aa:bb:cc:dd:ee:ff",
          ip_address: nil
        }
      ]}

  ## Common Errors

  - **"iw_dev_failed: command not found"** - `iw` tool not installed
  - **"iw_dev_failed: Operation not permitted"** - Need root/sudo privileges
  """
  @spec list_adapters() :: {:ok, [wifi_adapter()]} | {:error, String.t()}
  def list_adapters do
    # Run: iw dev
    # Lists all wireless network interfaces managed by the kernel
    case System.cmd("iw", ["dev"], stderr_to_stdout: true) do
      {output, 0} ->
        adapters = parse_iw_dev(output)
        {:ok, adapters}

      {error, code} ->
        cond do
          String.contains?(error, "Operation not permitted") or
              String.contains?(error, "Permission denied") ->
            {:error,
             "permission_denied: iw requires elevated privileges - see WIFI_PERMISSIONS.md for solutions"}

          code != 0 ->
            {:error, "iw_dev_failed (exit #{code}): #{String.trim(error)}"}

          true ->
            {:error, "iw_dev_failed: #{error}"}
        end
    end
  rescue
    # %ErlangError{original: :enoent} ->
    #   {:error, "iw command not found - install with: sudo apt install iw (Debian/Ubuntu) or sudo dnf install iw (Fedora)"}

    # %ErlangError{original: :eacces} ->
    #   {:error, "permission_denied: cannot execute iw command - check file permissions"}

    error ->
      {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Creates a WiFi mesh interface on the specified physical interface.

  Creates a virtual mesh point (mp) interface that will be used for 802.11s mesh networking.
  This is a **virtual interface** on top of the physical WiFi adapter - think of it like
  creating a VLAN on an Ethernet port.

  ## Command Used

  ```bash
  iw dev wlan0 interface add mesh0 type mp
  ```

  - `wlan0` - Physical WiFi interface
  - `mesh0` - New virtual mesh interface
  - `mp` - "Mesh Point" interface type (802.11s)

  ## Parameters

  - `interface` - Physical WiFi interface (e.g., "wlan0", "wlp3s0")
  - `mesh_interface` - Mesh interface name (default: "mesh0")

  ## Returns

  - `:ok` - Mesh interface created successfully
  - `:ok` - Interface already exists (idempotent operation)
  - `{:error, reason}` - Failed to create interface

  ## Permissions

  **Requires root/sudo** - Creating network interfaces is a privileged operation.

  ## Interface Naming

  Common naming conventions:
  - `mesh0` - First mesh interface (default)
  - `mesh1` - Second mesh interface (if using multiple)
  - `wlan0-mesh` - Alternative descriptive naming

  ## Examples

      # Create default mesh0 interface
      iex> AiReality2Transnet.Wifi.create_mesh_interface("wlan0")
      :ok

      # Create custom-named mesh interface
      iex> AiReality2Transnet.Wifi.create_mesh_interface("wlan0", "my_mesh")
      :ok

      # Interface already exists - still returns :ok
      iex> AiReality2Transnet.Wifi.create_mesh_interface("wlan0", "mesh0")
      :ok

  ## Common Errors

  - **"Operation not supported"** - WiFi adapter doesn't support mesh mode
  - **"Device or resource busy"** - NetworkManager is controlling the interface
  - **"Permission denied"** - Need root/sudo privileges
  - **"No such device"** - Physical interface doesn't exist

  ## Troubleshooting

  **NetworkManager interference:**
  ```bash
  sudo nmcli device set wlan0 managed no
  ```

  **Check adapter supports mesh:**
  ```bash
  sudo iw list | grep "mesh point"
  ```
  """
  @spec create_mesh_interface(String.t(), String.t()) :: :ok | {:error, String.t()}
  def create_mesh_interface(interface, mesh_interface \\ "mesh0") do
    # Run: iw dev wlan0 interface add mesh0 type mp
    # Creates a virtual "mesh point" interface for 802.11s networking
    case System.cmd("iw", ["dev", interface, "interface", "add", mesh_interface, "type", "mp"],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {error, _} ->
        # Interface might already exist, which is okay
        if String.contains?(error, "already exists") do
          :ok
        else
          {:error, "create_mesh_failed: #{error}"}
        end
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Configures and starts a WiFi mesh network.

  Joins the mesh interface to a specific mesh network (identified by mesh_id) on a specific
  frequency (channel). After joining, the interface is brought up so it can participate in
  mesh peering and routing.

  ## Command Used

  ```bash
  iw dev mesh0 mesh join R2MESH freq 2437
  ip link set mesh0 up
  ```

  ## CRITICAL: Mesh ID Must Match!

  **All nodes MUST use the same mesh ID to peer together.** Think of mesh_id like a WiFi
  network name (ESSID) - only devices with matching IDs can form a mesh.

  ## CRITICAL: Frequency Must Match!

  **All nodes MUST use the same frequency (channel) to communicate.** Mismatched channels
  won't peer, even with matching mesh IDs.

  ## Parameters

  - `mesh_interface` - Mesh interface name (e.g., "mesh0")
  - `mesh_id` - Mesh network identifier (e.g., "R2MESH", "REALITY2_MESH")
    - Case-sensitive
    - Typically 1-32 characters
    - Must match across all nodes
  - `frequency` - Channel frequency in MHz (default: 2437)
    - 2412 = Channel 1
    - 2437 = Channel 6 (recommended - least interference)
    - 2462 = Channel 11
    - 5180 = Channel 36 (5 GHz)

  ## Returns

  - `:ok` - Mesh joined and interface is up
  - `{:error, reason}` - Failed to join mesh or bring up interface

  ## Permissions

  **Requires root/sudo** - Joining mesh and bringing up interfaces are privileged operations.

  ## Examples

      # Join mesh on channel 6 (2.4 GHz)
      iex> AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH", 2437)
      :ok

      # Join mesh on channel 36 (5 GHz)
      iex> AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH_5G", 5180)
      :ok

      # Use default channel (2437)
      iex> AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH")
      :ok

  ## Mesh Peering Process

  After joining:
  1. Interface starts listening on the specified frequency
  2. Broadcasts mesh beacons advertising mesh_id
  3. Discovers other nodes with same mesh_id on same frequency
  4. Initiates mesh peering protocol (MPM)
  5. Establishes peer links (typically 10-30 seconds)
  6. Begins routing via HWMP

  ## Common Errors

  - **"No such device"** - Mesh interface doesn't exist (create it first)
  - **"Device or resource busy"** - Interface already joined to another mesh
  - **"Operation not supported"** - Adapter doesn't support mesh mode
  - **"Invalid argument"** - Invalid frequency for adapter's regulatory domain

  ## Troubleshooting

  **No peers appear:**
  - Verify all nodes use same mesh_id: `sudo iw dev mesh0 info | grep "mesh id"`
  - Verify all nodes use same channel: `sudo iw dev mesh0 info | grep channel`
  - Check devices are in range (< 50m for initial testing)
  - Check regulatory domain allows frequency: `iw reg get`

  **"Invalid argument" on 5 GHz:**
  Some countries restrict 5 GHz frequencies. Check with: `iw reg get`
  """
  @spec start_mesh(String.t(), String.t(), integer()) :: :ok | {:error, String.t()}
  def start_mesh(mesh_interface, mesh_id, frequency \\ 2437) do
    # Run: iw dev mesh0 mesh join R2MESH freq 2437
    # Joins the mesh network with specified ID on specified frequency
    case System.cmd(
           "iw",
           ["dev", mesh_interface, "mesh", "join", mesh_id, "freq", to_string(frequency)],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        # Bring interface up
        bring_interface_up(mesh_interface)

      {error, _} ->
        {:error, "mesh_join_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Brings a network interface up.

  ## Parameters
  - `interface` - Interface name

  ## Returns
  - `:ok` - Interface is up
  - `{:error, reason}` - Failed to bring up interface
  """
  @spec bring_interface_up(String.t()) :: :ok | {:error, String.t()}
  def bring_interface_up(interface) do
    case System.cmd("ip", ["link", "set", interface, "up"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {error, _} ->
        {:error, "interface_up_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Destroys a mesh interface.

  ## Parameters
  - `mesh_interface` - Mesh interface name

  ## Returns
  - `:ok` - Interface destroyed
  - `{:error, reason}` - Failed to destroy interface
  """
  @spec destroy_mesh_interface(String.t()) :: :ok | {:error, String.t()}
  def destroy_mesh_interface(mesh_interface) do
    case System.cmd("iw", ["dev", mesh_interface, "del"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {error, _} ->
        {:error, "destroy_mesh_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Gets the IPv6 link-local address for an interface.

  ## Parameters
  - `interface` - Interface name

  ## Returns
  - `{:ok, address}` - IPv6 link-local address (e.g., "fe80::1234")
  - `{:error, reason}` - Failed to get address

  ## Examples

      iex> AiReality2Transnet.Wifi.get_ipv6_link_local("mesh0")
      {:ok, "fe80::1234:5678:9abc:def0"}
  """
  @spec get_ipv6_link_local(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_ipv6_link_local(interface) do
    case System.cmd("ip", ["-6", "addr", "show", interface], stderr_to_stdout: true) do
      {output, 0} ->
        case parse_ipv6_link_local(output) do
          nil -> {:error, "no_ipv6_link_local_found"}
          address -> {:ok, address}
        end

      {error, _} ->
        {:error, "get_ipv6_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  @doc """
  Lists mesh peers connected to a mesh interface.

  ## Parameters
  - `mesh_interface` - Mesh interface name

  ## Returns
  - `{:ok, [peer]}` - List of connected peers
  - `{:error, reason}` - Failed to get peers

  ## Examples

      iex> AiReality2Transnet.Wifi.list_mesh_peers("mesh0")
      {:ok, [
        %{
          mac_address: "aa:bb:cc:dd:ee:ff",
          signal_strength: -45,
          last_seen: 1234567890
        }
      ]}
  """
  @spec list_mesh_peers(String.t()) :: {:ok, [mesh_peer()]} | {:error, String.t()}
  def list_mesh_peers(mesh_interface) do
    case System.cmd("iw", ["dev", mesh_interface, "station", "dump"], stderr_to_stdout: true) do
      {output, 0} ->
        peers = parse_station_dump(output)
        {:ok, peers}

      {error, _} ->
        {:error, "station_dump_failed: #{error}"}
    end
  rescue
    error -> {:error, "exception: #{inspect(error)}"}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Parse output from `iw dev`
  defp parse_iw_dev(output) do
    output
    |> String.split("\n")
    |> Enum.reduce({[], nil, nil}, fn line, {adapters, current_interface, current_address} ->
      trimmed = String.trim(line)

      cond do
        # Match "Interface wlan0"
        String.starts_with?(trimmed, "Interface ") ->
          interface = String.trim_leading(trimmed, "Interface ")
          {adapters, interface, current_address}

        # Match "addr aa:bb:cc:dd:ee:ff"
        String.starts_with?(trimmed, "addr ") ->
          address = String.trim_leading(trimmed, "addr ")

          # Create adapter if we have both interface and address
          adapter =
            if current_interface && address do
              %{
                transport: "wifi",
                interface: current_interface,
                mesh_interface: "mesh0",
                address: address,
                ip_address: nil
              }
            end

          new_adapters = if adapter, do: [adapter | adapters], else: adapters
          {new_adapters, nil, nil}

        true ->
          {adapters, current_interface, current_address}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # Parse IPv6 link-local address from `ip -6 addr show`
  defp parse_ipv6_link_local(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "inet6 fe80:") do
        # Extract address (format: "inet6 fe80::1234/64 scope link")
        trimmed
        |> String.trim_leading("inet6 ")
        |> String.split()
        |> List.first()
        |> then(fn addr_with_prefix ->
          # Remove /64 suffix
          String.split(addr_with_prefix, "/") |> List.first()
        end)
      end
    end)
  end

  # Parse output from `iw station dump`
  defp parse_station_dump(output) do
    output
    |> String.split("\n")
    |> Enum.reduce({[], nil, nil}, fn line, {peers, current_mac, current_signal} ->
      trimmed = String.trim(line)

      cond do
        # Match "Station aa:bb:cc:dd:ee:ff (on mesh0)"
        String.starts_with?(trimmed, "Station ") ->
          mac =
            trimmed
            |> String.trim_leading("Station ")
            |> String.split()
            |> List.first()

          {peers, mac, current_signal}

        # Match "signal: -45 dBm"
        String.starts_with?(trimmed, "signal:") ->
          signal =
            trimmed
            |> String.trim_leading("signal:")
            |> String.trim()
            |> String.split()
            |> List.first()
            |> String.to_integer()

          # Create peer if we have both MAC and signal
          peer =
            if current_mac && signal do
              %{
                mac_address: current_mac,
                signal_strength: signal,
                last_seen: System.system_time(:millisecond)
              }
            end

          new_peers = if peer, do: [peer | peers], else: peers
          {new_peers, nil, nil}

        true ->
          {peers, current_mac, current_signal}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # System Dependency Checks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Checks if required system commands are available.

  ## Returns
  - `{:ok, :all_available}` - All required commands found
  - `{:error, missing_commands}` - List of missing commands with installation instructions

  ## Example

      iex> AiReality2Transnet.Wifi.check_dependencies()
      {:ok, :all_available}

      # Or if commands are missing:
      {:error, [
        %{command: "iw", install: "sudo apt install iw"},
        %{command: "ip", install: "sudo apt install iproute2"}
      ]}
  """
  @spec check_dependencies() :: {:ok, :all_available} | {:error, list(map())}
  def check_dependencies do
    required_commands = [
      %{
        command: "iw",
        debian: "sudo apt install iw",
        fedora: "sudo dnf install iw",
        arch: "sudo pacman -S iw"
      },
      %{
        command: "ip",
        debian: "sudo apt install iproute2",
        fedora: "sudo dnf install iproute2",
        arch: "sudo pacman -S iproute2"
      }
    ]

    missing =
      Enum.filter(required_commands, fn %{command: cmd} ->
        case System.cmd("which", [cmd], stderr_to_stdout: true) do
          {_output, 0} -> false
          _ -> true
        end
      end)

    case missing do
      [] -> {:ok, :all_available}
      commands -> {:error, commands}
    end
  end
end
