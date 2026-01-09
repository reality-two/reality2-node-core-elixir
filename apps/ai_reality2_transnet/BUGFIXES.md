# Bug Fixes - BLE Discovery + WiFi Mesh Architecture

## Summary

Fixed compilation warnings after transitioning from GATT-based Sentant queries to WiFi mesh HTTP protocol.

## Issues Fixed

### 1. Unused Module Attribute

**File:** `lib/ai_reality2_transnet/wifi_server.ex`

**Warning:**
```
warning: module attribute @version was set but never used
```

**Fix:** Removed unused `@version "0.1.13"` module attribute

### 2. Deprecated GATT Protocol Functions in Tests

**File:** `lib/ai_reality2_transnet/transient_network_test.ex`

**Warnings:**
```
warning: AiReality2Transnet.GattProtocol.encode_sentant_directory/1 is undefined or private
warning: AiReality2Transnet.GattProtocol.decode_sentant_directory/1 is undefined or private
warning: AiReality2Transnet.GattProtocol.encode_sentant_command/4 is undefined or private
warning: AiReality2Transnet.GattProtocol.decode_sentant_command/1 is undefined or private
```

**Fix:** Updated `test_gatt_protocol/0` to use new minimal protocol functions:

**Before (Full Sentant Exchange via GATT):**
```elixir
# Test 1: Encode/decode Sentant directory
directory_json = GattProtocol.encode_sentant_directory(node_id)
{:ok, decoded} = GattProtocol.decode_sentant_directory(directory_json)

# Test 2: Encode/decode Sentant command
command_json = GattProtocol.encode_sentant_command(sentant_id, event, params, pass)
{:ok, decoded} = GattProtocol.decode_sentant_command(command_json)
```

**After (Minimal Info + WiFi Mesh Details):**
```elixir
# Test 1: Encode/decode minimal node info
node_info_json = GattProtocol.encode_node_info(node_id)
{:ok, decoded} = GattProtocol.decode_node_info(node_info_json)
# Returns: node_id, capabilities, sentant_count, message

# Test 2: Encode/decode WiFi mesh details
mesh_details_json = GattProtocol.encode_mesh_details()
{:ok, decoded} = GattProtocol.decode_mesh_details(mesh_details_json)
# Returns: mesh_id, ipv6_link_local, http_port, instructions

# Test 3: Encode/decode mesh command
command_json = GattProtocol.encode_mesh_command(:join_mesh, %{mesh_id: "R2MESH"})
{:ok, decoded} = GattProtocol.decode_mesh_command(command_json)
```

### 3. PNS Router Using Old GATT Functions

**File:** `lib/ai_reality2_pns/router.ex`

**Warnings:**
```
warning: AiReality2Transnet.GattProtocol.encode_sentant_command/4 is undefined or private
warning: AiReality2Transnet.GattProtocol.sentant_command_uuid/0 is undefined or private
```

**Fix:** Updated PNS Router to use WiFi mesh HTTP instead of GATT for Sentant commands

**Before (GATT Commands):**
```elixir
defp send_to_remote_gatt(node_id, sentant_id, event, params, pass) do
  # Encode command as JSON for GATT
  json_command = GattProtocol.encode_sentant_command(sentant_id, event, params, pass)

  case peer.transport do
    :ble_gatt -> send_via_ble_gatt(node_id, peer.address, json_command)
    :wifi_mesh -> send_via_wifi_mesh(node_id, json_command)
  end
end

defp send_via_ble_gatt(node_id, address, json_command) do
  char_uuid = GattProtocol.sentant_command_uuid()  # 00001236-...
  # Write to GATT characteristic
end
```

**After (WiFi Mesh HTTP):**
```elixir
defp send_to_remote_gatt(node_id, sentant_id, event, params, pass) do
  {:ok, peer} = PeerManager.get_peer(node_id)

  case peer.transport do
    :wifi_mesh ->
      # Use HTTP POST to peer's IPv6 address
      send_via_wifi_mesh(peer, sentant_id, event, params, pass)

    :ble_gatt ->
      # BLE is for discovery only
      Logger.warning("Peer is on BLE (discovery only)")
      {:error, :ble_discovery_only}
  end
end

defp send_via_wifi_mesh(peer, sentant_id, event, params, pass) do
  ipv6 = peer.ipv6_link_local
  # Uses GraphQL at http://[ipv6]:4005/reality2
  WifiServer.send_to_peer(ipv6, sentant_id, event, params, pass)
end
```

**Key Changes:**
- Removed JSON encoding (HTTP client does this automatically)
- Removed GATT characteristic UUID references
- Added IPv6 address lookup from peer info
- BLE transport now returns error (discovery only)
- Removed old `send_via_wifi_mesh/2` stub function

## Compilation Result

**Before:**
- 9 warnings about undefined functions
- 1 warning about unused module attribute

**After:**
- ✅ 0 warnings
- ✅ Clean compilation
- ✅ All apps generated successfully

