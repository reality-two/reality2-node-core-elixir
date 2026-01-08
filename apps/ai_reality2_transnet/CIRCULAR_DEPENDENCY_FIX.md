# Circular Dependency Fix - Transnet & PNS

## Problem

When attempting to run the application, encountered a circular dependency error:

```
** (Mix) Could not sort dependencies. The following dependencies form a cycle:
ai_reality2_pns, ai_reality2_transnet, uuid
```

## Root Cause

The dependency graph had a cycle:

```
ai_reality2_transnet → ai_reality2_pns → ai_reality2_transnet
```

Specifically:
1. `ai_reality2_transnet/mix.exs` depended on `{:ai_reality2_pns, in_umbrella: true}`
2. `ai_reality2_pns/mix.exs` depended on `{:ai_reality2_transnet, in_umbrella: true}`

This created an unresolvable circular dependency.

## Architectural Analysis

### What is PNS?
**Pathing Name System (PNS)** - Location-transparent routing for Sentants
- High-level abstraction over transport layers
- Routes events to Sentants regardless of location (local, BLE, WiFi mesh, GraphQL)
- Uses transnet's peer discovery to build routing tables

### What is Transnet?
**Transient Networks (Transnet)** - Low-level peer-to-peer transport
- BLE discovery (always-on, low power)
- WiFi mesh networking (on-demand, high bandwidth)
- Peer management and topology tracking

### Correct Layering

```
┌────────────────────────────────────────┐
│         Application Layer              │
│  - Sentant events, signals             │
│  - User interactions                   │
└────────────────────────────────────────┘
                 ↓ uses
┌────────────────────────────────────────┐
│   AiReality2Pns (PNS Router)           │  ← HIGH-LEVEL ROUTING
│  - Location-transparent addressing     │
│  - Automatic local vs remote detection │
│  - Broadcast support                   │
│  - Uses transnet for peer info         │
└────────────────────────────────────────┘
                 ↓ depends on (compile-time)
┌────────────────────────────────────────┐
│   AiReality2Transnet                   │  ← LOW-LEVEL TRANSPORT
│  - BLE beacon & discovery              │
│  - WiFi mesh interface management      │
│  - Peer lifecycle management           │
│  - Optionally notifies PNS (runtime)   │
└────────────────────────────────────────┘
```

**Key principle:** Low-level should not depend on high-level.

## Solution

### Option 1: Remove Compile-Time Dependency ✅ (Chosen)

**Approach:**
- Remove `{:ai_reality2_pns, in_umbrella: true}` from `ai_reality2_transnet/mix.exs`
- Use runtime checks (`Code.ensure_loaded?/1`) in transnet code
- PNS continues to depend on transnet (correct layering)

**Implementation:**

In `apps/ai_reality2_transnet/mix.exs`:
```elixir
defp deps do
  [
    {:reality2, in_umbrella: true},
    # Note: ai_reality2_pns is NOT a compile-time dependency
    # PNS integration uses runtime checks (Code.ensure_loaded?)
    # This prevents circular dependency (PNS depends on transnet)
    {:rustler, "~> 0.34.0"},
    {:plug_cowboy, "~> 2.0"},
    {:httpoison, "~> 2.0"}
  ]
end
```

In `apps/ai_reality2_transnet/lib/ai_reality2_transnet/peer_manager.ex`:
```elixir
# Notify PNS Router of topology change (if available)
if Code.ensure_loaded?(AiReality2Pns.Router) do
  AiReality2Pns.Router.refresh_topology()
end
```

**Advantages:**
- ✅ Clean architectural layering (low → high)
- ✅ Transnet works independently of PNS
- ✅ PNS can use full transnet API
- ✅ Optional integration (PNS is a plugin)

**Disadvantages:**
- ⚠️ Compile-time warnings about undefined functions (benign)

### Option 2: Event-Based Decoupling (Alternative, Not Used)

**Approach:**
- Remove both compile-time dependencies
- Use Phoenix.PubSub for communication
- Both modules publish/subscribe to events

**Why Not Chosen:**
- More complex (event bus overhead)
- Harder to debug (indirect communication)
- PNS needs direct access to transnet API (peer list, sentant info)
- Runtime checks are simpler and clearer

## Implementation Details

### Transnet → PNS (Optional Notification)

Transnet optionally notifies PNS when peers change:

```elixir
# In peer_manager.ex - when new peer discovered
if Code.ensure_loaded?(AiReality2Pns.Router) do
  AiReality2Pns.Router.refresh_topology()
end
```

**Files using runtime checks:**
- `lib/ai_reality2_transnet/peer_manager.ex` (lines 248, 312, 363)
- `lib/ai_reality2_transnet/transient_network_test.ex` (lines 71, 260)

### PNS → Transnet (Direct Dependency)

PNS has full compile-time access to transnet:

