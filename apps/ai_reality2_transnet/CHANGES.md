# Transient Network Changelog

## Current Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for complete documentation.

## Version History

### v0.1.13 (Current)

**Multi-Transport Mesh Architecture**

- Added R2Mesh - simple BLE relay protocol (works on any BlueZ)
- Added LoRaMesh - optional long-range support via USB dongle
- Added WiFi hotspot with hosting priority system
- Added ConnectionManager for hotspot/client management
- Added ConnectionAssessor for connection quality monitoring
- BLE Mesh code ready for future BlueZ 5.47+ support
- Thread/Matter integration planned (see ARCHITECTURE.md)

**Transport Summary:**
| Transport | Status | Range | Payload |
|-----------|--------|-------|---------|
| R2Mesh (BLE) | Ready | ~10m | ~24 bytes |
| WiFi Hotspot | Ready | ~100m | Unlimited |
| LoRa Mesh | Ready | ~15km | ~200 bytes |
| BLE Mesh | Future | ~30m | ~380 bytes |
| Thread/Matter | Future | ~30m | Smart home |

### v0.1.12

- Initial BLE beacon and GATT server
- WiFi mesh concept (802.11s)
- Basic peer discovery

### v0.1.11

- Rust NIF for BlueZ integration
- AltBeacon broadcasting
- Node presence detection

## Removed/Deprecated

- `WifiServer` - Replaced by ConnectionManager + Reality2Web GraphQL
- `TransportManager` - Replaced by ConnectionAssessor
- 802.11s WiFi mesh - Replaced by hotspot architecture
- GATT-based Sentant queries - Now uses HTTP/GraphQL over WiFi
