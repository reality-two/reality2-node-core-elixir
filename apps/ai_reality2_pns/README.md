# Reality2 Pathing Name System (PNS)

Location-transparent routing for Sentant digital agents across Reality2 nodes.

## Overview

The **Pathing Name System (PNS)** is a higher-level abstraction that allows Sentants to send events to other Sentants without knowing their physical location or connection type. Whether a Sentant is local, on a peer node via GATT Bluetooth, or on a remote server via GraphQL - the PNS handles routing automatically.

## Architecture

```
Sentant Automation
      ↓
   send action
      ↓
PNS Router (Location Resolver)
      ↓
   ┌──────────┴──────────┐
   ↓                     ↓
Local Sentant       Remote Sentant
   ↓                     ↓
Reality2.Sentants    ┌───┴────┐
                     ↓        ↓
                   GATT   GraphQL
                 (BLE)     (HTTP/WS)
```

## Features

### ✅ Location-Transparent Routing
- Send to any Sentant without knowing where it is
- Automatic route selection (local, GATT, GraphQL)
- Fallback mechanisms for reliability

### ✅ Topology Management
- Maintains cache of Sentant locations
- Subscribes to peer discovery events
- Auto-updates when peers connect/disconnect
- Manual refresh available

### ✅ Broadcasting
- Send to all Sentants with `"*"`
- Wildcard patterns: `"device_*"`, `"*_sensor"`
- Explicit lists of IDs or names
- Counts local and remote deliveries

### ✅ Integration
- Seamless integration with automation `send` action
- Works with existing Sentant code
- Backwards compatible (falls back to direct send)

## Installation

The PNS app is automatically loaded when included in the `PLUGINS` environment variable:

```bash
export PLUGINS="ai.reality2.pns, ..."
```

It's already added to `scripts/run_as_dev`.

## Usage

### Basic Sending

```elixir
# Send by ID (automatically routes)
AiReality2Pns.send_to(sentant_id, "event_name", %{param: "value"})

# Send by name
AiReality2Pns.send_to("device1_sensor", "read_temperature")

# With passthrough data
AiReality2Pns.send_to(sentant_id, "ping", %{}, %{source: "test"})
```

### Broadcasting

```elixir
# Broadcast to all Sentants
AiReality2Pns.broadcast("*", "sync")

# Pattern matching
AiReality2Pns.broadcast("sensor_*", "calibrate")

# Specific list
AiReality2Pns.broadcast([id1, id2, id3], "update")
```

### Location Discovery

```elixir
case AiReality2Pns.locate(sentant_id) do
  {:ok, :local} ->
    IO.puts("Sentant is on this node")

  {:ok, {:remote, node_id}} ->
    IO.puts("Sentant is on remote node: #{node_id}")

  {:error, :not_found} ->
    IO.puts("Sentant not found")
end
```

### Routing Table Inspection

```elixir
# Get routing table
table = AiReality2Pns.routing_table()

IO.inspect(table.stats)
#=> %{
#     local_sends: 42,
#     remote_sends: 15,
#     broadcasts: 3,
#     cache_hits: 50,
#     cache_misses: 7
#   }

# Refresh topology cache
AiReality2Pns.refresh()
```

## Automation Integration

The PNS is **automatically used** when you use the `send` action in Sentant automations:

```yaml
automations:
  - name: communicate
    on: trigger
    do:
      - send:
          to: other_sentant  # Can be local OR remote!
          event: hello
          parameters:
            message: "Hi from PNS!"
```

The automation code now routes through PNS automatically:
- If `other_sentant` is local → uses `Reality2.Sentants.sendto()`
- If `other_sentant` is remote → uses `AiReality2Transnet.Bluetooth.send_to_peer_sentant()`
- Fallback to direct send if PNS fails

### Sending to Remote Sentants in YAML

```yaml
automations:
  - name: cross_node_communication
    on: button_pressed
    do:
      - send:
          to: "remote_device_id"  # UUID of Sentant on peer node
          event: turn_on
          parameters:
            brightness: 100
```

