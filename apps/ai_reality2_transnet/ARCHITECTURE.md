# Reality2 Transient Network Architecture

## Overview

Reality2 Transient Networks use a **multi-transport mesh architecture** with automatic transport selection:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Sentants / PNS Router                        │
│                 (transport agnostic routing)                    │
├─────────────────────────────────────────────────────────────────┤
│                     Transport Selection                         │
├──────────┬──────────┬──────────┬──────────┬────────────────────┤
│  R2Mesh  │   WiFi   │   LoRa   │  Thread  │      Matter        │
│  (BLE)   │  Hotspot │   Mesh   │   Mesh   │   (smart home)     │
│  ~10m    │  ~100m   │  ~15km   │  ~30m    │   device control   │
│ ✓ ready  │ ✓ ready  │ ✓ ready  │  future  │      future        │
└──────────┴──────────┴──────────┴──────────┴────────────────────┘
```

### Current Transports

1. **BLE Discovery + R2Mesh** - Low power, always on, small messages (~24 bytes)
2. **WiFi Hotspot** - High bandwidth, auto-created mesh via WPA2-PSK
3. **LoRa Mesh** (optional) - Long range (~15km), USB dongle, medium messages (~200 bytes)

### Future Transports

4. **BLE Mesh** - Requires BlueZ 5.47+, code ready, waiting for OS support
5. **WiFi Mesh (802.11s)** - Kernel-level mesh, for infrastructure deployments
6. **Thread/Matter** - Smart home integration (see Future Enhancements)

This architecture avoids the 512-byte GATT characteristic size limit while maintaining low-power discovery.

## Architecture

### Tier 1: BLE Discovery (Low Power, Always On)

BLE is used ONLY for:
- Broadcasting node presence via AltBeacon
- Exchanging minimal node info (node_id, capabilities, sentant_count)
- Sharing WiFi mesh connection details (IPv6 address, HTTP port)

**GATT Service: 00001234-0000-1000-8000-00805f9b34fb**

#### Characteristics:

1. **Node Info** (UUID: 00001237, Read)
   - Minimal node metadata
   - Sentant count (NOT full list)
   - Capabilities (bluetooth, wifi_mesh)
   - Message directing client to use WiFi mesh for queries

   Example:
   ```json
   {
     "node_id": "550e8400-e29b-41d4-a716-446655440000",
     "version": "0.1.13",
     "capabilities": {
       "bluetooth": true,
       "wifi_mesh": true,
       "sentant_count": 5
     },
     "message": "Use WiFi mesh HTTP for Sentant queries - see mesh_details"
   }
   ```

2. **WiFi Mesh Details** (UUID: 00001235, Read/Notify)
   - WiFi mesh connection information
   - IPv6 link-local address
   - HTTP server port
   - Instructions for HTTP queries

   Example:
   ```json
   {
     "mesh_active": true,
     "mesh_id": "R2MESH",
     "ipv6_link_local": "fe80::1234:5678:90ab:cdef",
     "http_port": 4005,
     "instructions": "Query sentants: GET http://[ipv6]:port/mesh/sentants"
   }
   ```

3. **Mesh Command** (UUID: 00001236, Write)
   - Send mesh coordination commands
   - Join/leave mesh network

   Example:
   ```json
   {
     "command": "join_mesh",
     "parameters": {
       "mesh_id": "R2MESH"
     }
   }
   ```

### Tier 2: WiFi Mesh HTTP (High Bandwidth)

WiFi mesh (IEEE 802.11s) is used for:
- Querying full Sentant lists (no size limits)
- Sending events to Sentants (via GraphQL)
- High-throughput data transfer
- Multi-hop routing between nodes

**HTTP endpoints are served by Reality2Web on port 4005**

#### HTTP Endpoints:

1. **GET /mesh/sentants** - Query all Sentants

   Response:
   ```json
   {
     "node_id": "550e8400-e29b-41d4-a716-446655440000",
     "sentant_count": 5,
     "sentants": [
       {
         "id": "sentant-uuid",
         "name": "temperature_sensor",
         "events": ["read", "calibrate"],
         "signals": ["temperature_changed"]
       }
     ]
   }
   ```

2. **POST /reality2** - Send event to Sentant via GraphQL

   Use the standard GraphQL `sentantSend` mutation to send events to Sentants.

3. **GET /mesh/info** - Query node info with mesh details

   Response:
   ```json
   {
     "node_id": "550e8400-e29b-41d4-a716-446655440000",
     "version": "0.1.13",
     "capabilities": { ... },
     "mesh_info": {
       "active": true,
       "mesh_id": "R2MESH",
       "ipv6_link_local": "fe80::1234:5678:90ab:cdef"
     }
   }
   ```

## Discovery Flow

```
1. Node A broadcasts BLE AltBeacon
   └─> Contains: Node UUID

