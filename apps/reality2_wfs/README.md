# Reality2 Waggle Finding Service (WFS)

Location-transparent routing for Sentant digital agents across Reality2 nodes.

## Overview

The **Waggle Finding Service (WFS)** is a higher-level abstraction that allows Sentants to send events to other Sentants without knowing their physical location or connection type. Whether a Sentant is local, on a peer node via GATT Bluetooth, or on a remote server via GraphQL - the WFS handles routing automatically.

## Architecture

```
Sentant Automation
      ↓
   send action
      ↓
WFS Router (Location Resolver)
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

The WFS app is automatically loaded when included in the `PLUGINS` environment variable:

```bash
export PLUGINS="reality2.wfs, ..."
```

It's already added to `scripts/run_as_dev`.

## Usage

### Basic Sending

```elixir
# Send by ID (automatically routes)
Reality2Wfs.send_to(sentant_id, "event_name", %{param: "value"})

# Send by name
Reality2Wfs.send_to("device1_sensor", "read_temperature")

# With passthrough data
Reality2Wfs.send_to(sentant_id, "ping", %{}, %{source: "test"})
```

### Broadcasting

```elixir
# Broadcast to all Sentants
Reality2Wfs.broadcast("*", "sync")

# Pattern matching
Reality2Wfs.broadcast("sensor_*", "calibrate")

# Specific list
Reality2Wfs.broadcast([id1, id2, id3], "update")
```

### Location Discovery

```elixir
case Reality2Wfs.locate(sentant_id) do
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
table = Reality2Wfs.routing_table()

IO.inspect(table.stats)
#=> %{
#     local_sends: 42,
#     remote_sends: 15,
#     broadcasts: 3,
#     cache_hits: 50,
#     cache_misses: 7
#   }

# Refresh topology cache
Reality2Wfs.refresh()
```

## Automation Integration

The WFS is **automatically used** when you use the `send` action in Sentant automations:

```yaml
automations:
  - name: communicate
    on: trigger
    do:
      - send:
          to: other_sentant  # Can be local OR remote!
          event: hello
          parameters:
            message: "Hi from WFS!"
```

The automation code now routes through WFS automatically:
- If `other_sentant` is local → uses `Reality2.Sentants.sendto()`
- If `other_sentant` is remote → uses `Reality2Transnet.Bluetooth.send_to_peer_sentant()`
- Fallback to direct send if WFS fails

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
Reality2Wfs.Test.show_routing_table()
```

Output:
```
===========================================
WFS Routing Table
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
Reality2Wfs.Test.test_local_send()
```

Creates a test Sentant, locates it, and sends an event through WFS.

### Test Remote Send

```elixir
# Get a peer and one of its Sentants
peers = Reality2Transnet.Bluetooth.get_connected_peers()
{peer_id, peer_info} = Enum.at(Map.to_list(peers), 0)
sentant = Enum.at(peer_info.sentants, 0)
sentant_id = Map.get(sentant, "id")

# Test sending via WFS
Reality2Wfs.Test.test_remote_send(peer_id, sentant_id)
```

### Full Integration Test

```elixir
Reality2Wfs.Test.test_integration()
```

Runs all tests: local send, remote send, broadcast, and displays statistics.

### Quick Test

```elixir
Reality2Wfs.Test.quick_test()
```

Creates two local Sentants and demonstrates WFS routing between them.

## How It Works

### 1. Topology Cache

The WFS maintains a cache of Sentant locations:

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

The WFS subscribes to PubSub events:

```elixir
# From reality2_transnet
{:r2node_found, node_id, info}   # Add peer sentants to cache
{:r2node_lost, node_id}           # Remove peer sentants from cache
{:sentant_signal, signal_data}    # Future: track signal patterns
```

### 4. Transport Selection

The WFS automatically selects the best transport:

| Scenario | Transport | Implementation |
|----------|-----------|----------------|
| Local Sentant | Direct | `Reality2.Sentants.sendto()` |
| GATT Peer | Bluetooth | `Reality2Transnet.Bluetooth.send_to_peer_sentant()` |
| GraphQL Node | HTTP/WebSocket | (Future) `GraphQLClient.mutation()` |
| Unknown | Fallback | Try local, then error |

## Configuration

No configuration needed! The WFS automatically:
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
Reality2Wfs.refresh()

# Wait for peer discovery
Process.sleep(2000)

# Check if peers are connected
Reality2Transnet.Bluetooth.get_connected_peers()
```

### "Routing failed"
```elixir
# Check routing table
Reality2Wfs.Test.show_routing_table()

# Try locating the Sentant
Reality2Wfs.locate(sentant_id)

# Check if transnet is loaded
Code.ensure_loaded?(Reality2Transnet.Bluetooth)
```

### "Remote send not working"
```elixir
# Verify peer connection
Reality2Transnet.BluetoothTest.list_connected_peers()

# Test GATT directly
Reality2Transnet.BluetoothTest.test_peer_to_peer()

# Check WFS routing
Reality2Wfs.Test.test_remote_send(peer_id, sentant_id)
```

## API Reference

### Core Functions

#### `Reality2Wfs.send_to/4`
Send event to a Sentant (location-transparent).

#### `Reality2Wfs.broadcast/4`
Broadcast event to multiple Sentants.

#### `Reality2Wfs.locate/1`
Find where a Sentant is located.

#### `Reality2Wfs.routing_table/0`
Get current routing table and statistics.

#### `Reality2Wfs.refresh/0`
Force topology cache refresh.

### Test Functions

#### `Reality2Wfs.Test.show_routing_table/0`
Display formatted routing table.

#### `Reality2Wfs.Test.test_local_send/0`
Test sending to local Sentant.

#### `Reality2Wfs.Test.test_remote_send/2`
Test sending to remote Sentant.

#### `Reality2Wfs.Test.test_broadcast/1`
Test broadcasting with pattern.

#### `Reality2Wfs.Test.test_integration/0`
Run full integration test suite.

#### `Reality2Wfs.Test.quick_test/0`
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

**With WFS**, the controller doesn't need to know:
- Where `sensor_temp` is (Device A)
- How to reach it (GATT Bluetooth)
- The BLE address or connection details

The WFS handles **all routing automatically**! 🎯

## Integration with GraphQL

The WFS routing is **parallel** to GraphQL:

```
External Client              Internal Automation
      ↓                            ↓
   GraphQL                        WFS
(sentantSend mutation)    (send action in YAML)
      ↓                            ↓
      └──────→ Reality2.Sentants ←─┘
```

Both paths converge at the Sentant layer, and both receive signals via the same PubSub system.

## Summary

The Reality2 WFS provides:
- ✅ Location-transparent routing
- ✅ Automatic transport selection
- ✅ Mesh networking support
- ✅ Backwards compatibility
- ✅ Comprehensive testing tools
- ✅ Zero configuration needed

Send events to any Sentant, anywhere, without worrying about the details! 🚀
