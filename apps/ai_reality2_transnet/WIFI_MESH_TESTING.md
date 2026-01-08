# WiFi Mesh Testing Guide

Complete guide to testing Reality2 WiFi mesh networking across multiple devices.

## Prerequisites

### Hardware Requirements

**Each device needs:**
- WiFi adapter that supports mesh mode (IEEE 802.11s)
- Linux-based OS (tested on Ubuntu, Debian, Raspberry Pi OS)
- Root/sudo access

**Check if your WiFi adapter supports mesh:**
```bash
sudo iw list | grep -A 10 "Supported interface modes"
# Look for "mesh point" in the list
```

**Common compatible adapters:**
- Intel WiFi cards (most recent models)
- Atheros ath9k/ath10k chipsets
- Raspberry Pi built-in WiFi (BCM43xx)
- USB WiFi adapters with RT5370/RT2870 chipsets

### Software Requirements

**Each device needs:**
```bash
# Install required packages
sudo apt-get update
sudo apt-get install iw iproute2 wireless-tools

# Verify tools are available
which iw ip
```

### Reality2 Application

**On each device:**
```bash
cd reality2-node-core-elixir
mix deps.get
mix compile
```

---

## Testing Scenario: 3-Device Mesh Network

Let's call the devices:
- **Device A** (192.168.1.100)
- **Device B** (192.168.1.101)
- **Device C** (192.168.1.102)

---

## Phase 1: Verify WiFi Adapters

**On each device, in IEx:**

```elixir
# Start the application
iex -S mix

# List available WiFi adapters
iex> AiReality2Transnet.Wifi.list_adapters()
{:ok, [
  %{
    interface: "wlan0",
    mesh_interface: "mesh0",
    address: "aa:bb:cc:dd:ee:ff",
    transport: "wifi",
    ip_address: nil
  }
]}
```

**Troubleshooting:**
- If no adapters found: Check `ip link show` to see available interfaces
- If adapter doesn't support mesh: You'll get errors in Phase 2

---

## Phase 2: Create Mesh Interfaces

**On each device (requires sudo):**

### Option A: From IEx (Recommended)

```elixir
# Create mesh interface on wlan0
iex> AiReality2Transnet.Wifi.create_mesh_interface("wlan0", "mesh0")
:ok
```

### Option B: From Shell

```bash
# Create mesh interface
sudo iw dev wlan0 interface add mesh0 type mp

# Verify it was created
ip link show mesh0
```

**Expected output:**
```
mesh0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT
```

---

## Phase 3: Start the Mesh Network

**IMPORTANT:** All devices must use the **same mesh ID** and **same channel**.

**On Device A:**
```elixir
iex> AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH", 2437)
:ok
```

**On Device B:**
```elixir
iex> AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH", 2437)
:ok
```

**On Device C:**
```elixir
iex> AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH", 2437)
:ok
```

**Parameters:**
- `"mesh0"` - Mesh interface name
- `"R2MESH"` - Mesh ID (must match on all devices!)
- `2437` - Frequency in MHz (channel 6 on 2.4GHz band)

**Common channels:**
- 2412 = Channel 1
- 2437 = Channel 6 (recommended, least interference)
- 2462 = Channel 11
- 5180 = Channel 36 (5GHz, if supported)

---

## Phase 4: Verify Mesh Formation

**Wait 10-30 seconds for mesh peering to complete.**

### Check Mesh Status

**On each device:**

```bash
# Check mesh interface is up
ip link show mesh0
# Should show: state UP

# Check mesh status
sudo iw dev mesh0 info
```

**Expected output:**
```
Interface mesh0
    ifindex 5
    wdev 0x100000002
    addr aa:bb:cc:dd:ee:ff
    type mesh point
    wiphy 1
    channel 6 (2437 MHz), width: 20 MHz, center1: 2437 MHz
    mesh id: R2MESH
```

### Check Mesh Peers

**On Device A:**

