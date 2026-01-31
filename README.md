# Reality2

Reality2 is a distributed platform for sentient digital agents. Agents — called **Sentants** — are aware of the network and physical environment they inhabit. Groups of Sentants form **Swarms**, and the devices that host them form **Hives** that cooperate across wireless and internet links.

Users interact with Sentants directly through a GraphQL API. The focus is at the agent level, not the device level.

## Key Features

- **GraphQL API** — queries, mutations and subscriptions for controlling Sentants and listening for signals
- **Plugin architecture** — extend Sentant capabilities with inbuilt (Elixir/Rust) or external (HTTP API) plugins
- **Multi-transport mesh** — nodes discover and communicate over BLE, WiFi, LoRa and the internet via TransNet
- **Hive identity** — nodes that share a cryptographic identity form a Hive and cooperate automatically
- **Waggle Finding Service (WFS)** — locate and route events to Sentants anywhere in the mesh
- **Visual programming** — build Sentant definitions with a Blockly-based construct mode
- **Geospatial awareness** — locate Sentants in the physical world with geohashing and proximity search
- **XR support** — 3D and extended-reality visualisation via Three.js and WebXR

## Quick Start

### Prerequisites

- Elixir ~1.16+ and Erlang/OTP
- PostgreSQL
- Node.js (for building the web front-end)

### Clone and run

```bash
git clone https://github.com/reality-two/reality2-node-core-elixir.git
cd reality2-node-core-elixir
cd scripts
./run_as_dev
```

The `run_as_dev` script fetches dependencies, compiles the project, and starts an interactive Elixir shell with the Phoenix server. The node will be available at `https://localhost:4001`.

To generate fresh SSL certificates, use the script in the `cert` folder. For a named server, create certificates through your provider in the usual way.

## Project Structure

This is an Elixir umbrella project. The main applications are:

| Application | Description |
|-------------|-------------|
| **reality2** | Core Sentant platform — lifecycle, automations, plugin system |
| **reality2_web** | Phoenix web server, GraphQL API, WebSocket subscriptions |
| **ai_reality2_transnet** | Multi-transport mesh networking (BLE, WiFi, LoRa, Internet) |
| **ai_reality2_wfs** | Waggle Finding Service — cross-node Sentant addressing and routing |
| **ai_reality2_vars** | In-memory variable storage plugin |
| **ai_reality2_geospatial** | Geolocation and proximity search plugin |
| **ai_reality2_backup** | Persistent database storage plugin |
| **ai_reality2_auth** | Authentication and identity management plugin |
| **ai_reality2_versioncontrol** | Version tracking for Sentant definitions |
| **ai_reality2_rustdemo** | Demonstration of Rust-based plugins via Rustler |
| **com_raspberrypi_api** | Raspberry Pi sensor and GPIO integration |

Plugins are loaded selectively via the `PLUGINS` environment variable — see `scripts/run_as_dev` for the default set.

## Sentant Definitions

Sentants are defined in YAML, JSON or TOML files describing their automations, plugins and data. Place definitions in the `autostart/` folder to load them when the node starts, or load them at any time through the GraphQL API.

Example definitions and a Python client library are available in the [reality2-definitions](https://github.com/reality-two/reality2-definitions) repository.

## Web Interfaces

The `web/` folder contains several front-end applications:

- **sentants/** — the main Sentant dashboard, built with Svelte, including Blockly visual programming and map visualisation
- **iotdemo/** — IoT demonstration interface
- **lora-mesh-viz/** — LoRa mesh network topology visualiser
- **transnet-viz/** — TransNet network visualiser

To rebuild the web front-end: `./scripts/build_webapp`

## Documentation

Full documentation — getting started guides, definition formats, GraphQL reference, plugin details, and client libraries — is in the [reality2-documentation](https://github.com/reality-two/reality2-documentation) repository.

## License

See [LICENSE](LICENSE) for details.
