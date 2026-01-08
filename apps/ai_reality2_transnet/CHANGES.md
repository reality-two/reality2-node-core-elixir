# Transient Network Architecture Changes

## Summary

Redesigned Reality2 Transient Networks to use **BLE for discovery only** and **WiFi mesh for data queries**, solving the 512-byte GATT characteristic size limit problem.

## What Changed

### 1. WiFi Mesh HTTP Server (NEW)

**File:** `lib/ai_reality2_transnet/wifi_server.ex`

- Replaced GenServer wrapper with full HTTP server using Plug.Cowboy
- Provides REST API for Sentant queries and commands
- No size limits - can return full Sentant lists

**Endpoints:**
- `GET /sentants` - Query all Sentants (returns complete list)
- `POST /sentants/:id/send` - Send event to Sentant
- `GET /info` - Get node info with mesh details

**Client functions:**
```elixir
# Query remote peer's sentants
AiReality2Transnet.WifiServer.query_peer_sentants(peer_ipv6)

# Send command to remote sentant
AiReality2Transnet.WifiServer.send_to_peer(peer_ipv6, sentant_id, event, params)
```

### 2. Minimal GATT Protocol (REDESIGNED)

**File:** `lib/ai_reality2_transnet/gatt_protocol.ex`

**Before:** Full Sentant directory exchange via GATT (hit 512-byte limit)

**After:** Minimal info only
- Node Info (UUID 1237) - Returns node_id, capabilities, sentant_count
- Mesh Details (UUID 1235) - Returns IPv6 address, HTTP port for queries
- Mesh Command (UUID 1236) - Send mesh coordination commands

**Key Changes:**
- Removed: `encode_sentant_directory()`, `decode_sentant_directory()`, `handle_sentant_directory_read()`
- Added: `encode_mesh_details()`, `decode_mesh_details()`, `handle_mesh_details_read()`
- Modified: `encode_node_info()` now includes message directing to WiFi mesh

### 3. Dependencies Added

**File:** `mix.exs`

```elixir
{:plug_cowboy, "~> 2.0"},  # HTTP server
{:httpoison, "~> 2.0"}     # HTTP client
```

### 4. Documentation

**New Files:**
- `ARCHITECTURE.md` - Complete architecture documentation
- `CHANGES.md` - This file

## Discovery Flow (Before vs After)

### Before (BLE GATT only)
```
1. Detect BLE beacon
2. Connect via GATT
3. Read Sentant directory (512 bytes max - PROBLEM!)
4. Truncated JSON = invalid data
```

### After (BLE + WiFi Mesh)
```
1. Detect BLE beacon
2. Connect via GATT
3. Read Node Info (minimal - ~200 bytes)
4. Read Mesh Details (IPv6, port - ~150 bytes)
5. Join WiFi mesh
6. Query sentants via HTTP (no size limits!)
```

## Code Size Impact

**Additions:**
- WifiServer.Router: ~220 lines (HTTP endpoints)
- GattProtocol updates: ~150 lines (minimal protocol)
- ARCHITECTURE.md: ~400 lines (documentation)

**Removals:**
- Old WifiServer GenServer commands: ~200 lines
- GattProtocol full directory functions: ~100 lines

**Net change:** ~+470 lines (mostly documentation)

## Benefits

1. **Solves 512-byte GATT limit** - No more truncated JSON
2. **Better separation of concerns** - BLE for discovery, WiFi for data
3. **Higher bandwidth** - WiFi mesh ~50 Mbps vs BLE ~1 Mbps
4. **Power efficient** - BLE beacon low power, WiFi only when needed
5. **Scalable** - WiFi mesh supports multi-hop routing
6. **Debuggable** - HTTP is standard, can use curl/httpie for testing

## Testing

### Test BLE Discovery
```bash
iex> AiReality2Transnet.Bluetooth.get_state()
# Should show GATT server running
```

### Test WiFi HTTP Server
```bash
# From another device on same mesh
curl -v http://[fe80::1234:5678:90ab:cdef%mesh0]:8080/sentants

# Should return full Sentant list JSON
```

### Test End-to-End
```elixir
# 1. Discover peer via BLE
# (automatic when beacon detected)

# 2. Get peer's IPv6 from PeerManager
{:ok, peer} = AiReality2Transnet.PeerManager.get_peer("node-uuid")

# 3. Query sentants via WiFi
{:ok, sentants} = AiReality2Transnet.WifiServer.query_peer_sentants(
  peer.ipv6_link_local
)

# 4. Send command
{:ok, response} = AiReality2Transnet.WifiServer.send_to_peer(
  peer.ipv6_link_local,
  "sentant-uuid",
  "read",
  %{unit: "celsius"}
)
```

## Breaking Changes

### For Android App (reality2-android-devtool)

The Android app will need updates to:
1. Read mesh details from new GATT characteristic (UUID 1235)
2. Join WiFi mesh network
3. Query sentants via HTTP instead of GATT

**Note:** The existing GraphQL-over-GATT protocol (UUIDs 2A57, 2A58, 2A59) in `bluetooth.ex` is unchanged and still works for app control.

### For Device-to-Device Communication

Devices using the old Transient Network GATT protocol will need firmware updates to:
1. Use minimal Node Info characteristic (UUID 1237)
2. Read mesh details from UUID 1235
3. Query sentants via HTTP at ipv6:8080

## Backward Compatibility

- BLE beacon format unchanged (AltBeacon)
- GATT service UUID unchanged (00001234-...)
- Characteristic UUIDs repurposed but same values
- GraphQL-over-GATT (bluetooth.ex) unchanged

## Next Steps

1. **Test on ARM devices** - Compile for Arduino Uno-Q
2. **Update Android app** - Add WiFi mesh support
3. **Add security** - TLS for HTTP, mesh encryption
4. **Performance testing** - Measure BLE→WiFi handoff time
5. **Multi-hop routing** - Test mesh routing through intermediate nodes

## Files Modified

- ✏️  `lib/ai_reality2_transnet/wifi_server.ex` - Complete rewrite as HTTP server
- ✏️  `lib/ai_reality2_transnet/gatt_protocol.ex` - Minimal protocol
- ✏️  `mix.exs` - Added plug_cowboy, httpoison
- ➕ `ARCHITECTURE.md` - New documentation
- ➕ `CHANGES.md` - This file

## Files Unchanged (but relevant)

- `lib/ai_reality2_transnet/bluetooth.ex` - GraphQL-over-GATT (for Android app)
- `lib/ai_reality2_transnet/peer_manager.ex` - Tracks discovered peers
- `lib/ai_reality2_transnet/transport_manager.ex` - Decides BLE→WiFi upgrade
- `lib/ai_reality2_transnet/wifi.ex` - Pure Elixir WiFi mesh operations
- `lib/ai_reality2_transnet/application.ex` - Supervision tree

## Questions?

See `ARCHITECTURE.md` for detailed protocol specification and examples.
