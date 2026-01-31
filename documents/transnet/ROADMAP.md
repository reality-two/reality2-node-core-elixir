# Reality2 TransNet Roadmap

## Current Status

TransNet provides multi-transport mesh networking for Reality2 nodes, supporting BLE, WiFi, LoRa, and internet connectivity. Nodes can discover peers, relay events across transports, and form cooperative hives with shared identity.

## Design Principles

- **Transport agnostic** -- the same event model works over any physical link.
- **Decentralised first** -- no single point of failure; cloud is optional.
- **Progressive trust** -- nodes build reputation through observed behaviour.
- **Adaptive** -- routing and relay decisions evolve with changing network conditions.

---

## Phase 1: API Consolidation

Separate the low-level relay path from higher-level hive operations and expose a clean, unified API surface. This gives external tools and future transports a stable integration point.

## Phase 2: Hive Authentication

Gate sensitive hive operations behind cryptographic authentication while keeping public discovery open. Ensures that only authorised members can modify hive state or register as peers.

## Phase 3: Mesh Intelligence

Build an observation and decision layer that tracks transport quality, neighbour reliability, and network density. Nodes use this information to make smarter relay and routing choices in real time.

## Phase 4: Evolutionary Strategies

Replace static relay parameters with strategies that evolve per-node through selection and mutation. Neighbouring nodes share successful strategies so the whole mesh adapts to local conditions.

## Phase 5: Hive-Level Addressing (WFS)

Shift the primary addressing model from individual nodes to hives, so events can target a hive by name regardless of which member node is currently reachable. The Waggle Finding Service resolves names across local, hive, and inter-hive scopes.

## Phase 6: Cloud & Rendezvous Nodes

Enable always-on cloud nodes within hives for store-and-forward delivery and cross-hive rendezvous. Cloud participation is optional and the local mesh continues to function independently.

---

## Future Directions

- **Weaving** -- coordinated multi-hive topologies that self-organise around shared goals.
- **Edge computing** -- distributing computation across mesh nodes closer to sensors and actuators.
