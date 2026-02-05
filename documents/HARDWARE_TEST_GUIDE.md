# Hardware Integration Test Guide

Step-by-step instructions for testing Reality2 Transient Networks across physical devices.

## 1. Prerequisites

### Hardware
- **Laptop** — development machine running the Reality2 node
- **SBC1** — single-board computer (Raspberry Pi, etc.) with BLE and WiFi
- **SBC2** — second SBC for multi-peer mesh testing
- **Unihiker** — DFRobot Unihiker or similar device (Phase 3)
- **LoRa module** — USB LoRa transceiver at `/dev/ttyACM*` (Phase 4)

### Software (all devices)
- Elixir 1.17+ / Erlang/OTP 26+
- Git
- Python 3 (for `check_node.sh` JSON parsing)
- OpenSSL (for self-signed certificate generation)

### Network
- All SBCs within BLE range of the laptop (~10m)
- WiFi hotspot capability on at least one device
- Devices will form a WiFi cell automatically after BLE discovery

## 2. Device Setup

### Clone the repository (each device)

```bash
git clone <repo-url> reality2-node-core-elixir
cd reality2-node-core-elixir
mix deps.get
```

### Start a node using the setup script

On **SBC1**:
```bash
scripts/hardware_test/setup_node.sh SBC1
```

On **SBC2**:
```bash
scripts/hardware_test/setup_node.sh SBC2
```

On **Unihiker**:
```bash
scripts/hardware_test/setup_node.sh Unihiker
```

The setup script:
- Sets `R2_NODE_NAME` to the provided name
- Copies `autostart/hardware_test/*.bee.yaml` into `autostart/`
- Creates `.mnesia/$MIX_ENV` directory
- Starts `iex -S mix phx.server`

### Start the laptop node

```bash
scripts/run_as_dev
```

Or, to include hardware test sentants on the laptop:
```bash
cp autostart/hardware_test/*.bee.yaml autostart/
scripts/run_as_dev
```

## 3. Running Tests

### Check a node is ready

```bash
scripts/hardware_test/check_node.sh 192.168.4.2
```

Expected output:
```
=== Checking Reality2 node at 192.168.4.2 ===

--- /transnet/info ---
  Node Name:    SBC1
  Node ID:      a1b2c3d4-...
  Bluetooth:    active
  WiFi:         connected
  Sentants:     5

--- /mesh/sentants ---
  Sentant count: 5
    - PingPong
    - Counter
    - Transnet Test
    ...

=== Node at 192.168.4.2 is READY ===
```

### Run hardware tests

**List available phases:**
```bash
mix r2.hardware_test --list
```

**Run all phases:**
```bash
mix r2.hardware_test --verbose
```

**Run a specific phase:**
```bash
mix r2.hardware_test --phase 1 --verbose
```

### Environment variables

Override default IPs if your network differs:

```bash
export R2_SBC1_IP=192.168.4.2
export R2_SBC2_IP=192.168.4.3
export R2_UNIHIKER_IP=192.168.4.4
export R2_CLOUD_URL=https://cloud.example.com:4005
```

## 4. Phase-by-Phase Instructions

### Phase 1: Laptop + 1 SBC

**Setup:**
1. Start the laptop node (`scripts/run_as_dev`)
2. Start SBC1 (`scripts/hardware_test/setup_node.sh SBC1`)
3. Wait for BLE discovery (LED/log shows peer found)
4. Verify: `scripts/hardware_test/check_node.sh 192.168.4.2`

**Run:**
```bash
mix r2.hardware_test --phase 1 --verbose
```

**Tests (8):**
1. Local `/transnet/info` returns valid JSON
2. SBC1 `/transnet/info` reachable
3. BLE discovery: PeerManager has >= 1 peer (polls for 30s)
4. WiFi cell: peer has `wifi_hotspot` transport (polls for 60s)
5. Sentant exchange: peer has non-empty sentants (polls for 30s)
6. TrustGroupDirectory has >= 2 nodes
7. Local PingPong responds to ping
8. Cross-node PingPong: send via PNS to `"SBC1|PingPong"`

### Phase 2: + SBC2

**Setup:**
1. Keep Phase 1 devices running
2. Start SBC2 (`scripts/hardware_test/setup_node.sh SBC2`)
3. Verify: `scripts/hardware_test/check_node.sh 192.168.4.3`

**Run:**
```bash
mix r2.hardware_test --phase 2 --verbose
```

**Tests (6):**
1. SBC2 reachable
2. >= 2 peers in PeerManager (polls for 30s)
3. >= 3 nodes in TrustGroupDirectory
4. Send to SBC2 PingPong via PNS
5. MeshRouter relay count > 0
6. PeerManager stats show >= 2 current peers

### Phase 3: + Unihiker

**Setup:**
1. Keep Phases 1-2 devices running
2. Start Unihiker (`scripts/hardware_test/setup_node.sh Unihiker`)
3. Verify: `scripts/hardware_test/check_node.sh 192.168.4.4`

