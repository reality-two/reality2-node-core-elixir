# Architecture Corrections - GraphQL Privacy Model & IPUC

## Summary

Important architectural corrections to the Reality2 GraphQL documentation based on user clarifications.

This document covers two major corrections:
1. **Privacy Model** - Opaque design is universal, not port-specific
2. **IPUC Model** - Sentants are immutable definitions, not mutable data structures

## Previous (Incorrect) Understanding

The documentation incorrectly stated that:

- **Port 4005**: Authenticated, **full Sentant data** (state, parameters, everything)
- **Port 8080**: Public only, **filtered** to interface (name, events, signals)

This was **WRONG**. The privacy filtering was described as specific to port 8080 (WiFi mesh), when in reality it's a universal design principle.

## Correct Understanding

### Key Principle: Sentants Are Opaque

**Sentants are designed to be opaque** - they expose their public interface (capabilities) but hide their internal implementation (state, parameters, definitions).

This is a **fundamental design principle** of Reality2, not just a feature for transient networks.

### GraphQL Privacy Model (Universal)

**GraphQL is designed to ONLY expose public information**, regardless of which port is used:

#### ✅ Public Information Exposed (Both Ports)
- **Sentant ID** - UUID for addressing
- **Sentant Name** - Human-readable identifier
- **Event Names** - Commands that can be sent (names only, no parameters)
- **Signal Names** - Notifications that can be received (names only, no parameters)

#### ❌ Private Information Never Exposed (Both Ports)
- **Sentant State** - Current values, internal data
- **Event Parameters** - Implementation details, types, descriptions
- **Signal Parameters** - Implementation details, types, descriptions
- **Full Definitions** - Complete schemas, internal structure
- **User Information** - Ownership, permissions, metadata

### Actual Difference Between Ports

The difference is **NOT privacy** (both are public-only), but **write capabilities**:

#### Port 4005: Main GraphQL API

**Capabilities:**
- ✅ Query Sentants (read-only)
- ✅ Send events to Sentants
- ✅ **Create/delete Sentants** (if node allows it via environment variable)

**Sentant Lifecycle Control:**
- If node is "open" (env variable): Can create/delete Sentants dynamically via GraphQL
- If node is "closed": Sentants are startup-only, read-only access

**Privacy:** Public information only (opaque design)

#### Port 8080: WiFi Mesh GraphQL API

**Capabilities:**
- ✅ Query Sentants (read-only)
- ✅ Send events to Sentants
- ❌ **Cannot create/delete Sentants** (regardless of node configuration)

**Read-Only for Lifecycle:**
- Port 8080 never allows Sentant creation/deletion
- Transient peers have read-only access to Sentant lifecycle

**Privacy:** Public information only (opaque design)

## Benefits of Opaque Design