## Architecture Summary

### Old Flow (GATT-based)
```
BLE Beacon → GATT Connect → Read Sentant Directory → Send Commands via GATT
                             (512 byte limit!)      (Character UUID 1236)
```

### New Flow (Minimal GATT + WiFi HTTP)
```
BLE Beacon → GATT Connect → Read Node Info (minimal)
                          → Read Mesh Details (IPv6, port)
                          → Join WiFi Mesh
                          → Query Sentants via HTTP (no limits!)
                          → Send Commands via HTTP POST
```

## Testing After Fixes

### 1. Test GATT Protocol (Minimal)
```elixir
iex> AiReality2Transnet.TransientNetworkTest.test_gatt_protocol()

=== Testing GATT Protocol (Minimal - Discovery Only) ===

Test 1: Node Info Encoding (Minimal)
  Encoded: ~200 bytes
  ✓ Decoded successfully
    Sentant count: 5
    Message: Use WiFi mesh HTTP for Sentant queries

Test 2: WiFi Mesh Details Encoding
  Encoded: ~150 bytes
  ✓ Decoded successfully
    IPv6: fe80::1234:5678:90ab:cdef
    HTTP port: 4005
    Instructions: Query sentants: GET http://[ipv6]:port/mesh/sentants

Test 3: Mesh Command Encoding
  Encoded: ~80 bytes
  ✓ Decoded successfully
    Command: join_mesh
```

### 2. Test WiFi Mesh HTTP Queries
```bash
# Query sentants from remote peer
curl http://[fe80::1234:5678:90ab:cdef%mesh0]:4005/mesh/sentants

# Send command to remote sentant via GraphQL
curl -X POST http://[fe80::...%mesh0]:4005/reality2 \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { sentantSend(id: \"UUID\", event: \"read\", parameters: \"{\\\"unit\\\": \\\"celsius\\\"}\") { id } }"}'
```

### 3. Test PNS Routing
```elixir
# Discover peer via BLE
# (automatic when beacon detected)

# Upgrade to WiFi mesh
AiReality2Transnet.TransportManager.initiate_wifi_upgrade("peer-node-id")

# Send to remote Sentant (uses WiFi mesh HTTP automatically)
AiReality2Pns.send_to("sentant-id-on-remote-node", "read", %{unit: "celsius"})
# → GraphQL at http://[peer-ipv6]:4005/reality2
```

## Related Documentation

- `ARCHITECTURE.md` - Complete protocol specification
- `CHANGES.md` - Summary of architectural changes
- `BUGFIXES.md` - This file

## Files Modified in This Fix

- ✏️  `wifi_server.ex` - Removed unused @version
- ✏️  `transient_network_test.ex` - Updated to use minimal protocol functions
- ✏️  `router.ex` (PNS) - Changed to use WiFi mesh HTTP for commands

## Backward Compatibility Notes

### For Existing Code

**Breaking:**
- `GattProtocol.encode_sentant_directory/1` - **Removed** (use WiFi HTTP: GET /sentants)
- `GattProtocol.decode_sentant_directory/1` - **Removed**
- `GattProtocol.encode_sentant_command/4` - **Removed** (use WiFi HTTP: POST /sentants/:id/send)
- `GattProtocol.decode_sentant_command/1` - **Removed**
- `GattProtocol.sentant_command_uuid/0` - **Removed** (replaced with mesh_command_uuid)

**New Functions:**
- `GattProtocol.encode_mesh_details/0` - WiFi mesh connection info
- `GattProtocol.decode_mesh_details/1`
- `GattProtocol.encode_mesh_command/2` - Mesh coordination commands
- `GattProtocol.decode_mesh_command/1`
- `WifiServer.query_peer_sentants/2` - HTTP query for Sentants
- `WifiServer.send_to_peer/6` - HTTP POST to send commands

### Migration Guide

**Old Code (GATT):**
```elixir
# Query remote sentants via GATT
{:ok, peer} = PeerManager.get_peer(node_id)
json = GattProtocol.encode_sentant_directory(node_id)
# Read GATT characteristic...
{:ok, decoded} = GattProtocol.decode_sentant_directory(response)
```

**New Code (WiFi HTTP):**
```elixir
# Query remote sentants via WiFi mesh HTTP
{:ok, peer} = PeerManager.get_peer(node_id)
{:ok, sentants} = WifiServer.query_peer_sentants(peer.ipv6_link_local)
# Direct HTTP request, no GATT
```

## Next Steps

1. ✅ All compilation warnings resolved
2. ✅ Tests updated to use new protocol
3. ✅ PNS router updated for WiFi mesh
4. 🔜 Test on actual ARM devices (Arduino Uno-Q)
5. 🔜 Update Android app to use new protocol
6. 🔜 Performance testing of BLE→WiFi handoff

## Questions?

See documentation:
- `ARCHITECTURE.md` - Protocol details
- `CHANGES.md` - What changed and why
- `BUGFIXES.md` - This file