2. Node B detects beacon
   └─> Reads GATT Node Info characteristic
   └─> Gets: node_id, capabilities, sentant_count

3. Node B reads GATT Mesh Details characteristic
   └─> Gets: ipv6_link_local, http_port

4. If WiFi available, Node B joins mesh
   └─> Writes to Mesh Command characteristic: "join_mesh"

5. Node B queries Sentants via WiFi HTTP
   └─> GET http://[fe80::...]:4005/mesh/sentants
   └─> Receives full Sentant list (no size limits)

6. Node B sends commands via WiFi HTTP (GraphQL)
   └─> POST http://[fe80::...]:4005/reality2
```

## Benefits

### Why This Architecture?

1. **Avoids GATT 512-byte limit**
   - BLE only carries minimal info
   - WiFi handles large data transfers

2. **Power efficiency**
   - BLE beacon is low power, always on
   - WiFi only used when needed

3. **Scalability**
   - WiFi mesh supports multiple hops
   - HTTP is well-understood, debuggable

4. **Flexibility**
   - Can query single Sentant or all
   - Can send complex commands without size limits
   - Can stream data if needed

5. **Fallback capability**
   - Works without WiFi (discovery still happens via BLE)
   - Graceful degradation

## Code Structure

### BLE Layer
- `AiReality2Transnet.Bluetooth` - BLE beacon, GATT server, discovery
- `AiReality2Transnet.GattProtocol` - GATT protocol for device-to-device
- `AiReality2Transnet.Action` - Rust NIFs for BlueZ integration
- `AiReality2Transnet.R2Mesh` - Simple BLE relay mesh (works on any BlueZ)
- `AiReality2Transnet.BLEMesh` - Full BLE Mesh (requires BlueZ 5.47+, future)

### WiFi Layer
- `AiReality2Transnet.Wifi` - WiFi hotspot/client operations via NetworkManager
- `AiReality2Transnet.ConnectionManager` - Hotspot creation, client connections
- `AiReality2Transnet.ConnectionAssessor` - Connection quality, handover decisions
- `Reality2Web.MeshController` - HTTP endpoints for mesh queries

### LoRa Layer (Optional)
- `AiReality2Transnet.LoRaMesh` - LoRa mesh via USB dongle (auto-detects hardware)

### Management Layer
- `AiReality2Transnet.PeerManager` - Track discovered peers across all transports
- `AiReality2Transnet.Main` - Sentant plugin interface

### Integration Layer
- `AiReality2Wfs.Router` - Location-transparent Sentant routing

## Testing

### BLE Discovery
```elixir
# Start watching for nodes
AiReality2Transnet.Bluetooth.get_state()

# When node found:
# {:r2node_found, "550e8400-...", %{address: "AA:BB:CC:DD:EE:FF", rssi: -45}}
```

### WiFi Mesh Queries
```elixir
# Query remote peer's sentants
peer_ipv6 = "fe80::1234:5678:90ab:cdef"
{:ok, sentants} = AiReality2Transnet.WifiServer.query_peer_sentants(peer_ipv6)

# Send command to remote sentant
{:ok, response} = AiReality2Transnet.WifiServer.send_to_peer(
  peer_ipv6,
  "sentant-uuid",
  "read",
  %{unit: "celsius"}
)
```

### Peer Management
```elixir
# Get all discovered peers
peers = AiReality2Transnet.PeerManager.get_all_peers()

# Get specific peer
{:ok, peer} = AiReality2Transnet.PeerManager.get_peer("node-uuid")

