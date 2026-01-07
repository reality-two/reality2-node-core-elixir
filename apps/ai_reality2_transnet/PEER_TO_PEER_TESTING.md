# Peer-to-Peer GATT Mesh Testing Guide

This guide explains how to test the peer-to-peer BLE mesh networking where each Reality2 node acts as both a GATT server and client.

## Architecture Overview

Each Reality2 node:
- **Broadcasts** its presence via BLE beacon (ALTBeacon format with company ID 0xFFFF)
- **Discovers** nearby R2 nodes automatically
- **Connects** as a GATT client when a peer is discovered
- **Reads** the peer's sentants via the Query characteristic
- **Stores** peer information in `connected_peers` state
- **Sends mutations** to peer sentants via the Data characteristic
- **Receives signals** from peers via PubSub (same as GraphQL)

## Flow Diagram

```
Device A                                    Device B
   │                                           │
   │◄──────── Beacon Discovery ───────────────►│
   │                                           │
   │  {:r2node_found, B_id, %{address: ...}}  │
   │                                           │  {:r2node_found, A_id, %{address: ...}}
   │                                           │
   │──── GATT Connect ─────────────────────────►│
   │◄─── GATT Connect ──────────────────────────│
   │                                           │
   │──── Read Query Char (sentantAll) ─────────►│
   │◄─── Sentants JSON ─────────────────────────│
   │                                           │
   │◄─── Read Query Char (sentantAll) ──────────│
   │──── Sentants JSON ────────────────────────►│
   │                                           │
   │  Store B's sentants                       │  Store A's sentants
   │  in connected_peers                       │  in connected_peers
   │                                           │
   │──── Write Data Char (mutation) ───────────►│
   │◄─── Notification (response) ───────────────│
   │                                           │
```

## Test Setup with Two Devices

### Prerequisites

Both devices must:
- Have BLE capability (Bluetooth 4.0+)
- Be running the Reality2 node software
- Be within BLE range (~10-30 meters depending on environment)

---

## Test Scenario 1: Automatic Peer Discovery and Connection

### **Device 1 Setup:**

```bash
cd /path/to/reality2-node-core-elixir
./run
```

In the IEx console:

```elixir
# Create a test sentant
sentant_yaml = """
name: device1_sensor
events:
  - name: read_temperature
  - name: read_humidity
automations:
  - name: respond_to_temp_request
    on: read_temperature
    do:
      - signal:
          event: temperature_data
          parameters:
            celsius: 25.5
            fahrenheit: 77.9
"""

Reality2.Sentants.create(sentant_yaml)

# Get your node ID
node_id = Reality2.Bootstrap.get(:node_id)
IO.puts("Device 1 Node ID: #{node_id}")

# Check GATT server status
AiReality2Transnet.BluetoothTest.check_state()
```

### **Device 2 Setup:**

```bash
cd /path/to/reality2-node-core-elixir
./run
```

In the IEx console:

```elixir
# Create a different sentant
sentant_yaml = """
name: device2_actuator
events:
  - name: turn_on
  - name: turn_off
automations:
  - name: respond_to_on
    on: turn_on
    do:
      - signal:
          event: status_changed
          parameters:
            state: on
"""

Reality2.Sentants.create(sentant_yaml)

# Get your node ID
node_id = Reality2.Bootstrap.get(:node_id)
IO.puts("Device 2 Node ID: #{node_id}")
```

### **Observe Automatic Connection:**

On **both devices**, watch the logs. You should see:

```
[info] R2 Node discovered: <peer-node-id>
[info] Successfully connected to peer <peer-node-id>, discovered X sentants
[info] GATT Sentant Server is ready and discoverable
```

### **Verify Connection (on Device 2):**

```elixir
# List all connected peers
AiReality2Transnet.BluetoothTest.list_connected_peers()

# You should see Device 1 with its sentants listed!
```

---

## Test Scenario 2: Send Mutation to Peer Sentant

Once devices are connected (see Test Scenario 1):

### **On Device 2:**

```elixir
# Get the peer info
{:ok, peers} = AiReality2Transnet.BluetoothTest.list_connected_peers()

# Get Device 1's node ID and first sentant ID
{device1_node_id, device1_info} = Enum.at(Map.to_list(peers), 0)
device1_sentant = Enum.at(device1_info.sentants, 0)
device1_sentant_id = Map.get(device1_sentant, "id")

# Send a mutation to Device 1's sentant
AiReality2Transnet.BluetoothTest.send_to_peer(
  device1_node_id,
  device1_sentant_id,
  "read_temperature",
  %{unit: "celsius"}
)
```

### **On Device 1:**

Watch the logs - you should see:

```
[info] Processing sentantSend: id=<sentant-id>, event=read_temperature
[info] Sentant signal received: <sentant-id> - temperature_data
```

The signal will be broadcast to:
- Device 2 (via BLE notification)
- Any GraphQL subscriptions (via PubSub)

---

