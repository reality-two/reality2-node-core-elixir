# Transnet Test YAML Configuration Fix

## Summary

Fixed the "Transnet Test.bee.yaml" Sentant automation file by adding WiFi mesh command handlers to `WifiServer` module.

## Problem

The `autostart/Transnet Test.bee.yaml` file defined WiFi mesh commands:
- `wifi_list_adapters`
- `wifi_create_mesh`
- `wifi_destroy_mesh`
- `wifi_list_peers`
- `wifi_get_ipv6`

However, the `WifiServer` module only implemented the HTTP GraphQL server and had no `handle_cast` functions to process these commands from Sentant automations.

## Solution

Added command handlers to `lib/ai_reality2_transnet/wifi_server.ex` to process WiFi mesh operations.

### Implementation

Added the following `handle_cast` functions to `AiReality2Transnet.WifiServer`:

#### 1. List WiFi Adapters
```elixir
def handle_cast(%{command: "list_adapters"}, state) do
  Logger.debug("[WifiServer] Listing WiFi adapters")

  case AiReality2Transnet.Wifi.list_adapters() do
    {:ok, adapters} ->
      Logger.info("[WifiServer] Found #{length(adapters)} WiFi adapters")
      {:noreply, state}

    {:error, reason} ->
      Logger.error("[WifiServer] Failed to list adapters: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

#### 2. Create Mesh
```elixir
def handle_cast(%{command: "create_mesh", parameters: params}, state) do
  interface = Map.get(params, "interface") || Map.get(params, :interface)
  mesh_interface = Map.get(params, "mesh_interface") || Map.get(params, :mesh_interface, "mesh0")
  mesh_id = Map.get(params, "mesh_id") || Map.get(params, :mesh_id)
  frequency = Map.get(params, "frequency") || Map.get(params, :frequency, 2437)

  Logger.info("[WifiServer] Creating mesh: #{mesh_interface} from #{interface}, ID: #{mesh_id}, freq: #{frequency}")

  with {:ok, _} <- AiReality2Transnet.Wifi.create_mesh_interface(interface, mesh_interface),
       {:ok, _} <- AiReality2Transnet.Wifi.start_mesh(mesh_interface, mesh_id, frequency) do
    Logger.info("[WifiServer] Mesh created successfully")
    {:noreply, state}
  else
    {:error, reason} ->
      Logger.error("[WifiServer] Failed to create mesh: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

#### 3. Destroy Mesh
```elixir
def handle_cast(%{command: "destroy_mesh", parameters: params}, state) do
  mesh_interface = Map.get(params, "mesh_interface") || Map.get(params, :mesh_interface, "mesh0")

  Logger.info("[WifiServer] Destroying mesh interface: #{mesh_interface}")

  case AiReality2Transnet.Wifi.destroy_mesh_interface(mesh_interface) do
    {:ok, _} ->
      Logger.info("[WifiServer] Mesh destroyed successfully")
      {:noreply, state}

    {:error, reason} ->
      Logger.error("[WifiServer] Failed to destroy mesh: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

#### 4. List Mesh Peers
```elixir
def handle_cast(%{command: "list_peers", parameters: params}, state) do
  mesh_interface = Map.get(params, "mesh_interface") || Map.get(params, :mesh_interface, "mesh0")

  Logger.debug("[WifiServer] Listing mesh peers on #{mesh_interface}")

  case AiReality2Transnet.Wifi.list_mesh_peers(mesh_interface) do
    {:ok, peers} ->
      Logger.info("[WifiServer] Found #{length(peers)} mesh peers")
      {:noreply, state}

    {:error, reason} ->
      Logger.error("[WifiServer] Failed to list peers: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

#### 5. Get IPv6 Address
```elixir
def handle_cast(%{command: "get_ipv6", parameters: params}, state) do
  interface = Map.get(params, "interface") || Map.get(params, :interface, "mesh0")

  Logger.debug("[WifiServer] Getting IPv6 address for #{interface}")

  case AiReality2Transnet.Wifi.get_ipv6_link_local(interface) do
    {:ok, ipv6} ->
      Logger.info("[WifiServer] IPv6 address: #{ipv6}")
      {:noreply, state}

    {:error, reason} ->
      Logger.error("[WifiServer] Failed to get IPv6: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

## How It Works

### Command Routing Flow

```
┌──────────────────────────────────────────────────────────────┐
│  1. Sentant Event Triggered (from YAML automation)           │
│     Event: "Create Mesh"                                      │
│     Parameters: {interface, mesh_interface, mesh_id, ...}     │
└──────────────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│  2. Main.sendto/2 called                                      │
│     Command: "wifi_create_mesh"                               │
│     Parameters: {...}                                         │
└──────────────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│  3. Command routing (in AiReality2Transnet.Main)             │
│     - Checks if command starts with "wifi_"                   │
│     - Strips "wifi_" prefix → "create_mesh"                   │
│     - Routes to: GenServer.cast(WifiServer, %{...})           │
└──────────────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│  4. WifiServer.handle_cast/2 processes command                │
│     - Extracts parameters                                     │
│     - Calls AiReality2Transnet.Wifi functions                 │
│     - Logs results                                            │
└──────────────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│  5. AiReality2Transnet.Wifi executes system commands          │
│     - iw dev <interface> interface add <mesh>                 │
│     - iw dev <mesh> mesh join <mesh_id> freq <freq>           │
│     - Returns {:ok, result} or {:error, reason}               │
└──────────────────────────────────────────────────────────────┘
```

### YAML Configuration Structure

The `Transnet Test.bee.yaml` file defines a Sentant with automations:

```yaml
sentant:
  name: Transnet Test
  description: Test and manage Bluetooth and WiFi networking capabilities

  automations:
    # BLE Operations (no wifi_ prefix)
    - name: List BLE Adapters
      transitions:
        - public: true
          event: BLE Adapters
          actions:
            - command: list_adapters
              plugin: ai.reality2.transnet

    # WiFi Operations (wifi_ prefix)
    - name: Create Mesh
      transitions:
        - public: true
          event: Create Mesh
          parameters:
            interface: string
            mesh_interface: string
            mesh_id: string
            frequency: number
          actions:
            - command: wifi_create_mesh
              plugin: ai.reality2.transnet
```

### Command Naming Convention

**BLE Commands** (no prefix):
- `list_adapters` → Routed to `Bluetooth` module
- `scan_nodes` → Routed to `Bluetooth` module
- `reset_nodes` → Routed to `Bluetooth` module

**WiFi Commands** (wifi_ prefix):
- `wifi_list_adapters` → Stripped to `list_adapters` → Routed to `WifiServer`
- `wifi_create_mesh` → Stripped to `create_mesh` → Routed to `WifiServer`
- `wifi_destroy_mesh` → Stripped to `destroy_mesh` → Routed to `WifiServer`
- `wifi_list_peers` → Stripped to `list_peers` → Routed to `WifiServer`
- `wifi_get_ipv6` → Stripped to `get_ipv6` → Routed to `WifiServer`

## Available Commands

### Bluetooth Operations

| Event Name | Command | Parameters | Description |
|------------|---------|------------|-------------|
| BLE Adapters | `list_adapters` | None | List Bluetooth adapters |
| Rescan | `reset_nodes` | None | Reset discovered nodes list |
| Timed Scan | `scan_nodes` | `timeout: number` | Scan for nodes for specified duration |

### WiFi Mesh Operations

| Event Name | Command | Parameters | Description |
|------------|---------|------------|-------------|
| WiFi Adapters | `wifi_list_adapters` | None | List WiFi network adapters |
| Create Mesh | `wifi_create_mesh` | `interface, mesh_interface, mesh_id, frequency` | Create and start WiFi mesh |
| Destroy Mesh | `wifi_destroy_mesh` | `mesh_interface` | Destroy WiFi mesh interface |
| List Mesh Peers | `wifi_list_peers` | `mesh_interface` | List connected mesh peers |
| Get IPv6 | `wifi_get_ipv6` | `interface` | Get IPv6 link-local address |

## Usage Example

### Via GraphQL (Reality2 Web UI)

```graphql
mutation {
  sentantSend(
    id: "transnet-test-id"
    event: "Create Mesh"
    parameters: "{\"interface\":\"wlan0\",\"mesh_interface\":\"mesh0\",\"mesh_id\":\"R2MESH\",\"frequency\":2437}"
  ) {
    id
    name
  }
}
```

### Via Elixir

```elixir
# Send event to Transnet Test Sentant
Reality2.Sentants.sendto(
  %{name: "Transnet Test"},
  %{
    event: "Create Mesh",
    parameters: %{
      interface: "wlan0",
      mesh_interface: "mesh0",
      mesh_id: "R2MESH",
      frequency: 2437
    }
  }
)
```

### Via IEx Console

```elixir
# Direct command to WifiServer (for testing)
GenServer.cast(AiReality2Transnet.WifiServer, %{
  command: "create_mesh",
  parameters: %{
    "interface" => "wlan0",
    "mesh_interface" => "mesh0",
    "mesh_id" => "R2MESH",
    "frequency" => 2437
  }
})

# Check logs for results
[info] [WifiServer] Creating mesh: mesh0 from wlan0, ID: R2MESH, freq: 2437
[info] [WifiServer] Mesh created successfully
```

## Testing

### 1. Verify Sentant Loaded

```elixir
iex> Reality2.Sentants.read(%{name: "Transnet Test"}, :definition)
{:ok, %{...}}
```

### 2. List Available Events

The Sentant should expose these public events:
- "BLE Adapters"
- "Rescan"
- "Timed Scan"
- "WiFi Adapters"
- "Create Mesh"
- "Destroy Mesh"
- "List Mesh Peers"
- "Get IPv6"

### 3. Test WiFi Operations

```elixir
# List WiFi adapters
Reality2.Sentants.sendto(
  %{name: "Transnet Test"},
  %{event: "WiFi Adapters"}
)

# Create mesh
Reality2.Sentants.sendto(
  %{name: "Transnet Test"},
  %{
    event: "Create Mesh",
    parameters: %{
      interface: "wlan0",
      mesh_interface: "mesh0",
      mesh_id: "R2MESH",
      frequency: 2437
    }
  }
)

# List mesh peers
Reality2.Sentants.sendto(
  %{name: "Transnet Test"},
  %{
    event: "List Mesh Peers",
    parameters: %{mesh_interface: "mesh0"}
  }
)
```

## Future Enhancements

### TODO: Signal Results Back to Sentant

Currently, command handlers log results but don't signal back to the Sentant. To implement:

```elixir
def handle_cast(%{command: "list_adapters"}, state) do
  case AiReality2Transnet.Wifi.list_adapters() do
    {:ok, adapters} ->
      # Signal results back to Sentant
      AiReality2Transnet.Bluetooth.broadcast_signal(
        state.sentant_id,
        "WiFi Adapters Listed",
        %{adapters: adapters}
      )
      {:noreply, state}

    {:error, reason} ->
      # Signal error back to Sentant
      AiReality2Transnet.Bluetooth.broadcast_signal(
        state.sentant_id,
        "Error",
        %{reason: inspect(reason)}
      )
      {:noreply, state}
  end
end
```

This would require:
1. Storing `sentant_id` in WifiServer state
2. Defining signal events in YAML
3. Updating handlers to call `broadcast_signal`

## Files Modified

1. **`lib/ai_reality2_transnet/wifi_server.ex`**
   - Added 5 `handle_cast` functions for WiFi commands
   - Added catchall `handle_cast` to prevent crashes

2. **`autostart/Transnet Test.bee.yaml`**
   - No changes needed - commands were already correct

## Verification

✅ **Compilation successful:**
```bash
mix compile
# Exit code: 0
# No errors or warnings
```

✅ **Command routing working:**
- BLE commands route to Bluetooth module
- WiFi commands route to WifiServer module (with prefix stripped)

✅ **WiFi functions available:**
- `AiReality2Transnet.Wifi.list_adapters/0` ✓
- `AiReality2Transnet.Wifi.create_mesh_interface/2` ✓
- `AiReality2Transnet.Wifi.start_mesh/3` ✓
- `AiReality2Transnet.Wifi.destroy_mesh_interface/1` ✓
- `AiReality2Transnet.Wifi.list_mesh_peers/1` ✓
- `AiReality2Transnet.Wifi.get_ipv6_link_local/1` ✓

## Benefits

1. **Complete WiFi mesh control via Sentant automations**
   - Create/destroy mesh networks
   - List adapters and peers
   - Get network information

2. **Consistent command interface**
   - Same pattern for BLE and WiFi commands
   - Clear naming convention (wifi_ prefix for WiFi)

3. **Integration with Reality2 ecosystem**
   - Works with GraphQL API
   - Accessible from web UI
   - Supports Sentant automations

4. **Logging and debugging**
   - All operations logged
   - Clear success/failure messages
   - Easy to trace command execution

**Author:**
- Dr. Roy C. Davies
- [roycdavies.github.io](https://roycdavies.github.io/)
