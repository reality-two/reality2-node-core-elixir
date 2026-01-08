# WiFi Mesh GraphQL Architecture

## Overview

WiFi mesh uses **GraphQL** (same as port 4005) for transient peer-to-peer networks.

**IMPORTANT:** GraphQL in Reality2 is designed to **always expose public information only**,
regardless of which port is used. The privacy model is baked into the GraphQL schema itself.

## Key Principles

### 1. IPUC Model - Sentant Design Foundation ✅

Sentants follow the **IPUC model**, which fundamentally shapes the Reality2 architecture:

- **Immutable** - Once a Sentant exists, its definition cannot be changed
- **Persistent** - Sentants persist across restarts and system changes
- **Unique** - Each Sentant has a globally unique identifier (UUID)
- **Consistent** - Same view of a Sentant from any interface or protocol

**Immutability and Plugins:**
- Sentants are **immutable definitions**, not mutable data structures
- A Sentant's interface (events, signals) is fixed at creation
- Sentants CANNOT be "modified" or "updated" after creation
- Sentants CAN interact with mutable data through **plugins**
- You can only **create** or **delete** a Sentant, never change it

This immutability is why the opaque design works so well - you're exposing an
unchanging, consistent public interface.

### 2. GraphQL Consistency ✅

WiFi mesh GraphQL (port 8080) uses the **same schema and resolvers** as the main API (port 4005):
- `sentantAll` query
- `sentantSend` mutation
- `awaitSignal` subscription (future)

**Implementation:** Calls `Absinthe.run()` with `Reality2Web.Schema`

### 3. Opaque Design - Privacy-First ✅

**Sentants are designed to be opaque** - they expose their public interface but hide
their internal implementation. This is a fundamental design principle of Reality2.

This opacity follows naturally from the IPUC model: since Sentants are immutable
definitions, what you expose is a consistent, unchanging public interface.

**Public Information Only** - GraphQL exposes only the public API surface:
- ✅ Sentant ID (for addressing)
- ✅ Sentant name (human-readable identifier)
- ✅ Event names (commands that can be sent)
- ✅ Signal names (notifications that can be received)

**Private Information Never Exposed:**
- ❌ Sentant state/data (current values)
- ❌ Event parameters/descriptions (implementation details)
- ❌ Signal parameters/descriptions (implementation details)
- ❌ Full definitions (internal schemas)
- ❌ User information (ownership, permissions)

This is true for **both port 4005 and port 8080** - the privacy model is universal.

## Port Differences

The difference between ports is **not privacy** (both are public-only), but **write capabilities**:

### Port 4005: Main GraphQL API

```
User/App → HTTP/HTTPS (4005) → GraphQL → Public Sentant Data
           Can create/delete Sentants ✓ (if node allows)
           Can query Sentants ✓
           Can send events ✓
           Public information only ✓
```

**Use cases:**
- Web browser control
- Android app
- Administrative operations (create/delete Sentants)
- Sentant queries and commands

**Sentant Lifecycle Control:**
- If node is "open" (env variable): Can create/delete Sentants dynamically
- If node is "closed": Sentants are startup-only, read-only access

### Port 8080: WiFi Mesh GraphQL

```
Peer Node → HTTP (8080) → GraphQL → Public Sentant Data
            No auth (mesh is trusted)
            CANNOT create/delete Sentants ✗
            Can query Sentants ✓
            Can send events ✓
            Public information only ✓
```

**Use cases:**
- Transient peer-to-peer
- Wearable device discovery
- Ad-hoc mesh networks
- Public API surface exchange

**Read-Only for Sentant Lifecycle:**
- Can query existing Sentants
- Can send events to Sentants
- **Cannot** create or delete Sentants (regardless of node configuration)

## Example Queries

### sentantAll Query

**Request (from peer):**
```graphql
query {
  sentantAll {
    id
    name
    events
    signals
  }
}
```

