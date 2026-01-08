# BLE Discovery Fix

## Problem

After implementing the WiFi mesh HTTP protocol, BLE beacon discovery stopped working because `bluetooth.ex` was trying to use the old GATT protocol to read Sentants from discovered peers.

## Root Cause

When a BLE beacon was detected, `bluetooth.ex` automatically:
1. Connected to the peer via GATT
2. Tried to read Sentants from characteristic UUID `2A57` (GraphQL service)
3. **This failed** because it should have been reading from the Transient Network service (UUID `1234`)
4. But we **removed** the Sentant directory from the Transient Network protocol!

## The Fix

### Changed Discovery Flow

**Before (Broken):**
```
BLE Beacon Detected
  └─> connect_to_peer(address, node_id)
      └─> read_peer_sentants() [Uses old GATT protocol]
          └─> Read from UUID 2A57 (wrong service!)
              └─> FAILS - trying to read sentants via GATT
```

**After (Fixed):**
```
BLE Beacon Detected
  └─> Register peer with PeerManager
      └─> Peer tracked as :ble_gatt transport
          └─> TransportManager can upgrade to WiFi mesh later
              └─> Query sentants via HTTP (no GATT)
```

### Code Changes

#### 1. Updated `handle_info({:r2node_found, ...})` in bluetooth.ex

**Before:**
```elixir
def handle_info({:r2node_found, id, info}, state) do
  # Automatically connect as GATT client and read peer's sentants
  case connect_to_peer(address, id, adapter_name) do
    {:ok, peer_info} ->
      # Add to connected_peers
      new_peers = Map.put(state.connected_peers, id, peer_info)
      {:noreply, %{state | connected_peers: new_peers}}
  end
end
```

**After:**
```elixir
def handle_info({:r2node_found, id, info}, state) do
  # Register peer with PeerManager (BLE discovery only)
  # Sentant queries will happen via WiFi mesh HTTP after upgrade
  if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
    AiReality2Transnet.PeerManager.register_peer(id, info)
  end
  {:noreply, state}
end
```

#### 2. Updated `handle_info({:r2node_lost, ...})` in bluetooth.ex

**Before:**
```elixir
def handle_info({:r2node_lost, id}, state) do
  # Remove from connected peers
  new_peers = Map.delete(state.connected_peers, id)
  {:noreply, %{state | connected_peers: new_peers}}
end
```

**After:**
```elixir
def handle_info({:r2node_lost, id}, state) do
  # Remove from PeerManager
  if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
    AiReality2Transnet.PeerManager.remove_peer(id)
  end
  {:noreply, state}
end
```

#### 3. Deprecated Old GATT Functions

**Removed:**
- `connect_to_peer/3` - No longer needed
- `read_peer_sentants/2` - Used old GATT protocol

**Added comment:**
```elixir
# NOTE: These functions are deprecated. BLE is now for discovery only.
# For Sentant queries, use WiFi Mesh HTTP via WifiServer module.
#
# To query remote sentants:
#   {:ok, peer} = AiReality2Transnet.PeerManager.get_peer(node_id)
#   {:ok, sentants} = AiReality2Transnet.WifiServer.query_peer_sentants(peer.ipv6_link_local)
```

#### 4. Updated API Functions to Use PeerManager

**Before:**
```elixir
def get_connected_peers do
  GenServer.call(__MODULE__, :get_connected_peers)
end
```

**After:**
```elixir
def get_connected_peers do
  if Code.ensure_loaded?(AiReality2Transnet.PeerManager) do
    AiReality2Transnet.PeerManager.get_all_peers()
  else
    %{}
  end
end
```

## Testing

### Check BLE is Working

```elixir
# System should show:
# |-- Node ID: xxx beacon started on hci0
# |-- R2 watch started on hci0
# [info] GATT Sentant Server is ready and discoverable

# When a peer is detected, you'll see:
# [info] R2 Node discovered: <uuid>
# [info] Peer <short-uuid>... registered with PeerManager
```