```elixir
iex> AiReality2Transnet.Wifi.list_mesh_peers("mesh0")
{:ok, [
  %{mac_address: "11:22:33:44:55:66", signal_strength: -45, last_seen: 120},
  %{mac_address: "77:88:99:aa:bb:cc", signal_strength: -52, last_seen: 340}
]}
# Should see Device B and Device C
```

**Or from shell:**
```bash
sudo iw dev mesh0 station dump
```

**Expected output:**
```
Station 11:22:33:44:55:66 (on mesh0)
    mesh plink: ESTAB
    signal: -45 dBm
    tx bitrate: 54.0 MBit/s
```

**If no peers show up:**
- Wait longer (up to 60 seconds)
- Check all devices are on same mesh ID: `sudo iw dev mesh0 info | grep "mesh id"`
- Check all devices are on same channel
- Check devices are in WiFi range (try moving closer)

---

## Phase 5: Get IPv6 Addresses

**Mesh uses IPv6 link-local addresses for peer-to-peer communication.**

**On each device:**

```elixir
iex> AiReality2Transnet.Wifi.get_ipv6_link_local("mesh0")
{:ok, "fe80::aabb:ccff:fedd:eeff"}
```

**Or from shell:**
```bash
ip -6 addr show dev mesh0 | grep "fe80"
```

**Note these down:**
- Device A: `fe80::1111:2222:3333:4444`
- Device B: `fe80::5555:6666:7777:8888`
- Device C: `fe80::9999:aaaa:bbbb:cccc`

---

## Phase 6: Test IPv6 Connectivity

**From Device A, ping Device B:**

```bash
ping6 -c 4 fe80::5555:6666:7777:8888%mesh0
# Note: %mesh0 is required to specify the interface
```

**Expected output:**
```
PING fe80::5555:6666:7777:8888%mesh0(fe80::5555:6666:7777:8888) 56 data bytes
64 bytes from fe80::5555:6666:7777:8888: icmp_seq=1 ttl=64 time=2.3 ms
64 bytes from fe80::5555:6666:7777:8888: icmp_seq=2 ttl=64 time=1.9 ms
```

**Test all combinations:**
- A → B ✓
- A → C ✓
- B → A ✓
- B → C ✓
- C → A ✓
- C → B ✓

**If ping fails:**
- Verify mesh peers are connected: `sudo iw dev mesh0 station dump`
- Check IPv6 is enabled: `sysctl net.ipv6.conf.mesh0.disable_ipv6` (should be 0)
- Try bringing interface down and up: `sudo ip link set mesh0 down && sudo ip link set mesh0 up`

---

## Phase 7: Start WiFi HTTP Server

**On each device:**

```elixir
# Start the WiFi HTTP server on port 8080
iex> AiReality2Transnet.WifiServer.start()
{:ok, #PID<0.1234.0>}
```

**Verify server is running:**
```bash
# Check server is listening on port 8080
netstat -tuln | grep 8080
# Should show: tcp6  0  0 :::8080  :::*  LISTEN
```

---

## Phase 8: Test HTTP Connectivity

**From Device A, query Device B's HTTP server:**

```bash
# Test /info endpoint
curl "http://[fe80::5555:6666:7777:8888%mesh0]:8080/info"
```

**Expected response:**
```json
{
  "node_id": "550e8400-e29b-41d4-a716-446655440000",
  "mesh_id": "R2MESH",
  "ipv6_link_local": "fe80::5555:6666:7777:8888",
  "http_port": 8080,
  "timestamp": 1736345678000
}
```

**If connection fails:**
- Try using IP instead of curl's bracket notation: `curl -g http://[fe80::...%mesh0]:8080/info`
- Check firewall: `sudo ufw allow 8080` or `sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT`
- Verify server is running: Check IEx for errors

---

## Phase 9: Test GraphQL Queries

### Query Remote Sentants

**From Device A, query Device B's sentants:**

```bash
curl -X POST "http://[fe80::5555:6666:7777:8888%mesh0]:8080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { sentantAll { id name events signals } }"}'
```