## Testing

### Show Routing Table

```elixir
AiReality2Pns.Test.show_routing_table()
```

Output:
```
===========================================
PNS Routing Table
===========================================
Local Sentants: 5
Remote Sentants: 12

Statistics:
- Local sends: 42
- Remote sends: 15
- Broadcasts: 3

Sentant Locations:
  a1b2c3d4... => LOCAL
  e5f6g7h8... => REMOTE (i9j0k1l2...)
  ...
===========================================
```

### Test Local Send

```elixir
AiReality2Pns.Test.test_local_send()
```

Creates a test Sentant, locates it, and sends an event through PNS.

### Test Remote Send

```elixir
# Get a peer and one of its Sentants
peers = AiReality2Transnet.Bluetooth.get_connected_peers()
{peer_id, peer_info} = Enum.at(Map.to_list(peers), 0)
sentant = Enum.at(peer_info.sentants, 0)
sentant_id = Map.get(sentant, "id")

# Test sending via PNS
AiReality2Pns.Test.test_remote_send(peer_id, sentant_id)
```

### Full Integration Test

```elixir
AiReality2Pns.Test.test_integration()
```

Runs all tests: local send, remote send, broadcast, and displays statistics.

### Quick Test

```elixir
AiReality2Pns.Test.quick_test()
```

Creates two local Sentants and demonstrates PNS routing between them.

## How It Works

### 1. Topology Cache

The PNS maintains a cache of Sentant locations:

```elixir
%{
  sentant_locations: %{
    "sentant-uuid-1" => :local,
    "sentant-uuid-2" => {:remote, "node-id-a"},
    "sentant-uuid-3" => {:remote, "node-id-b"},
    ...
  },
  peer_sentants: %{
    "node-id-a" => ["sentant-uuid-2", "sentant-uuid-5"],
    "node-id-b" => ["sentant-uuid-3", "sentant-uuid-6"],
    ...
  }
}
```

### 2. Location Resolution

When you send to a Sentant:

1. **Check cache** - Is location known?
   - If local → send directly
   - If remote → route via GATT/GraphQL
   - If not found → try direct send + update cache

2. **Fallback** - If routing fails, try direct send

3. **Update** - Cache misses trigger topology refresh

### 3. Peer Discovery Integration

The PNS subscribes to PubSub events:

```elixir
# From ai_reality2_transnet
{:r2node_found, node_id, info}   # Add peer sentants to cache
{:r2node_lost, node_id}           # Remove peer sentants from cache
{:sentant_signal, signal_data}    # Future: track signal patterns
```

### 4. Transport Selection

The PNS automatically selects the best transport:

| Scenario | Transport | Implementation |
|----------|-----------|----------------|
| Local Sentant | Direct | `Reality2.Sentants.sendto()` |
| GATT Peer | Bluetooth | `AiReality2Transnet.Bluetooth.send_to_peer_sentant()` |
| GraphQL Node | HTTP/WebSocket | (Future) `GraphQLClient.mutation()` |
| Unknown | Fallback | Try local, then error |

## Configuration

No configuration needed! The PNS automatically:
- Starts with the application
- Subscribes to peer events
- Refreshes topology on init
- Integrates with automations

## Performance

### Caching Strategy
- **Cache Hit**: O(1) lookup in map
- **Cache Miss**: O(1) local check + topology refresh
- **Refresh**: O(N) where N = total Sentants

### Statistics Tracking
```elixir
%{
  local_sends: 0,      # Successful local routes
  remote_sends: 0,     # Successful remote routes
  broadcasts: 0,       # Broadcast operations
  cache_hits: 0,       # Found in cache
  cache_misses: 0      # Not in cache (triggered refresh)
}
```

## Future Enhancements

### 🚧 GraphQL Transport
Support for routing to GraphQL nodes:
```elixir
send_to_remote_graphql(node_url, sentant_id, event, params)
```

### 🚧 Multi-Hop Routing
Route through intermediate nodes:
```
Node A → Node B → Node C
```

