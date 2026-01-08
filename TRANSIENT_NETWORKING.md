# Reality2 Transient Networking

**Spontaneous, self-organizing peer-to-peer networks for wearable Reality2 devices**

## Overview

Transient Networking enables small wearable devices running Reality2 to automatically discover each other, exchange Sentant information, and communicate seamlessly - all without user interaction.

### Key Features

- **Zero-configuration discovery** via BLE AltBeacon
- **Automatic Sentant exchange** via GATT protocol
- **Location-transparent routing** with PNS (Pathing Name System)
- **Intelligent transport upgrade** from BLE to WiFi mesh when beneficial
- **Self-healing networks** with automatic peer timeout and cleanup

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Transient Network                        │
│                                                             │
│  Device 1               Device 2             Device 3       │
│  ┌──────────┐         ┌──────────┐        ┌──────────┐      │
│  │Reality2  │◄──BLE──►│Reality2  │◄──BLE──►│Reality2 │     │
│  │  Node    │         │  Node    │         │  Node    │     │
│  │          │         │          │         │          │     │
│  │Sentants: │         │Sentants: │         │Sentants: │     │
│  │- sensor1 │         │- display │         │- alert   │     │
│  │- health  │         │- ui      │         │- notify  │     │
│  └────┬─────┘         └────┬─────┘         └────┬─────┘     │
│       │                    │                    │           │
│       └────WiFi Mesh───────┴────────────────────┘           │
│            (automatic upgrade)                              │
└─────────────────────────────────────────────────────────────┘
```

### Layers

1. **Discovery Layer** - BLE AltBeacon broadcasting and scanning
2. **Exchange Layer** - GATT protocol for Sentant directory sharing
3. **Routing Layer** - PNS Router for location-transparent messaging
4. **Transport Layer** - Intelligent BLE/WiFi selection

## Components

### 1. GATT Protocol (`AiReality2Transnet.GattProtocol`)

Defines the GATT service and characteristics for Sentant exchange:

**Service UUID:** `00001234-0000-1000-8000-00805f9b34fb`

**Characteristics:**
- `Sentant Directory` (Read, Notify) - Lists all Sentants on this node
- `Sentant Command` (Write) - Send events to remote Sentants
- `Node Info` (Read) - Node capabilities and metadata

**Message Format:** JSON

```elixir
# Sentant Directory
%{
  "node_id" => "uuid",
  "sentants" => [
    %{"id" => "uuid", "name" => "sensor1", "events" => ["read", "calibrate"]}
  ]
}

# Sentant Command
%{
  "sentant_id" => "uuid",
  "event" => "read_temperature",
  "parameters" => %{"unit" => "celsius"}
}
```

### 2. Peer Manager (`AiReality2Transnet.PeerManager`)

Tracks discovered peers and their state:

```elixir
# Register a discovered peer
PeerManager.register_peer(node_id, %{address: "AA:BB:CC:DD:EE:FF", rssi: -55})

# Update peer's Sentants after GATT exchange
PeerManager.update_peer_sentants(node_id, sentants)

# Get all tracked peers
PeerManager.get_all_peers()

# Get statistics
PeerManager.get_stats()
```

**Peer State:**
- Node ID (UUID)
- Transport (`:ble_gatt` | `:wifi_mesh`)
- Available Sentants
- Connection info (address, RSSI)
- Capabilities (WiFi support, etc.)
- Last seen timestamp

### 3. Transport Manager (`AiReality2Transnet.TransportManager`)

Decides when to upgrade from BLE to WiFi mesh:

**Upgrade Criteria:**
- Data volume > 10 KB/sec
- Number of peers > 3
- Poor BLE signal (RSSI < -70 dBm)
- Explicit request

```elixir
# Check if upgrade is recommended
TransportManager.should_upgrade_to_wifi?(peer_id)
#=> {:yes, "high_data_volume"} | {:no, "criteria_not_met"}

# Initiate WiFi mesh upgrade
TransportManager.initiate_wifi_upgrade(peer_id, mesh_id)