**Response (filtered):**
```json
{
  "data": {
    "sentantAll": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "temperature_sensor",
        "events": ["read", "calibrate"],
        "signals": ["temperature_changed"]
      },
      {
        "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        "name": "motion_detector",
        "events": ["arm", "disarm", "reset"],
        "signals": ["motion_detected", "motion_stopped"]
      }
    ]
  }
}
```

**What's filtered out:**
- Event parameters (e.g., `read(unit: String)`)
- Event descriptions
- Signal parameters (e.g., `temperature_changed(value: Float)`)
- Signal descriptions
- Sentant state
- Full definition structure

### sentantSend Mutation

**Request (from peer):**
```graphql
mutation {
  sentantSend(
    id: "550e8400-e29b-41d4-a716-446655440000"
    event: "read"
    parameters: "{\"unit\":\"celsius\"}"
  ) {
    id
    name
  }
}
```

**Response (filtered):**
```json
{
  "data": {
    "sentantSend": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "temperature_sensor"
    }
  }
}
```

**What's filtered out:**
- Full Sentant definition
- State after event
- Internal parameters

## Privacy Model Rationale

### Why Opaque Design?

**Sentants are designed to be opaque by default**, exposing only their public capabilities.
This is not just a feature for transient networks - it's a fundamental design principle
of Reality2 that applies universally (both port 4005 and 8080).