### 🚧 Path Discovery
Dijkstra or A* for optimal routing:
```elixir
find_best_path(from_node, to_node) #=> [node1, node2, node3]
```

### 🚧 Load Balancing
Distribute broadcasts across multiple paths:
```elixir
broadcast_with_lb("*", event, params, strategy: :round_robin)
```

### 🚧 Retry Logic
Automatic retry with exponential backoff:
```elixir
send_with_retry(sentant_id, event, max_retries: 3, backoff: :exponential)
```

## Troubleshooting

### "Sentant not found"
```elixir
# Refresh topology cache
AiReality2Pns.refresh()

# Wait for peer discovery
Process.sleep(2000)

# Check if peers are connected
AiReality2Transnet.Bluetooth.get_connected_peers()
```

### "Routing failed"
```elixir
# Check routing table
AiReality2Pns.Test.show_routing_table()

# Try locating the Sentant
AiReality2Pns.locate(sentant_id)

# Check if transnet is loaded
Code.ensure_loaded?(AiReality2Transnet.Bluetooth)
```

### "Remote send not working"
```elixir
# Verify peer connection
AiReality2Transnet.BluetoothTest.list_connected_peers()

# Test GATT directly
AiReality2Transnet.BluetoothTest.test_peer_to_peer()

# Check PNS routing
AiReality2Pns.Test.test_remote_send(peer_id, sentant_id)
```

## API Reference

### Core Functions

#### `AiReality2Pns.send_to/4`
Send event to a Sentant (location-transparent).

#### `AiReality2Pns.broadcast/4`
Broadcast event to multiple Sentants.

#### `AiReality2Pns.locate/1`
Find where a Sentant is located.

#### `AiReality2Pns.routing_table/0`
Get current routing table and statistics.

#### `AiReality2Pns.refresh/0`
Force topology cache refresh.

### Test Functions

#### `AiReality2Pns.Test.show_routing_table/0`
Display formatted routing table.

#### `AiReality2Pns.Test.test_local_send/0`
Test sending to local Sentant.

#### `AiReality2Pns.Test.test_remote_send/2`
Test sending to remote Sentant.

#### `AiReality2Pns.Test.test_broadcast/1`
Test broadcasting with pattern.

#### `AiReality2Pns.Test.test_integration/0`
Run full integration test suite.

#### `AiReality2Pns.Test.quick_test/0`
Quick test with two local Sentants.

## Example Scenario

### Multi-Device Mesh

**Setup**: 3 devices with Reality2 nodes
- Device A: `sensor_temp`, `sensor_humidity`
- Device B: `actuator_fan`, `actuator_heater`
- Device C: `controller_hvac`

**Automation** (on Device C):
```yaml
name: controller_hvac
events:
  - name: temperature_check
automations:
  - name: regulate_temperature
    on: temperature_check
    do:
      # Read from Device A (via GATT)
      - send:
          to: sensor_temp
          event: read_value

      # Control Device B (via GATT)
      - test:
          condition: temperature > 25
          then:
            - send:
                to: actuator_fan
                event: turn_on
                parameters:
                  speed: high
```

**With PNS**, the controller doesn't need to know:
- Where `sensor_temp` is (Device A)
- How to reach it (GATT Bluetooth)
- The BLE address or connection details

The PNS handles **all routing automatically**! 🎯

## Integration with GraphQL

The PNS routing is **parallel** to GraphQL:

```
External Client              Internal Automation
      ↓                            ↓
   GraphQL                        PNS
(sentantSend mutation)    (send action in YAML)
      ↓                            ↓
      └──────→ Reality2.Sentants ←─┘
```

Both paths converge at the Sentant layer, and both receive signals via the same PubSub system.

## Summary

The Reality2 PNS provides:
- ✅ Location-transparent routing
- ✅ Automatic transport selection
- ✅ Mesh networking support
- ✅ Backwards compatibility
- ✅ Comprehensive testing tools
- ✅ Zero configuration needed

Send events to any Sentant, anywhere, without worrying about the details! 🚀