# Record data transfer for throughput tracking
TransportManager.record_data_transfer(peer_id, bytes)
```

### 4. WiFi Module (`AiReality2Transnet.Wifi`)

Pure Elixir implementation for WiFi mesh management:

```elixir
# List WiFi adapters
Wifi.list_adapters()
#=> {:ok, [%{interface: "wlan0", address: "AA:BB:CC:DD:EE:FF", ...}]}

# Create mesh interface
Wifi.create_mesh_interface("wlan0", "mesh0")

# Start mesh network
Wifi.start_mesh("mesh0", "REALITY2_MESH", 2437)

# List mesh peers
Wifi.list_mesh_peers("mesh0")
#=> {:ok, [%{mac_address: "...", signal_strength: -45, ...}]}

# Get IPv6 link-local address
Wifi.get_ipv6_link_local("mesh0")
#=> {:ok, "fe80::1234:5678:9abc:def0"}
```

### 5. PNS Router (`AiReality2Pns.Router`)

Location-transparent routing for Sentant events:

```elixir
# Send to any Sentant (local or remote)
AiReality2Pns.send_to(sentant_id, "read_temperature", %{unit: "celsius"})
#=> {:ok, :local} | {:ok, {:remote, node_id}}

# Broadcast to all Sentants matching pattern
AiReality2Pns.broadcast("sensor_*", "calibrate", %{})

# Locate a Sentant
AiReality2Pns.Router.locate(sentant_id)
#=> {:ok, :local} | {:ok, {:remote, node_id}} | {:error, :not_found}

# Get routing table
AiReality2Pns.Router.get_routing_table()
```

## Flow: Device-to-Device Communication

### Step 1: Discovery
```elixir
# Device 1 starts broadcasting
AiReality2Transnet.Bluetooth.start_beacon(node_uuid, sentant_count, ...)

# Device 2 discovers Device 1
# -> receives {:r2node_found, device1_id, info}

# PeerManager automatically registers the peer
PeerManager.register_peer(device1_id, info)
```

### Step 2: GATT Exchange
```elixir
# Device 2 connects to Device 1 via GATT
AiReality2Transnet.Bluetooth.connect_to_peer(device1_id)

# Read Sentant directory from Device 1
directory_json = GattProtocol.handle_sentant_directory_read(device1_id)
{:ok, %{sentants: sentants}} = GattProtocol.decode_sentant_directory(directory_json)

# Update PeerManager with Device 1's Sentants
PeerManager.update_peer_sentants(device1_id, sentants)

# PeerManager notifies PNS Router to refresh topology
AiReality2Pns.Router.refresh_topology()
```

### Step 3: Transparent Routing
```elixir
# Application wants to send to a Sentant (doesn't know where it is)
AiReality2Pns.send_to("sensor1", "read_temperature", %{})

# PNS Router:
# 1. Looks up "sensor1" in routing table
# 2. Finds it's on Device 1 (remote)
# 3. Encodes command via GattProtocol
# 4. Sends via BLE GATT to Device 1
# 5. Device 1 receives command and executes locally
```

### Step 4: WiFi Upgrade (Optional)
```elixir
# TransportManager detects high data volume
TransportManager.should_upgrade_to_wifi?(device1_id)
#=> {:yes, "high_data_volume"}

# Initiates WiFi mesh upgrade
TransportManager.initiate_wifi_upgrade(device1_id)

# Both devices:
# 1. Create mesh0 interface
# 2. Join R2MESH_<peer_id> network
# 3. Update PeerManager transport to :wifi_mesh
# 4. Future messages use WiFi instead of BLE
```

## Testing

### Integration Test Suite

```elixir
alias AiReality2Transnet.TransientNetworkTest, as: TNT

# Show system status
TNT.status()

# Simulate peer discovery
TNT.simulate_peer_discovery()

# Test GATT protocol
TNT.test_gatt_protocol()

# Test PNS routing
TNT.test_pns_routing()

# Test WiFi mesh upgrade
TNT.test_wifi_upgrade()