# Check transport
:wifi_mesh = AiReality2Transnet.PeerManager.get_transport("node-uuid")
```

## Deployment

### Requirements
- Linux with BlueZ stack
- iw and ip utilities for WiFi mesh
- Elixir 1.17+
- Rust toolchain for NIFs

### Configuration
```elixir
# config/config.exs
config :ai_reality2_transnet,
  wifi_server_port: 4005  # HTTP port (served by Reality2Web)
```

### ARM Cross-Compilation
For Arduino Uno-Q devices:
```bash
# Set Rust target
export RUSTFLAGS="-C target-cpu=native"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc

# Build
mix deps.get
mix compile
```

## Future Enhancements

### Near Term
1. **mDNS Discovery** - Use mDNS instead of/in addition to BLE beaconing
2. **WebSocket Subscriptions** - Stream Sentant signals over WebSocket
3. **Security Hardening** - TLS for HTTP, per-deployment PSK secrets
4. **Android Integration** - Update reality2-android-devtool to use new protocol

### Medium Term - Thread/Matter Integration

Thread and Matter would enable Sentants to interact with smart home devices.

#### Thread Mesh (802.15.4)
- **What**: Low-power IPv6 mesh network, same radio as Zigbee
- **Hardware**: ESP32-C6 (native), USB 802.15.4 dongle
- **Use case**: Sentant-to-Sentant over Thread mesh
- **Module**: `thread_mesh.ex` (same API as R2Mesh/LoRaMesh)

#### Matter Bridge
- **What**: Application layer for smart home interoperability
- **Integration**: Reality2 as Matter controller
- **Use cases**:
  - Light Sentant → controls Philips Hue/IKEA bulbs
  - Sensor events → trigger Sentant automations
  - Sentant signals → control locks, thermostats
- **Module**: `matter_bridge.ex`

#### Protocol Comparison

| Protocol | Frequency | Range | Power | Mesh | Best For |
|----------|-----------|-------|-------|------|----------|
| R2Mesh (BLE) | 2.4 GHz | ~10m | Very Low | Yes | Discovery, small msgs |
| WiFi | 2.4/5 GHz | ~100m | High | Hotspot | Bulk data, GraphQL |
| LoRa | Sub-GHz | ~15km | Low | Yes | Rural, outdoor |
| Thread | 2.4 GHz | ~30m | Very Low | Yes | Smart home mesh |
| Zigbee | 2.4 GHz | ~30m | Low | Yes | Legacy sensors |
| Z-Wave | 868/908 MHz | ~100m | Low | Yes | Reliable automation |
| Z-Wave LR | Sub-GHz | ~1km | Low | Yes | Large properties |

#### Implementation Approach
1. Add `thread_mesh.ex` following LoRaMesh pattern
2. Add `matter_bridge.ex` for device control
3. PNS Router selects transport based on message type/destination
4. Sentant definitions unchanged - transport is transparent

### Long Term
5. **WiFi Mesh (802.11s)** - Kernel-level mesh for infrastructure
6. **Signed Events** - Cryptographic verification of event sources
7. **Sentant Access Control** - Per-Sentant authorization policies

## References

### Current Implementation
- [IEEE 802.11s WiFi Mesh](https://en.wikipedia.org/wiki/IEEE_802.11s)
- [AltBeacon Specification](https://github.com/AltBeacon/spec)
- [BlueZ Bluetooth Stack](http://www.bluez.org/)
- [Rustler NIFs](https://github.com/rusterlium/rustler)

### LoRa
- [LoRa Alliance](https://lora-alliance.org/)
- [Meshtastic](https://meshtastic.org/) - Open source LoRa mesh
- [Circuits.UART](https://hexdocs.pm/circuits_uart/) - Elixir serial communication

### Thread/Matter (Future)
- [Thread Group](https://www.threadgroup.org/)
- [Matter (CSA)](https://csa-iot.org/all-solutions/matter/)
- [OpenThread](https://openthread.io/) - Open source Thread implementation
- [Matter SDK](https://github.com/project-chip/connectedhomeip)

### Smart Home Protocols
- [Zigbee Alliance](https://zigbeealliance.org/)
- [Z-Wave Alliance](https://z-wavealliance.org/)
