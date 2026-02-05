// Terminology mapping for Standard/Advanced mode
// Standard mode uses friendly bee-themed terms, Advanced mode uses technical terms
//
// Hierarchy:
//   Group (trusted group of devices)
//     └── Hive (single device)
//           └── Bees (agents)
//                 └── Swarm (grouped bees)

import { getAdvancedMode } from "../stores/preferences-store.svelte";

type TermKey =
  // Infrastructure
  | "meadow" | "Meadow"           // Group of nodes (was: hive)
  | "hive" | "Hive"               // Single node/device
  | "hives" | "Hives"
  | "node" | "Node"               // Technical term for device
  | "peer" | "Peer"               // Discovered nearby
  | "neighbour" | "Neighbour"
  | "member" | "Member"           // Node in the meadow
  | "keyHolder" | "KeyHolder"     // Has the private key
  | "keeper" | "Keeper"
  | "directory" | "Directory"     // Registry of nodes/bees
  | "map" | "Map"
  // Agents
  | "sentant" | "Sentant"         // Individual agent
  | "sentants" | "Sentants"
  | "bee" | "Bee"
  | "bees" | "Bees"
  | "swarm" | "Swarm"             // Group of agents
  // Interactions
  | "signal" | "Signal"           // Outgoing notification
  | "buzz" | "Buzz"
  | "event" | "Event"             // Incoming trigger
  | "message" | "Message"
  | "state" | "State"             // Current data
  | "memory" | "Memory"
  // Actions
  | "deploy" | "Deploy"           // Load onto device
  | "release" | "Release"
  | "unload" | "Unload"           // Remove from device
  | "recall" | "Recall"
  // Internals (hidden in standard)
  | "automation" | "Automation"
  | "plugin" | "Plugin"
  | "transition" | "Transition"
  | "action" | "Action"
  // Access
  | "viewer" | "Viewer"
  | "visitor" | "Visitor"
  // Status
  | "provisional" | "Provisional";

const TERMINOLOGY: Record<"standard" | "advanced", Record<TermKey, string>> = {
  standard: {
    // Infrastructure - friendly terms
    meadow: "group",
    Meadow: "Group",
    hive: "hive",
    Hive: "Hive",
    hives: "hives",
    Hives: "Hives",
    node: "hive",
    Node: "Hive",
    peer: "neighbour",
    Peer: "Neighbour",
    neighbour: "neighbour",
    Neighbour: "Neighbour",
    member: "hive",
    Member: "Hive",
    keyHolder: "keeper",
    KeyHolder: "Keeper",
    keeper: "keeper",
    Keeper: "Keeper",
    directory: "map",
    Directory: "Map",
    map: "map",
    Map: "Map",
    // Agents
    sentant: "bee",
    Sentant: "Bee",
    sentants: "bees",
    Sentants: "Bees",
    bee: "bee",
    Bee: "Bee",
    bees: "bees",
    Bees: "Bees",
    swarm: "swarm",
    Swarm: "Swarm",
    // Interactions
    signal: "buzz",
    Signal: "Buzz",
    buzz: "buzz",
    Buzz: "Buzz",
    event: "message",
    Event: "Message",
    message: "message",
    Message: "Message",
    state: "memory",
    State: "Memory",
    memory: "memory",
    Memory: "Memory",
    // Actions
    deploy: "release",
    Deploy: "Release",
    release: "release",
    Release: "Release",
    unload: "recall",
    Unload: "Recall",
    recall: "recall",
    Recall: "Recall",
    // Internals (still shown with friendly names if needed)
    automation: "routine",
    Automation: "Routine",
    plugin: "tool",
    Plugin: "Tool",
    transition: "response",
    Transition: "Response",
    action: "task",
    Action: "Task",
    // Access
    viewer: "visitor",
    Viewer: "Visitor",
    visitor: "visitor",
    Visitor: "Visitor",
    // Status
    provisional: "new",
    Provisional: "New",
  },
  advanced: {
    // Infrastructure - technical terms
    meadow: "trust group",
    Meadow: "Trust Group",
    hive: "node",
    Hive: "Node",
    hives: "nodes",
    Hives: "Nodes",
    node: "node",
    Node: "Node",
    peer: "peer",
    Peer: "Peer",
    neighbour: "peer",
    Neighbour: "Peer",
    member: "member",
    Member: "Member",
    keyHolder: "key holder",
    KeyHolder: "Key Holder",
    keeper: "key holder",
    Keeper: "Key Holder",
    directory: "directory",
    Directory: "Directory",
    map: "directory",
    Map: "Directory",
    // Agents
    sentant: "sentant",
    Sentant: "Sentant",
    sentants: "sentants",
    Sentants: "Sentants",
    bee: "sentant",
    Bee: "Sentant",
    bees: "sentants",
    Bees: "Sentants",
    swarm: "swarm",
    Swarm: "Swarm",
    // Interactions
    signal: "signal",
    Signal: "Signal",
    buzz: "signal",
    Buzz: "Signal",
    event: "event",
    Event: "Event",
    message: "event",
    Message: "Event",
    state: "state",
    State: "State",
    memory: "state",
    Memory: "State",
    // Actions
    deploy: "deploy",
    Deploy: "Deploy",
    release: "deploy",
    Release: "Deploy",
    unload: "unload",
    Unload: "Unload",
    recall: "unload",
    Recall: "Unload",
    // Internals
    automation: "automation",
    Automation: "Automation",
    plugin: "plugin",
    Plugin: "Plugin",
    transition: "transition",
    Transition: "Transition",
    action: "action",
    Action: "Action",
    // Access
    viewer: "viewer",
    Viewer: "Viewer",
    visitor: "viewer",
    Visitor: "Viewer",
    // Status
    provisional: "provisional",
    Provisional: "Provisional",
  },
};

/**
 * Get the appropriate term based on current mode.
 * @param key The terminology key
 * @returns The translated term for the current mode
 */
export function t(key: TermKey): string {
  const mode = getAdvancedMode() ? "advanced" : "standard";
  return TERMINOLOGY[mode][key] ?? key;
}

/**
 * Get a term explicitly for a specific mode (useful for conditional rendering).
 */
export function termFor(key: TermKey, advanced: boolean): string {
  const mode = advanced ? "advanced" : "standard";
  return TERMINOLOGY[mode][key] ?? key;
}