# Full integration test
TNT.run_integration_test()
```

### Manual Testing

```elixir
# Check PeerManager
AiReality2Transnet.PeerManager.get_all_peers()
AiReality2Transnet.PeerManager.get_stats()

# Check TransportManager
AiReality2Transnet.TransportManager.get_stats()

# Check PNS Router
AiReality2Pns.Router.get_routing_table()

# Check WiFi
AiReality2Transnet.Wifi.list_adapters()
```

## Deployment to Arduino Uno-Q

### Requirements

**System packages:**
```bash
sudo apt install bluez bluez-tools iw iproute2 wireless-tools dbus
sudo apt install erlang elixir
```

**Permissions:**
```bash
# Option 1: Run as root (testing)
sudo iex -S mix

# Option 2: Set capabilities (production)
sudo setcap cap_net_admin+epi /usr/bin/iw
sudo setcap cap_net_admin+epi /usr/bin/ip

# Option 3: Add user to netdev group
sudo usermod -aG netdev $USER
```

### Cross-Compilation

For ARM devices, ensure Rust cross-compilation is set up:

```bash
# Install ARM target
rustup target add armv7-unknown-linux-gnueabihf  # 32-bit
# OR
rustup target add aarch64-unknown-linux-gnu      # 64-bit

# Set target in Podman build
export CARGO_BUILD_TARGET=armv7-unknown-linux-gnueabihf
```

### Verification

```bash
# On Uno-Q device:
iw list | grep -A 10 "Supported interface modes" | grep mesh
# Should show "mesh point" if WiFi chip supports 802.11s
```

## Configuration

### Thresholds

Edit `transport_manager.ex` to adjust upgrade criteria:

```elixir
@data_volume_threshold_bytes_per_sec 10_000  # 10 KB/s
@peer_count_threshold 3
@rssi_quality_threshold -70  # dBm
@upgrade_check_interval_ms 10_000  # Check every 10 seconds
```

### Timeouts

Edit `peer_manager.ex`:

```elixir
@peer_timeout_ms 60_000  # Remove peers not seen for 60 seconds
@cleanup_interval_ms 30_000  # Check for stale peers every 30 seconds
```

## Performance Considerations

### BLE GATT
- **Throughput:** ~1 Mbps
- **Range:** 10-50m
- **Power:** Low
- **Best for:** Small messages, sensor data, control commands

### WiFi Mesh
- **Throughput:** 50+ Mbps
- **Range:** 50-100m+
- **Power:** Higher
- **Best for:** Large transfers, streaming, many peers

## Future Enhancements

### Phase 2
- [ ] HTTP-based WiFi mesh protocol (currently stub)
- [ ] GATT client write implementation for remote commands
- [ ] Automatic mesh ID coordination between peers
- [ ] Battery-aware transport decisions

### Phase 3
- [ ] Multi-hop mesh routing
- [ ] Sentant replication across devices
- [ ] Distributed consensus for shared state
- [ ] Encryption and authentication

## Troubleshooting

### WiFi mesh not creating

**Check:**
1. WiFi chip supports mesh mode: `iw list | grep "mesh point"`
2. Running with appropriate permissions
3. Interface not already in use
4. Driver supports cfg80211 (most modern drivers do)

### BLE peers not discovered

**Check:**
1. BlueZ running: `systemctl status bluetooth`
2. D-Bus accessible: `dbus-send --system --print-reply --dest=org.bluez /`
3. Adapter powered: `bluetoothctl power on`
4. Beacon UUID matches AltBeacon format

### PNS routing fails

**Check:**
1. PeerManager has peer registered: `PeerManager.get_all_peers()`
2. Peer has Sentants: Check `peer.sentants` list
3. PNS topology refreshed: `AiReality2Pns.Router.refresh_topology()`

## License

Copyright © 2026 Dr. Roy C. Davies
Part of the Reality2 framework

## Author

Dr. Roy C. Davies
[roycdavies.github.io](https://roycdavies.github.io/)