### Check Peer Discovery

```elixir
# Get discovered peers (via PeerManager now, not bluetooth module)
iex> AiReality2Transnet.PeerManager.get_all_peers()
%{
  "node-uuid" => %{
    node_id: "node-uuid",
    transport: :ble_gatt,  # Discovered via BLE
    address: "AA:BB:CC:DD:EE:FF",
    rssi: -45,
    sentants: [],  # Empty - not queried yet
    last_seen: 1234567890
  }
}
```

### Query Sentants via WiFi Mesh

```elixir
# After peer upgrades to WiFi mesh
iex> {:ok, peer} = AiReality2Transnet.PeerManager.get_peer("node-uuid")
iex> peer.transport
:wifi_mesh

# Query sentants via HTTP (not GATT!)
iex> AiReality2Transnet.WifiServer.query_peer_sentants(peer.ipv6_link_local)
{:ok, [
  %{id: "...", name: "sensor1", events: ["read"], ...}
]}
```

## Architecture Now

```
┌─────────────────────────────────────────────────────────┐
│                    BLE Discovery                         │
│  (Beacon + minimal GATT - no Sentant data transfer)     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
          ┌──────────────────────┐
          │    PeerManager       │
          │  (Track all peers)   │
          └──────────┬───────────┘
                     │
                     ↓
          ┌──────────────────────┐
          │  TransportManager    │
          │ (Decide WiFi upgrade)│
          └──────────┬───────────┘
                     │
                     ↓ (upgrade when needed)
┌─────────────────────────────────────────────────────────┐
│                   WiFi Mesh HTTP                         │
│   (Query sentants, send commands - no size limits!)     │
└─────────────────────────────────────────────────────────┘
```

## What Works Now

✅ **BLE Beacon Broadcasting** - Advertises node presence
✅ **BLE Node Discovery** - Detects nearby Reality2 nodes
✅ **Peer Registration** - Tracks discovered peers in PeerManager
✅ **Peer Cleanup** - Removes lost peers automatically
✅ **GATT Server** - Still works for Android app (GraphQL-over-GATT)
✅ **WiFi Mesh Upgrade** - Can upgrade BLE peers to WiFi for data
✅ **HTTP Sentant Queries** - No 512-byte limit!

## What Doesn't Work (By Design)

❌ **Sentant queries via GATT** - Removed (use WiFi mesh HTTP)
❌ **Automatic GATT connection** - Removed (just register peer)
❌ **connected_peers in bluetooth.ex** - Deprecated (use PeerManager)

## Migration Guide

### Old Code (Before Fix)

```elixir
# Get peers from bluetooth module
peers = AiReality2Transnet.Bluetooth.get_connected_peers()

# Peers had sentants pre-loaded from GATT
sentants = peers["node-uuid"].sentants
```

### New Code (After Fix)

```elixir
# Get peers from PeerManager
peers = AiReality2Transnet.PeerManager.get_all_peers()

# Peer is just registered, no sentants yet
peer = peers["node-uuid"]
# peer.sentants = [] (empty)
# peer.transport = :ble_gatt (discovery only)

# Upgrade to WiFi mesh first
AiReality2Transnet.TransportManager.initiate_wifi_upgrade("node-uuid")

# Then query sentants via HTTP
{:ok, peer} = AiReality2Transnet.PeerManager.get_peer("node-uuid")
{:ok, sentants} = AiReality2Transnet.WifiServer.query_peer_sentants(peer.ipv6_link_local)
```

## Related Documentation

- `ARCHITECTURE.md` - Complete protocol specification
- `CHANGES.md` - What changed and why
- `BUGFIXES.md` - Compilation warning fixes
- `BLE_DISCOVERY_FIX.md` - This file

## Summary

**Problem:** BLE discovery broke because it tried to read Sentants via old GATT protocol
**Solution:** BLE now just registers peers, WiFi mesh HTTP handles data queries
**Result:** BLE beacon/discovery working again ✅