1. **Encapsulation** - Internal state is hidden, only behavior is exposed
2. **Privacy** - No accidental leakage of sensitive data
3. **Security** - Smaller attack surface (can't probe internals)
4. **Flexibility** - Implementation can change without breaking API
5. **Safe Transient Networks** - Strangers can interact with capabilities without data leakage

## Implementation Notes

### GraphQL Schema

The `Reality2Web.Schema` is **the same** on both ports:
- Designed to return only public information
- No separate "filtered" vs "full" schema
- Opaque design is baked into the schema itself

### Additional Filtering (Safety Measure)

Port 8080 includes post-processing filtering as a **safety measure**:

```elixir
# Execute using existing Reality2 GraphQL schema
# The schema itself is designed to return only public information
{:ok, result} = Absinthe.run(query, Reality2Web.Schema, variables: variables)

# Additional filtering as a safety measure
# (The schema already returns public-only data, this ensures it)
filtered = filter_private_data(result.data)
```

This is defense-in-depth, not the primary privacy mechanism.

## Sentant Lifecycle

Sentants can be created/deleted in two ways:

1. **At Startup** - Sentants loaded from configuration
   - Always available
   - Works on both "open" and "closed" nodes

2. **Dynamically via Port 4005** - If environment variable permits
   - Node is "open": Sentants can be created/deleted via GraphQL
   - Node is "closed": Sentants are startup-only, no dynamic changes
   - **Port 8080 never allows this**, regardless of configuration

## Files Updated

The following documentation files have been corrected:

1. **`wifi_server.ex`** - Module documentation
   - Updated port comparison section
   - Added "Sentants Are Opaque" section
   - Clarified Sentant lifecycle control
   - Emphasized privacy model is universal

2. **`WIFI_MESH_GRAPHQL.md`** - Architecture documentation
   - Updated overview to emphasize universal privacy
   - Corrected port comparison section
   - Added "Opaque Design" principle
   - Clarified implementation details
   - Updated rationale section

## Key Takeaways

1. **Opaque design is universal** - Not just for WiFi mesh, but for all GraphQL access
2. **Both ports expose public-only data** - Privacy model is the same
3. **Port difference is write capabilities** - Only port 4005 can create/delete Sentants
4. **Environment variable controls creation** - "Open" vs "closed" nodes
5. **Port 8080 is always read-only for lifecycle** - Transient peers can't create Sentants

## Terminology

**Correct terminology going forward:**

- ✅ "Sentants are opaque"
- ✅ "Public information only" (applies to both ports)
- ✅ "Port 8080 is read-only for Sentant lifecycle"
- ✅ "Port 4005 can create/delete Sentants (if node allows)"

**Avoid these incorrect phrases:**

- ❌ "Port 4005 has full Sentant data"
- ❌ "Port 8080 filters private data" (implies port 4005 doesn't)
- ❌ "Privacy filtering for transient networks" (implies it's specific to mesh)

---

## Correction 2: IPUC Model - Sentants Are Immutable

### User Clarification

> "The core features of Sentants are: IPUC - Immutable, Persistent, Unique (in the world),
> Consistent (view from any interface). This means, therefore, that once a Sentant exists,
> it cannot be changed (though it can make changes to data via plugins)."

### What Was Missing

The previous documentation didn't explain that Sentants are **immutable definitions**.
This is a fundamental architectural principle that explains many design decisions.

### Correct Understanding: IPUC Model

**IPUC** defines the core properties of Sentants:

#### I - Immutable
- **Once a Sentant exists, its definition cannot be changed**
- The interface (events, signals) is fixed at creation
- No "update" or "modify" operations exist
- You can only **create** or **delete** a Sentant, never change it

#### P - Persistent
- Sentants persist across restarts and system changes
- Loaded at startup from configuration
- Optionally created dynamically (if node allows)

#### U - Unique
- Each Sentant has a globally unique identifier (UUID)
- No two Sentants in the world share the same ID
- Enables unambiguous addressing across all networks

#### C - Consistent
- Same view of a Sentant from any interface or protocol
- BLE, WiFi mesh, GraphQL, WebSocket - all show identical information
- Universal privacy model (opaque design) ensures consistency

### Immutability vs Mutability

**Sentants are immutable**, but they can interact with mutable data:

```
┌─────────────────────────────────────────┐
│         Sentant (Immutable)              │
│  - Fixed interface (events, signals)     │
│  - Cannot be modified after creation     │
│  - Opaque to external observers          │
└─────────────────────────────────────────┘
                  │
                  │ uses
                  ↓
┌─────────────────────────────────────────┐
│         Plugin (Mutable Data)            │
│  - Read/write external state             │
│  - Database, files, sensors, etc.        │
│  - Sentant remains unchanged             │
└─────────────────────────────────────────┘
```

**Key insight:** Sentants are like **immutable functions**, not mutable objects.
They define behavior (what events they handle), not state (what data they hold).

### Why This Matters

1. **Opaque design makes sense** - You're exposing an immutable interface, not hiding mutable state
2. **No "update Sentant" operation** - Immutability means only create/delete, never modify
3. **Consistency across protocols** - Immutable definitions are naturally consistent
4. **Simplifies lifecycle management** - No versioning, no migrations, no updates

### Files Updated

The following documentation files have been updated to include IPUC model:

1. **`wifi_server.ex`** - Module documentation
   - Added "Sentant Design Principles: IPUC" section
   - Explained immutability and plugin relationship
   - Connected IPUC to opaque design principle

2. **`WIFI_MESH_GRAPHQL.md`** - Architecture documentation
   - Added IPUC model as first key principle
   - Explained why immutability enables opaque design
   - Clarified create/delete-only lifecycle

3. **`ARCHITECTURE_CORRECTIONS.md`** - This file
   - Documented IPUC model as second major correction

## Terminology Update

**Correct terminology going forward:**

- ✅ "Sentants follow the IPUC model"
- ✅ "Sentants are immutable definitions"
- ✅ "Sentants can only be created or deleted, not modified"
- ✅ "Plugins allow Sentants to interact with mutable data"
- ✅ "Consistent view across all interfaces"

**Avoid these incorrect phrases:**

- ❌ "Update a Sentant" (Sentants can't be updated)
- ❌ "Modify Sentant state" (Sentants don't have mutable state)
- ❌ "Change Sentant definition" (definitions are immutable)

## Conclusion

The Reality2 architecture is more elegant and principled than initially documented:

### Correction 1: Privacy Model
- **One schema**, not two (public vs full)
- **One privacy model**, not two (opaque by design)
- **One difference**: Write capabilities (create/delete Sentants)

### Correction 2: IPUC Model
- **Immutable definitions**, not mutable objects
- **Create/delete lifecycle**, not create/update/delete
- **Consistent interface**, across all protocols
- **Plugin-based mutability**, Sentants remain immutable

### Benefits

Understanding these principles makes the system:
- **Simpler** - Fewer concepts, clearer boundaries
- **More secure** - Immutability prevents many classes of bugs
- **More maintainable** - Consistent model across all interfaces
- **More elegant** - Design principles align naturally
