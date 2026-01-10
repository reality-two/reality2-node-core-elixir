# AiReality2Transnet

Transient Networking module for Reality2 - enables peer-to-peer communication between Reality2 nodes using multiple wireless transports.

## Overview

Reality2 Transient Networks provide automatic mesh networking between nearby Reality2 nodes, allowing Sentants to communicate across devices without infrastructure.

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

## Features

- **BLE Discovery** - AltBeacon broadcasting for node discovery
- **R2Mesh** - Simple relay mesh over BLE (works on any BlueZ version)
- **WiFi Hotspot** - Auto-created WPA2-PSK network for high-bandwidth data
- **LoRa Mesh** - Optional long-range support via USB dongle
- **Automatic Transport Selection** - Best transport chosen based on message size/range
- **Hosting Priority** - Nodes elect host based on capabilities (WiFi adapters, battery, etc.)

## Quick Start

The module starts automatically with the Reality2 application. No configuration required for basic operation.

```elixir
# Check Bluetooth state
AiReality2Transnet.Bluetooth.get_state()

# Get discovered peers
AiReality2Transnet.PeerManager.get_all_peers()

# Send mesh message (small data, ~24 bytes)
AiReality2Transnet.R2Mesh.broadcast_event("sensor", "reading", %{v: 23})

# Check LoRa availability (if USB dongle connected)
AiReality2Transnet.LoRaMesh.available?()
```

## Modules

| Module | Purpose |
|--------|---------|
| `Bluetooth` | BLE beacon, GATT server, discovery |
| `R2Mesh` | Simple BLE relay mesh protocol |
| `LoRaMesh` | Optional LoRa mesh (USB dongle) |
| `Wifi` | WiFi hotspot/client operations |
| `ConnectionManager` | Hotspot creation, client connections |
| `ConnectionAssessor` | Connection quality, handover decisions |
| `PeerManager` | Track discovered peers |
| `GattProtocol` | GATT protocol encoding/decoding |

## Configuration

Optional configuration in `config/config.exs`:

```elixir
config :ai_reality2_transnet,
  # PSK derivation secret (change for production!)
  psk_secret: "YourSecretHere",

  # LoRa configuration (optional)
  lora: [
    enabled: true,
    port: "/dev/ttyUSB0",  # or auto-detect
    spreading_factor: 7,
    tx_power: 14
  ]
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture and protocol specification
- [CHANGES.md](CHANGES.md) - Change history
- [BUGFIXES.md](BUGFIXES.md) - Bug fix documentation

## Requirements

- Linux with BlueZ stack
- NetworkManager (for WiFi hotspot)
- Elixir 1.17+
- Rust toolchain (for BLE NIFs)

## Author

- Dr. Roy C. Davies
- [roycdavies.github.io](https://roycdavies.github.io/)
