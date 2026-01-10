# Reality2 Transnet Rust NIF

Rust NIF for Bluetooth Low Energy operations using BlueZ via the `bluer` crate.

## Modules

| Module | Purpose |
|--------|---------|
| `beacon` | AltBeacon advertising for node presence |
| `discovery` | BLE scanning and node detection |
| `gatt` | GATT server for bootstrap/coordination |
| `mesh` | BLE Mesh support (future, requires BlueZ 5.47+) |

## Building

Built automatically with `mix compile`. Requires:
- Rust toolchain (rustup)
- BlueZ development headers (`libbluetooth-dev`)
- D-Bus development headers (`libdbus-1-dev`)

## NIF Functions

Exposed via `AiReality2Transnet.Action`:

```elixir
# Adapter discovery
list_adapters(pid)
list_adapters_seq()

# Node discovery
scan_nodes(pid, timeout)
start_watching(pid, company_id, adapter_name, lost_after_ms)
stop_watching(handle)

# AltBeacon
start_broadcast(company_id, uuid, major, minor, rssi, node_name, priority, adapter)
stop_broadcast(handle)

# GATT Server
start_gatt_server(pid, adapter_name)
stop_gatt_server(handle)
gatt_notify(handle, data)
gatt_write_characteristic(handle, char_uuid, data)

# GATT Client
gatt_connect(pid, address, adapter_name)
gatt_read_characteristic(pid, address, char_uuid, adapter_name)
gatt_write_to_device(pid, address, char_uuid, data, adapter_name)

# BLE Mesh (future)
mesh_init(pid, node_uuid, adapter_name)
mesh_publish(handle, dst_address, opcode, payload)
mesh_subscribe(handle, address)
mesh_sentant_address(node_id, sentant_name)
mesh_group_address(group_name)
```

## Cross-Compilation

For ARM targets (e.g., Raspberry Pi):

```bash
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
mix compile
```