```elixir
# In ai_reality2_pns/lib/ai_reality2_pns/router.ex
defp send_to_remote_gatt(node_id, sentant_id, event, parameters, passthrough) do
  with true <- Code.ensure_loaded?(AiReality2Transnet.PeerManager),
       true <- Code.ensure_loaded?(AiReality2Transnet.WifiServer),
       {:ok, peer} <- AiReality2Transnet.PeerManager.get_peer(node_id) do
    # Use WiFi mesh or BLE for routing
    case peer.transport do
      :wifi_mesh -> send_via_wifi_mesh(peer, sentant_id, event, parameters)
      :ble_gatt -> {:error, :ble_discovery_only}
    end
  end
end
```

**Note:** PNS still uses runtime checks as defensive programming, but has compile-time dependency.

## Compilation Warnings

### Expected Warnings (Now Suppressed)

Previously, when compiling `ai_reality2_transnet`, you would see:

```
warning: AiReality2Pns.Router.refresh_topology/0 is undefined
  (module AiReality2Pns.Router is not available or is yet to be defined)
```

**Why this happens:**
- Elixir's compiler sees the function call but can't find the module
- Module is checked at runtime with `Code.ensure_loaded?/1`
- Warning is safe to ignore (runtime checks handle missing module)

**How we suppressed them:**
Added `@compile` directives in each file that uses runtime-optional modules:

```elixir
# In peer_manager.ex
@compile {:no_warn_undefined, AiReality2Pns.Router}

# In transient_network_test.ex
@compile {:no_warn_undefined, [AiReality2Pns.Router, AiReality2Pns]}

# In wifi_server.ex
@compile {:no_warn_undefined, [Absinthe, Reality2Web.Schema]}
```

**Why this approach:**
- ✅ Precise - Only suppresses warnings for specific modules in specific files
- ✅ Documented - Comments explain why each module is optional
- ✅ Maintainable - Clear what dependencies are runtime-optional
- ✅ Clean compilation - No warning clutter masks real issues

## Verification

### Test Successful Compilation

```bash
# Clean build
mix clean
mix deps.get
mix compile

# Should succeed with exit code 0
# No circular dependency error
```

### Test Runtime Integration

```elixir
# Start both apps
iex -S mix

# Check PNS Router is available
Code.ensure_loaded?(AiReality2Pns.Router)
#=> {:module, AiReality2Pns.Router}

# Check transnet can optionally notify PNS
if Code.ensure_loaded?(AiReality2Pns.Router) do
  AiReality2Pns.Router.refresh_topology()
  IO.puts("PNS notified successfully")
end
```

## Benefits of This Approach

1. **Architectural Correctness**
   - Low-level (transnet) doesn't depend on high-level (PNS)
   - Proper separation of concerns
   - Clear dependency flow

2. **Optional Integration**
   - Transnet works standalone
   - PNS is a plugin that enhances transnet
   - System is modular and composable

3. **Simplicity**
   - Runtime checks are straightforward
   - No event bus complexity
   - Easy to understand and debug

4. **Flexibility**
   - PNS can be added/removed without breaking transnet
   - Other high-level routers could be built on transnet
   - Clean extension point

## Lessons Learned

### Circular Dependencies in Umbrella Apps

**Problem indicators:**
- Two apps depend on each other
- "Could not sort dependencies" error
- Cycle in dependency graph

**Solution patterns:**
1. **Runtime checks** - Use `Code.ensure_loaded?/1` for optional integration
2. **Event-based** - PubSub for decoupling (if truly needed)
3. **Shared abstraction** - Extract common interface to separate app
4. **Rethink architecture** - Usually indicates design issue

**Best practice:**
- Low-level modules should NOT depend on high-level modules
- Use dependency inversion when needed
- Runtime checks are OK for optional features

### When to Use Runtime Checks

✅ **Good for:**
- Optional integrations (plugins, extensions)
- High-level features that low-level can notify
- Breaking circular dependencies
- Feature flags and conditional compilation

❌ **Avoid for:**
- Core functionality dependencies
- Type safety requirements
- When compile-time verification is needed
- Protocol/behaviour implementations

## Conclusion

The circular dependency between `ai_reality2_transnet` and `ai_reality2_pns` has been resolved by:

1. Removing compile-time dependency from transnet → PNS
2. Using runtime checks (`Code.ensure_loaded?/1`) for optional integration
3. Keeping compile-time dependency from PNS → transnet (correct layering)

This results in a clean architectural separation where:
- Transnet (low-level transport) works independently
- PNS (high-level routing) builds on top of transnet
- Integration is optional and verified at runtime

**Status:** ✅ Resolved - Compiles successfully without circular dependency error

**Author:**
- Dr. Roy C. Davies
- [roycdavies.github.io](https://roycdavies.github.io/)