**Expected response (privacy filtered):**
```json
{
  "data": {
    "sentantAll": [
      {
        "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        "name": "temperature_sensor",
        "events": ["read", "calibrate"],
        "signals": ["temperature_changed"]
      }
    ]
  }
}
```

**Or from IEx:**

```elixir
iex> peer_ipv6 = "fe80::5555:6666:7777:8888"
iex> AiReality2Transnet.WifiServer.query_peer_sentants(peer_ipv6)
{:ok, [
  %{
    "id" => "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "name" => "temperature_sensor",
    "events" => ["read", "calibrate"],
    "signals" => ["temperature_changed"]
  }
]}
```

### Send Event to Remote Sentant

**From Device A, send event to Device B's sentant:**

```bash
curl -X POST "http://[fe80::5555:6666:7777:8888%mesh0]:8080/graphql" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($id: ID!, $event: String!, $parameters: String) { sentantSend(id: $id, event: $event, parameters: $parameters) { id name } }",
    "variables": {
      "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "event": "read",
      "parameters": "{\"unit\":\"celsius\"}"
    }
  }'
```

**Or from IEx:**

```elixir
iex> peer_ipv6 = "fe80::5555:6666:7777:8888"
iex> sentant_id = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
iex> AiReality2Transnet.WifiServer.send_to_peer(peer_ipv6, sentant_id, "read", %{unit: "celsius"})
{:ok, %{"id" => "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "name" => "temperature_sensor"}}
```

---

## Phase 10: Test Full Mesh Communication

**Verify all devices can query each other:**

### Device A queries Device B and C

```elixir
# On Device A
iex> AiReality2Transnet.WifiServer.query_peer_sentants("fe80::5555:6666:7777:8888")
{:ok, [...]} # Device B's sentants

iex> AiReality2Transnet.WifiServer.query_peer_sentants("fe80::9999:aaaa:bbbb:cccc")
{:ok, [...]} # Device C's sentants
```

### Device B queries Device A and C

```elixir
# On Device B
iex> AiReality2Transnet.WifiServer.query_peer_sentants("fe80::1111:2222:3333:4444")
{:ok, [...]} # Device A's sentants

iex> AiReality2Transnet.WifiServer.query_peer_sentants("fe80::9999:aaaa:bbbb:cccc")
{:ok, [...]} # Device C's sentants
```

### Device C queries Device A and B

```elixir
# On Device C
iex> AiReality2Transnet.WifiServer.query_peer_sentants("fe80::1111:2222:3333:4444")
{:ok, [...]} # Device A's sentants

iex> AiReality2Transnet.WifiServer.query_peer_sentants("fe80::5555:6666:7777:8888")
{:ok, [...]} # Device B's sentants
```

---

## Phase 11: Test Multi-Hop Routing

**Move Device A and C out of direct WiFi range, but keep B in range of both.**

**Topology:**
```
A ←--→ B ←--→ C
(A cannot directly see C)
```

**From Device A, ping Device C:**
```bash
ping6 -c 4 fe80::9999:aaaa:bbbb:cccc%mesh0
```

**Expected:** Packets route through Device B automatically (HWMP routing).

**From Device A, query Device C's sentants:**
```elixir
iex> AiReality2Transnet.WifiServer.query_peer_sentants("fe80::9999:aaaa:bbbb:cccc")
{:ok, [...]} # Should work via B as a relay
```

**Verify routing path:**
```bash
# On Device B, watch mesh traffic
sudo iw dev mesh0 station dump
# Look for both A and C in the station list
```

---

## Troubleshooting

### Mesh Interface Won't Create

**Error:** `Device or resource busy`

**Solution:**
```bash
# Stop NetworkManager from interfering
sudo systemctl stop NetworkManager
# Or disable for specific interface
sudo nmcli device set wlan0 managed no
```

### No Mesh Peers Appear