**Run:**
```bash
mix r2.hardware_test --phase 3 --verbose
```

**Tests (4):**
1. Unihiker reachable
2. 4 nodes in TrustGroupDirectory
3. Broadcast `"*"` event delivered to all nodes
4. Hive addressing resolves PingPong across multiple nodes

### Phase 4: LoRa Transport

**Setup:**
1. Connect LoRa USB module to laptop
2. Ensure `/dev/ttyACM*` device appears
3. At least one remote node also has LoRa

**Run:**
```bash
mix r2.hardware_test --phase 4 --verbose
```

**Tests (4):**
1. LoRa serial device exists at `/dev/ttyACM*`
2. LoRa peer in PeerManager with confidence > 0
3. Small event delivered via LoRa
4. MeshRouter `transport_sends` shows LoRa activity

### Phase 5: Cloud Connectivity

**Setup:**
1. Deploy a Reality2 node to a cloud server
2. Set the URL: `export R2_CLOUD_URL=https://cloud.example.com:4005`

**Run:**
```bash
R2_CLOUD_URL=https://cloud.example.com:4005 mix r2.hardware_test --phase 5 --verbose
```

**Tests (3):**
1. Cloud node reachable via HTTP
2. Cloud peer with internet confidence >= 200
3. Signal delivered to cloud PingPong sentant

## 5. IEx Exploration

For manual debugging, use these commands in the IEx shell:

### Peer Management
```elixir
# List all discovered peers
Reality2Transnet.PeerManager.get_all_peers()

# Get peer manager stats
Reality2Transnet.PeerManager.get_stats()

# Get a specific peer by name
Reality2Transnet.PeerManager.get_peer_by_name("SBC1")
```

### Trust Group Directory
```elixir
# View the full directory
Reality2Transnet.TrustGroupDirectory.get_directory()

# Find a sentant across all nodes
Reality2Transnet.TrustGroupDirectory.find_sentant_by_name("PingPong")

# Get best transport to reach a node
Reality2Transnet.TrustGroupDirectory.best_transport_for(node_id)
```

### Mesh Router
```elixir
# View router stats
Reality2Transnet.MeshRouter.get_stats()

# List available transports
Reality2Transnet.MeshRouter.list_transports()

# Send a signal through the mesh
Reality2Transnet.MeshRouter.send_signal("source_id", "target_id", "ping", %{})
```

### PNS Routing
```elixir
# Send to a local sentant
AiReality2Pns.Router.send_to_sentant("PingPong", "ping", %{})

# Send to a remote sentant
AiReality2Pns.Router.send_to_sentant("SBC1|PingPong", "ping", %{})

# Broadcast to all nodes
AiReality2Pns.Router.send_to_sentant("*", "ping", %{})

# Locate a sentant across the network
AiReality2Pns.Router.locate("*|PingPong")

# View the routing table
AiReality2Pns.Router.get_routing_table()
```

### Node Info
```elixir
# Get local node identity
Reality2.Bootstrap.get(:node_id)
Reality2.Bootstrap.get(:node_name)
```

## 6. Troubleshooting

### BLE Not Discovering Peers

- Verify BLE adapter is present: `hciconfig` or `bluetoothctl show`
- Check BLE is enabled in plugins: `PLUGINS` env var includes `reality2.transnet`
- Ensure devices are within range (~10m line of sight)
- Check logs for `[Bluetooth]` or `[PeerManager]` messages
- Restart BLE scanning:
  ```elixir
  # In IEx on either node
  AiReality2Pns.Router.send_to_sentant("Transnet Test", "Rescan", %{})
  ```

### WiFi Cell Not Forming

- Check WiFi hotspot capability: `nmcli device wifi list`
- Verify hosting priority in BLE beacon (higher priority = host)
- Check logs for `[ConnectionAssessor]` and `[ConnectionManager]` messages
- WiFi upgrade can take 30-60s after BLE discovery

### LoRa Not Working

- Verify serial device: `ls /dev/ttyACM*`
- Check permissions: `sudo usermod -a -G dialout $USER`
- Verify baud rate matches LoRa module configuration
- Check logs for `[LoRaMesh]` or `[LoRaTransport]` messages
- LoRa has limited bandwidth; keep payloads small (< 256 bytes)

### Cross-Node Events Not Delivered

- Verify both nodes are in the same trust group: check `TrustGroupDirectory.get_directory()`
- Check PNS routing table: `AiReality2Pns.Router.get_routing_table()`
- Ensure sentant names match exactly (case-sensitive)
- Check MeshRouter stats for send/receive counts
- Verify the target sentant exists: `AiReality2Pns.Router.locate("NodeName|SentantName")`

### Node Not Starting

- Check Mnesia directory exists: `ls .mnesia/dev/`
- Verify SSL certificates: `ls apps/reality2_web/priv/cert/`
- Check port 4005 is free: `lsof -i :4005`
- Review full logs: `MIX_ENV=dev iex -S mix phx.server 2>&1 | tee node.log`