## Test Scenario 3: Automated Full Test

### **On Either Device:**

```elixir
# Run the comprehensive peer-to-peer test
AiReality2Transnet.BluetoothTest.test_peer_to_peer()
```

This will:
1. Discover nearby R2 nodes
2. Wait for auto-connection
3. List connected peers and their sentants
4. Automatically send a test mutation to the first peer's first sentant

---

## Test Scenario 4: Peer Disconnection

### **On Device 1:**

```elixir
# Stop the Bluetooth service
GenServer.stop(AiReality2Transnet.Bluetooth)
```

### **On Device 2:**

Wait ~30 seconds (the `lost_after_ms` timeout), then check logs:

```
[info] R2 Node lost: <device1-node-id>
```

Verify peer was removed:

```elixir
AiReality2Transnet.BluetoothTest.list_connected_peers()
# Device 1 should no longer be in the list
```

---

## Manual API Testing

### Get Connected Peers

```elixir
peers = AiReality2Transnet.Bluetooth.get_connected_peers()
# Returns: %{node_id => %{address, sentants, connected_at, ...}}
```

### Get Specific Peer Info

```elixir
{:ok, peer_info} = AiReality2Transnet.Bluetooth.get_peer(peer_node_id)
# Returns detailed info about a specific peer
```

### Send Mutation to Peer

```elixir
AiReality2Transnet.Bluetooth.send_to_peer_sentant(
  peer_node_id,
  sentant_id,
  event_name,
  parameters,
  passthrough
)
```

---

## Monitoring and Debugging

### Check Bluetooth State

```elixir
state = AiReality2Transnet.Bluetooth.get_state()
IO.inspect(state.connected_peers, label: "Connected Peers")
```

### Monitor Messages

```elixir
# Trace Bluetooth messages for 10 seconds
AiReality2Transnet.BluetoothTest.monitor_messages(10_000)
```

### Check Node Discovery

```elixir
# Manually trigger node discovery
AiReality2Transnet.BluetoothTest.test_node_discovery()
```

---

## Expected Behavior

### Successful Connection

✅ Peer discovered via beacon
✅ Automatic GATT client connection
✅ Peer's sentants read and cached
✅ `connected_peers` map updated
✅ Sentants notified via `__internal` event

### Successful Mutation

✅ Mutation sent to peer's Data characteristic
✅ Peer validates and processes mutation
✅ Response received via notification
✅ Signal broadcast to all subscribers (BLE + GraphQL)

### Disconnection

✅ Peer timeout detected after ~30s
✅ Peer removed from `connected_peers`
✅ Sentants notified via `__internal` event

---

## Troubleshooting

### "Peer not connecting"

- Check both devices are broadcasting beacons
- Verify BLE range (try moving devices closer)
- Check logs for connection errors
- Ensure both devices have sentants created

### "Failed to read peer sentants"

- Verify GATT server is running on peer: `AiReality2Transnet.BluetoothTest.check_state()`
- Check the query characteristic is accessible
- Look for Rust NIF errors in logs

### "Mutation not received"

- Verify peer is in `connected_peers`: `AiReality2Transnet.Bluetooth.get_connected_peers()`
- Check the sentant ID is correct
- Verify the event name is in the peer sentant's events list
- Look for validation errors in peer logs

---

## Architecture Notes

### State Management

Each node maintains:

```elixir
%{
  adapter_name: "hci0",
  gatt_handle: #ResourceArc<...>,
  r2_beacon: #ResourceArc<...>,
  r2_watch: #ResourceArc<...>,
  events_sent: 0,
  signals_broadcast: 0,
  queries_processed: 0,
  connected_peers: %{
    "peer-node-uuid" => %{
      address: "AA:BB:CC:DD:EE:FF",
      node_id: "peer-node-uuid",
      sentants: [...],
      sentant_count: 3,
      connected_at: ~U[2025-01-08 12:00:00Z]
    }
  }
}
```

### PubSub Integration

Signals from peer sentants flow through the same PubSub system as local sentants:

```
Peer Sentant Signal
      ↓
Reality2.Sentants.sendto()
      ↓
Reality2Web.SentantResolver.send_signal()
      ↓
Phoenix.PubSub.broadcast(Reality2.PubSub, "sentant:signals")
      ↓
    ┌─────────┴─────────┐
    ↓                   ↓
GraphQL Subscribers   GATT Clients
    ↓                   ↓
WebSocket          BLE Notification
```

This means GraphQL clients and BLE clients both receive the same signals in real-time!

---

## Next Steps

After successful peer-to-peer testing, you can:

1. Implement **mesh routing** - forward messages through multiple hops
2. Add **discovery caching** - remember known peers
3. Implement **connection pooling** - maintain persistent connections
4. Add **encryption** - secure BLE communications
5. Create **pathing plugin integration** - route signals through the mesh

The foundation is now in place for a true peer-to-peer BLE mesh network mirroring GraphQL's architecture!
