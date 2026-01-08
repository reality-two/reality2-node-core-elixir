# WiFi Mesh Quick Start

Fast setup guide for testing WiFi mesh on multiple devices.

## Quick Setup (Each Device)

### 1. Start IEx
```bash
cd reality2-node-core-elixir
sudo iex -S mix
```

### 2. Create and Start Mesh
```elixir
# Create mesh interface
AiReality2Transnet.Wifi.create_mesh_interface("wlan0", "mesh0")

# Join mesh network (SAME mesh ID and channel on all devices!)
AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH", 2437)

# Start HTTP server
AiReality2Transnet.WifiServer.start()
```

### 3. Get Your IPv6 Address
```elixir
AiReality2Transnet.Wifi.get_ipv6_link_local("mesh0")
# Note this down: fe80::xxxx:xxxx:xxxx:xxxx
```

---

## Quick Tests

### Check Mesh Peers
```elixir
AiReality2Transnet.Wifi.list_mesh_peers("mesh0")
```

### Test Connectivity (from shell)
```bash
ping6 -c 4 fe80::PEER_IPV6%mesh0
```

### Query Remote Sentants
```elixir
peer_ipv6 = "fe80::PEER_IPV6"
AiReality2Transnet.WifiServer.query_peer_sentants(peer_ipv6)
```

### Send Event to Remote Sentant
```elixir
peer_ipv6 = "fe80::PEER_IPV6"
sentant_id = "sentant-uuid-from-query"
AiReality2Transnet.WifiServer.send_to_peer(peer_ipv6, sentant_id, "read", %{unit: "celsius"})
```

---

## Quick Troubleshooting

**No mesh peers?**
```bash
# Check all devices have same mesh ID and channel
sudo iw dev mesh0 info

# Restart mesh
AiReality2Transnet.Wifi.destroy_mesh_interface("mesh0")
AiReality2Transnet.Wifi.create_mesh_interface("wlan0", "mesh0")
AiReality2Transnet.Wifi.start_mesh("mesh0", "R2MESH", 2437)
```

**HTTP not responding?**
```bash
# Check firewall
sudo ufw allow 8080

# Restart server
AiReality2Transnet.WifiServer.stop()
AiReality2Transnet.WifiServer.start()
```

**For detailed guide, see WIFI_MESH_TESTING.md**