**Check:**
1. All devices using same mesh ID: `sudo iw dev mesh0 info | grep "mesh id"`
2. All devices on same channel: `sudo iw dev mesh0 info | grep channel`
3. Devices in WiFi range (move closer, < 50m for initial testing)
4. No conflicting APs on same channel

**Restart mesh:**
```elixir
iex> AiReality2Transnet.Wifi.destroy_mesh_interface("mesh0")
iex> AiReality2Transnet.Wifi.create_mesh_interface("wlan0", "mesh0")
iex> AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH", 2437)
```

### HTTP Server Not Responding

**Check server is running:**
```elixir
iex> Process.whereis(AiReality2Transnet.WifiServer)
#PID<0.1234.0> # Should return a PID
```

**Check firewall:**
```bash
sudo ufw status
sudo ufw allow 8080
```

**Check IPv6:**
```bash
# Ensure IPv6 is enabled
sysctl net.ipv6.conf.all.disable_ipv6
# Should be 0
```

### GraphQL Queries Return Errors

**Check Reality2 application is running:**
```elixir
iex> Reality2.Bootstrap.get(:node_id)
"550e8400-e29b-41d4-a716-446655440000"
```

**Check sentants exist:**
```elixir
iex> Reality2.Metadata.all(:SentantIDs)
%{"sensor1" => "uuid-1", "sensor2" => "uuid-2"}
```

**Restart WiFi server:**
```elixir
iex> AiReality2Transnet.WifiServer.stop()
iex> AiReality2Transnet.WifiServer.start()
```

---

## Success Criteria ✅

**You've successfully tested WiFi mesh when:**

- ✅ All devices can create mesh interfaces
- ✅ All devices join the mesh network (same mesh ID)
- ✅ Mesh peers appear in station dump
- ✅ IPv6 pings work between all devices
- ✅ HTTP /info endpoint accessible from all devices
- ✅ GraphQL sentantAll query returns data (privacy filtered)
- ✅ GraphQL sentantSend mutation works across devices
- ✅ Multi-hop routing works (A → B → C)

---

## Performance Testing

### Bandwidth Test

```bash
# On Device A, start iperf3 server
iperf3 -s -V

# On Device B, test throughput to Device A
iperf3 -c fe80::1111:2222:3333:4444%mesh0 -V
```

**Expected:** 10-50 Mbps depending on WiFi standard and conditions

### Latency Test

```bash
# Continuous ping
ping6 -i 0.2 fe80::5555:6666:7777:8888%mesh0
```

**Expected:** 1-10 ms for direct peers, 5-20 ms for multi-hop

### Load Test

```bash
# Query sentants rapidly
for i in {1..100}; do
  curl -s "http://[fe80::5555:6666:7777:8888%mesh0]:8080/graphql" \
    -H "Content-Type: application/json" \
    -d '{"query": "query { sentantAll { id name } }"}' > /dev/null
done
```

---

## Cleanup

**When done testing:**

```elixir
# Stop WiFi server
iex> AiReality2Transnet.WifiServer.stop()

# Destroy mesh interface
iex> AiReality2Transnet.Wifi.destroy_mesh_interface("mesh0")
```

**Or from shell:**
```bash
sudo iw dev mesh0 del
```

---

## Next Steps

Once basic mesh is working:
1. Test BLE + WiFi handoff (BLE discovery → WiFi upgrade)
2. Test automatic peer discovery
3. Test signal-based subscriptions (future feature)
4. Performance optimization
5. Power consumption testing (especially on battery devices)

---

## Reference

- **WiFi Mesh Code:** `apps/ai_reality2_transnet/lib/ai_reality2_transnet/wifi.ex`
- **HTTP Server:** `apps/ai_reality2_transnet/lib/ai_reality2_transnet/wifi_server.ex`
- **Architecture:** `apps/ai_reality2_transnet/WIFI_MESH_GRAPHQL.md`
- **IEEE 802.11s Standard:** [Wikipedia](https://en.wikipedia.org/wiki/IEEE_802.11s)