**Benefits of opacity:**
- ✅ **Encapsulation** - Internal state is hidden, only behavior is exposed
- ✅ **Privacy** - No accidental leakage of sensitive data
- ✅ **Security** - Smaller attack surface (can't probe internals)
- ✅ **Flexibility** - Implementation can change without breaking API

**For transient networks, opacity is especially critical:**

```
Your wearable ←→ Random person's wearable
    (WiFi mesh - strangers meeting)
```

You want to:
- ✅ Discover what capabilities they have
- ✅ Send public events to their Sentants
- ✅ Know what signals they might emit

You DON'T want to:
- ❌ Expose your private data
- ❌ Reveal your internal state
- ❌ Show sensitive configurations
- ❌ Leak user information

The opaque design makes this safe by default.

### Security Model

**WiFi mesh = Trusted transport layer**
- Same mesh ID = Same group/organization
- Negotiated via BLE beforehand
- Analogous to "same WiFi network"

**But nodes within mesh = Semi-trusted**
- Can send events (public API)
- Cannot read state (private data)
- Cannot see parameters (implementation details)

## Implementation Details

### Server Side (wifi_server.ex)

```elixir
# POST /graphql endpoint
post "/graphql" do
  query = conn.body_params["query"]
  variables = conn.body_params["variables"]

  # Execute using existing Reality2 GraphQL schema
  # The schema itself is designed to return only public information
  {:ok, result} = Absinthe.run(query, Reality2Web.Schema, variables: variables)

  # Additional filtering as a safety measure
  # (The schema already returns public-only data, this ensures it)
  filtered = filter_private_data(result.data)

  send_json_response(conn, 200, %{data: filtered})
end

# Filter to only public fields (safety measure)
defp filter_private_data(%{"sentantAll" => sentants}) do
  %{"sentantAll" => Enum.map(sentants, fn sentant ->
    sentant
    |> Map.take(["id", "name", "events", "signals"])
    |> extract_names_only()
  end)}
end
```

**Key points:**
1. Uses `Absinthe.run()` with existing `Reality2Web.Schema`
2. Ensures consistency with main GraphQL API (port 4005)
3. **Same schema** used on both ports - opaque design is universal
4. Post-filtering is a safety measure (schema already returns public-only data)
5. Only returns: id, name, events (names only), signals (names only)

### Client Side (wifi_server.ex)

```elixir
# Query remote peer's sentants
def query_peer_sentants(peer_ipv6, port \\ 8080) do
  url = "http://[#{peer_ipv6}]:#{port}/graphql"

  query = """
  query {
    sentantAll {
      id
      name
      events
      signals
    }
  }
  """

  HTTPoison.post(url, Jason.encode!(%{query: query}), ...)
end

# Send command to remote sentant
def send_to_peer(peer_ipv6, sentant_id, event, parameters) do
  url = "http://[#{peer_ipv6}]:#{port}/graphql"

  query = """
  mutation($id: ID!, $event: String!, $parameters: String) {
    sentantSend(id: $id, event: $event, parameters: $parameters) {
      id
      name
    }
  }
  """

  variables = %{id: sentant_id, event: event, parameters: Jason.encode!(parameters)}

  HTTPoison.post(url, Jason.encode!(%{query: query, variables: variables}), ...)
end
```

## Complete Flow: Peer Discovery and Query

```
┌─────────────────────────────────────────────────────────┐
│ Step 1: BLE Discovery (Always On, Low Power)            │
│                                                          │
│ Wearable A ───── BLE Beacon ────→ Wearable B            │
│            (node_id, rssi)                               │
│                                                          │
│ Wearable B ← GATT: Node Info ─── Wearable A             │
│ Wearable B ← GATT: Mesh Details ─ Wearable A            │
│            (mesh_id, ipv6, port)                         │
└─────────────────────────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Step 2: WiFi Mesh Formation (On-Demand)                 │
│                                                          │
│ Both: iw dev mesh0 mesh join "R2MESH" freq 2437        │
│ [Automatic HWMP routing, IPv6 link-local]               │
│                                                          │
│ Wearable A: fe80::aaaa                                  │
│ Wearable B: fe80::bbbb                                  │
└─────────────────────────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Step 3: GraphQL Query (WiFi Mesh HTTP)                  │
│                                                          │
│ Wearable B → POST http://[fe80::aaaa]:8080/graphql      │
│   query { sentantAll { id name events signals } }       │
│                                                          │
│ Wearable A → Response (filtered public data):           │
│   {                                                      │
│     "sentantAll": [                                      │
│       {                                                  │
│         "id": "...",                                     │
│         "name": "sensor1",                               │
│         "events": ["read", "calibrate"],                 │
│         "signals": ["value_changed"]                     │
│       }                                                  │
│     ]                                                    │
│   }                                                      │
└─────────────────────────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Step 4: Send Events (GraphQL Mutation)                  │
│                                                          │
│ Wearable B → POST http://[fe80::aaaa]:8080/graphql      │
│   mutation {                                             │
│     sentantSend(                                         │
│       id: "...",                                         │
│       event: "read",                                     │
│       parameters: "{\"unit\":\"celsius\"}"               │
│     ) { id name }                                        │
│   }                                                      │
│                                                          │
│ Wearable A executes event, returns public info only     │
└─────────────────────────────────────────────────────────┘
```

## Testing

### Test Local GraphQL Server

```bash
# Test sentantAll query
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "query { sentantAll { id name events signals } }"}'

# Test sentantSend mutation
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($id: ID!, $event: String!, $parameters: String) { sentantSend(id: $id, event: $event, parameters: $parameters) { id name } }",
    "variables": {
      "id": "sentant-uuid",
      "event": "read",
      "parameters": "{\"unit\":\"celsius\"}"
    }
  }'
```

### Test in IEx

```elixir
# Query remote peer (after WiFi mesh formed)
iex> peer_ipv6 = "fe80::1234:5678:90ab:cdef"
iex> {:ok, sentants} = AiReality2Transnet.WifiServer.query_peer_sentants(peer_ipv6)
[
  %{
    "id" => "...",
    "name" => "temperature_sensor",
    "events" => ["read", "calibrate"],
    "signals" => ["temperature_changed"]
  }
]

# Send event to remote sentant
iex> {:ok, result} = AiReality2Transnet.WifiServer.send_to_peer(
  peer_ipv6,
  "sentant-uuid",
  "read",
  %{unit: "celsius"}
)
%{"id" => "sentant-uuid", "name" => "temperature_sensor"}
```

### Verify Privacy Filtering

```elixir
# Query main API (port 4005) - Full data
iex> Absinthe.run("query { sentantAll { id name events { name parameters } } }", Reality2Web.Schema)
{:ok, %{
  data: %{
    "sentantAll" => [
      %{
        "id" => "...",
        "name" => "sensor1",
        "events" => [
          %{
            "name" => "read",
            "parameters" => [%{"name" => "unit", "type" => "String"}]  # ← Full details
          }
        ]
      }
    ]
  }
}}

# Query WiFi mesh (port 8080) - Filtered
iex> WifiServer.query_peer_sentants("fe80::...")
{:ok, [
  %{
    "id" => "...",
    "name" => "sensor1",
    "events" => ["read"]  # ← Just names, no parameters!
  }
]}
```

## Benefits

### 1. Consistency
- Same GraphQL queries work on both APIs
- Developers familiar with main API can use mesh API
- Schema updates automatically apply to both

### 2. Privacy
- Strangers only see public interface
- Cannot inspect internal state
- Cannot see implementation details

### 3. Discoverability
- Peers can discover what events are available
- Can see what signals might be emitted
- Enables dynamic interaction

### 4. Simplicity
- Standard GraphQL protocol
- No custom RPC needed
- Debugging with standard tools (GraphiQL, Insomnia, etc.)

## Comparison with Alternatives

| Approach | Consistency | Privacy | Complexity |
|----------|-------------|---------|------------|
| **GraphQL with filtering** | ✅ Perfect | ✅ Controlled | 😊 Low |
| Separate REST API | ❌ Diverges | ✅ Controlled | 😐 Medium |
| Full GraphQL (no filter) | ✅ Perfect | ❌ Exposed | 😊 Low |
| Custom RPC protocol | ❌ Diverges | ✅ Controlled | 😰 High |

## Security Considerations

### Threat Model

**WiFi Mesh = Semi-Trusted Environment:**
- Same mesh ID implies coordination (via BLE)
- Not open internet, but not fully trusted
- Analogous to corporate WiFi network

**Attacks Prevented:**
- ✅ State inspection (only events exposed)
- ✅ Data exfiltration (no state in responses)
- ✅ Probing internal structure (parameters hidden)

**Attacks NOT Prevented:**
- ⚠️ Event spamming (can send many events)
- ⚠️ Signal enumeration (can see signal names)
- ⚠️ Timing attacks (response times leak info)

**Mitigations:**
- Rate limiting (future enhancement)
- Event validation (already done by Sentants)
- Audit logging (future enhancement)

## Future Enhancements

### 1. WebSocket Subscriptions

```graphql
subscription {
  awaitSignal(id: "sentant-uuid", signal: "temperature_changed") {
    signal
    data  # Filtered to public data only
  }
}
```

**Benefits:**
- Real-time updates over mesh
- Efficient (no polling)
- Matches main API subscriptions

### 2. Field-Level Privacy Control

```elixir
# In Sentant definition
defmodule TemperatureSensor do
  sentant do
    field :internal_calibration, :float, privacy: :private
    field :last_reading, :float, privacy: :public

    event :read, privacy: :public
    event :recalibrate, privacy: :private  # Only via authenticated API
  end
end
```

### 3. Mesh-Specific Schema

```graphql
# WiFi mesh gets a subset schema
type MeshSentant {
  id: ID!
  name: String!
  events: [String!]!  # Names only
  signals: [String!]! # Names only
}

# Main API gets full schema
type Sentant {
  id: ID!
  name: String!
  events: [Event!]!   # Full Event objects with parameters
  signals: [Signal!]! # Full Signal objects with parameters
  # ... many more fields
}
```

## Summary

**WiFi Mesh GraphQL = Same queries, filtered responses**

- ✅ Uses existing GraphQL schema (consistency)
- ✅ Filters responses to public data only (privacy)
- ✅ GraphQL at both layers (simplicity)
- ✅ Suitable for transient peer networks (security)

**Phase 3 of transient networking is now GraphQL, not REST!** 🚀
