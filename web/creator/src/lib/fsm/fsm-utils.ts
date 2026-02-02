import type { AutomationModel, PluginModel } from "../models/canvas";

export interface FSMState {
  id: string;
  name: string;
  isStart: boolean;
  isWildcard: boolean;
  isAntenna: boolean;
  isCommand: boolean;
  isSignal: boolean;
  isSend: boolean;
  isPublic: boolean;
  transitionIndex?: number;
  sendTarget?: string;
  sendType?: "bee" | "reply" | "broadcast" | "self";
}

/**
 * Extract signal actions from a transition's action list.
 * Returns array of { event, isPublic } for each signal action found.
 */
function findSignals(t: { actions: Array<{ command: string; parameters?: Record<string, unknown> }> }): Array<{ event: string; isPublic: boolean }> {
  const signals: Array<{ event: string; isPublic: boolean }> = [];
  for (const a of t.actions) {
    if (a.command === "signal" && a.parameters) {
      const event = a.parameters.event as string | undefined;
      if (event) {
        signals.push({ event, isPublic: !!(a.parameters.public) });
      }
    }
  }
  return signals;
}

/**
 * Extract direct send actions (send without a plugin/antenna).
 */
function classifySendType(to: string | undefined): "bee" | "reply" | "broadcast" | "self" {
  if (to === "@sender") return "reply";
  if (to === "*" || (to && to.includes("|"))) return "broadcast";
  if (!to) return "self";
  return "bee";
}

function findDirectSends(t: { actions: Array<{ command: string; plugin?: string; parameters?: Record<string, unknown> }> }): Array<{ event: string; target: string; sendType: "bee" | "reply" | "broadcast" | "self"; delay?: number }> {
  const sends: Array<{ event: string; target: string; sendType: "bee" | "reply" | "broadcast" | "self"; delay?: number }> = [];
  for (const a of t.actions) {
    if (a.command === "send" && !a.plugin && a.parameters) {
      const event = a.parameters.event as string | undefined;
      const to = a.parameters.to as string | undefined;
      const delay = a.parameters.delay as number | string | undefined;
      if (event) {
        sends.push({ event, target: to || "", sendType: classifySendType(to), delay: delay ? Number(delay) || undefined : undefined });
      }
    }
  }
  return sends;
}

export interface FSMEdge {
  id: string;
  source: string;
  target: string;
  sourceHandle: string;
  targetHandle: string;
  transitionIndex: number;
  event: string;
  isPublic: boolean;
  isAntennaLink: boolean;
}

/**
 * Build a map of plugin name → output event for plugins that have output config.
 */
function buildPluginOutputMap(plugins: PluginModel[]): Map<string, string> {
  const map = new Map<string, string>();
  for (const p of plugins) {
    if (p.output?.event) {
      map.set(p.name, p.output.event);
    }
  }
  return map;
}

/**
 * For a transition, find the plugin name if it has a send-to-plugin action (external plugin).
 */
function findPluginSend(t: { actions: Array<{ command: string; plugin?: string }> }): string | undefined {
  for (const a of t.actions) {
    if (a.command === "send" && a.plugin) return a.plugin;
  }
  return undefined;
}

/**
 * For a transition, find all internal plugin references — actions that have a
 * `plugin` field but are NOT "send" commands (those are external plugin calls).
 * Returns unique plugin names.
 */
function findInternalPluginRefs(t: { actions: Array<{ command: string; plugin?: string }> }): string[] {
  const names = new Set<string>();
  for (const a of t.actions) {
    if (a.plugin && a.command !== "send") {
      names.add(a.plugin);
    }
  }
  return Array.from(names);
}

/**
 * Classify a transition based on its from/to fields.
 */
function classifyTransition(t: { from?: string; to?: string; event: string }): "instruction" | "start" | "wildcard" | "full" {
  const hasFrom = !!t.from;
  const hasTo = !!t.to;
  if (!hasFrom && !hasTo) return "instruction";
  if (t.from === "start") return "start";
  if (t.from === "*" || (!hasFrom && hasTo)) return "wildcard";
  return "full";
}

/**
 * Extract FSM nodes from automation transitions and plugins.
 *
 * Node types:
 * - State nodes: explicit from/to state names
 * - Start node: when from === "start"
 * - Wildcard node: only when explicit from === "*" (not for instructions)
 * - Command nodes: one per instruction transition (no from/to) — each is unique
 * - Antenna nodes: plugins referenced by send actions whose output events are caught
 */
export function extractStates(automation: AutomationModel, plugins: PluginModel[] = []): FSMState[] {
  if (!automation?.transitions) return [];

  const pluginOutputMap = buildPluginOutputMap(plugins);
  const stateNames = new Set<string>();
  const antennaNames = new Set<string>();
  let needsWildcard = false;
  let idx = 0;

  // Identify active antenna linkages
  const transitionEvents = new Set(automation.transitions.map(t => t.event));
  const activeAntennaPlugins = new Set<string>();

  for (const t of automation.transitions) {
    const pluginName = findPluginSend(t);
    if (pluginName) {
      const outputEvent = pluginOutputMap.get(pluginName);
      if (outputEvent && transitionEvents.has(outputEvent)) {
        activeAntennaPlugins.add(pluginName);
        antennaNames.add(pluginName);
      }
    }
  }

  const outputEventToPlugin = new Map<string, string>();
  for (const p of activeAntennaPlugins) {
    const ev = pluginOutputMap.get(p);
    if (ev) outputEventToPlugin.set(ev, p);
  }

  // Collect internal plugin references (actions with plugin field, non-send command)
  const internalPluginNames = new Set<string>();
  for (const t of automation.transitions) {
    for (const name of findInternalPluginRefs(t)) {
      internalPluginNames.add(name);
    }
  }
  // Add internal plugins as antenna names (if not already covered by external plugins)
  for (const name of internalPluginNames) {
    if (!antennaNames.has(name)) {
      antennaNames.add(name);
    }
  }

  // Collect events from state-based transitions so we can merge redundant instructions
  const stateTransitionEvents = new Set<string>();
  for (const t of automation.transitions) {
    const kind = classifyTransition(t);
    if (kind !== "instruction") {
      stateTransitionEvents.add(t.event);
    }
  }

  // Collect state names and command nodes
  const commandNodes: FSMState[] = [];
  // Track merged instruction indices → first matching state transition index
  const mergedInstructions = new Map<number, number>();

  for (let tIdx = 0; tIdx < automation.transitions.length; tIdx++) {
    const t = automation.transitions[tIdx];
    const kind = classifyTransition(t);
    const pluginName = findPluginSend(t);
    const sendsToAntenna = pluginName && activeAntennaPlugins.has(pluginName);
    const isAntennaResponse = outputEventToPlugin.has(t.event);

    switch (kind) {
      case "instruction": {
        // If this event already appears on a state transition and the instruction
        // has no unique antenna chain, merge it (suppress command node) to reduce clutter
        const hasAntennaChain = sendsToAntenna || isAntennaResponse || findInternalPluginRefs(t).length > 0;
        if (!hasAntennaChain && stateTransitionEvents.has(t.event)) {
          // Find first state transition with matching event for merging signals/sends
          for (let sIdx = 0; sIdx < automation.transitions.length; sIdx++) {
            const st = automation.transitions[sIdx];
            if (classifyTransition(st) !== "instruction" && st.event === t.event) {
              mergedInstructions.set(tIdx, sIdx);
              break;
            }
          }
          break;
        }
        commandNodes.push({
          id: `fsm-c-${idx++}`,
          name: t.event,
          isStart: false,
          isWildcard: false,
          isAntenna: false,
          isCommand: true,
          isSignal: false,
          isSend: false,
          isPublic: t.public ?? false,
          transitionIndex: tIdx,
        });
        break;
      }

      case "start":
        stateNames.add("start");
        if (t.to && t.to !== "*") stateNames.add(t.to);
        break;

      case "wildcard":
        needsWildcard = true;
        if (t.to && t.to !== "*") stateNames.add(t.to);
        break;

      case "full":
        if (t.from && t.from !== "*") stateNames.add(t.from);
        if (t.to && t.to !== "*") stateNames.add(t.to);
        break;
    }
  }

  if (needsWildcard) stateNames.add("*");

  // Build final state list
  const states: FSMState[] = [];

  for (const name of stateNames) {
    states.push({
      id: `fsm-s-${idx++}`,
      name,
      isStart: name === "start",
      isWildcard: name === "*",
      isAntenna: false,
      isCommand: false,
      isSignal: false,
      isSend: false,
      isPublic: false,
    });
  }

  // Add command nodes
  states.push(...commandNodes);

  // Add antenna nodes
  for (const name of antennaNames) {
    states.push({
      id: `fsm-a-${idx++}`,
      name,
      isStart: false,
      isWildcard: false,
      isAntenna: true,
      isCommand: false,
      isSignal: false,
      isSend: false,
      isPublic: false,
    });
  }

  // Add signal nodes — one per signal action found in all transitions
  for (let tIdx = 0; tIdx < automation.transitions.length; tIdx++) {
    const t = automation.transitions[tIdx];
    const signals = findSignals(t);
    for (let sIdx = 0; sIdx < signals.length; sIdx++) {
      const sig = signals[sIdx];
      states.push({
        id: `fsm-sig-${tIdx}-${sIdx}`,
        name: sig.event,
        isStart: false,
        isWildcard: false,
        isAntenna: false,
        isCommand: false,
        isSignal: true,
        isSend: false,
        isPublic: sig.isPublic,
        transitionIndex: tIdx,
      });
    }
  }

  // Add direct send nodes (send without plugin/antenna)
  // Suppress self-sends whose event already appears as a transition event
  // (the FSM edges already show that flow; delay is visible in ActionEditor)
  for (let tIdx = 0; tIdx < automation.transitions.length; tIdx++) {
    const t = automation.transitions[tIdx];
    const directSends = findDirectSends(t);
    for (let dIdx = 0; dIdx < directSends.length; dIdx++) {
      const ds = directSends[dIdx];
      if (ds.sendType === "self" && transitionEvents.has(ds.event)) continue;
      states.push({
        id: `fsm-send-${tIdx}-${dIdx}`,
        name: ds.event,
        isStart: false,
        isWildcard: false,
        isAntenna: false,
        isCommand: false,
        isSignal: false,
        isSend: true,
        isPublic: false,
        transitionIndex: tIdx,
        sendTarget: ds.target,
        sendType: ds.sendType,
      });
    }
  }

  return states;
}

/**
 * Map transitions to edges between nodes.
 *
 * For instructions: the command node IS the transition. Edges connect it
 * to/from antenna nodes or leave it standalone (no edges for plain commands).
 *
 * For state transitions: edges between state nodes as before.
 */
export function extractEdges(automation: AutomationModel, states: FSMState[], plugins: PluginModel[] = []): FSMEdge[] {
  if (!automation?.transitions || states.length === 0) return [];

  const pluginOutputMap = buildPluginOutputMap(plugins);

  // Build lookup maps
  const stateNameToId = new Map<string, string>();
  const antennaNameToId = new Map<string, string>();
  const commandByTransIdx = new Map<number, FSMState>();
  const signalsByTransIdx = new Map<number, FSMState[]>();
  const sendsByTransIdx = new Map<number, FSMState[]>();

  for (const s of states) {
    if (s.isAntenna) {
      antennaNameToId.set(s.name, s.id);
    } else if (s.isSignal && s.transitionIndex !== undefined) {
      if (!signalsByTransIdx.has(s.transitionIndex)) signalsByTransIdx.set(s.transitionIndex, []);
      signalsByTransIdx.get(s.transitionIndex)!.push(s);
    } else if (s.isSend && s.transitionIndex !== undefined) {
      if (!sendsByTransIdx.has(s.transitionIndex)) sendsByTransIdx.set(s.transitionIndex, []);
      sendsByTransIdx.get(s.transitionIndex)!.push(s);
    } else if (s.isCommand && s.transitionIndex !== undefined) {
      commandByTransIdx.set(s.transitionIndex, s);
    } else {
      stateNameToId.set(s.name, s.id);
    }
  }

  // Identify active antenna linkages
  const transitionEvents = new Set(automation.transitions.map(t => t.event));
  const activeAntennaPlugins = new Set<string>();
  for (const t of automation.transitions) {
    const pluginName = findPluginSend(t);
    if (pluginName) {
      const outputEvent = pluginOutputMap.get(pluginName);
      if (outputEvent && transitionEvents.has(outputEvent)) {
        activeAntennaPlugins.add(pluginName);
      }
    }
  }
  const outputEventToPlugin = new Map<string, string>();
  for (const p of activeAntennaPlugins) {
    const ev = pluginOutputMap.get(p);
    if (ev) outputEventToPlugin.set(ev, p);
  }

  const edges: FSMEdge[] = [];

  automation.transitions.forEach((t, idx) => {
    const kind = classifyTransition(t);
    const pluginName = findPluginSend(t);
    const sendsToAntenna = pluginName && activeAntennaPlugins.has(pluginName);
    const responsesFromPlugin = outputEventToPlugin.get(t.event) ?? null;
    const internalRefs = findInternalPluginRefs(t);

    if (kind === "instruction") {
      const cmdNode = commandByTransIdx.get(idx);
      if (!cmdNode) return;

      // Build an inline chain: [incoming] → command → [internal antennae] → [outgoing]
      // Track the "current" node as we build the chain left-to-right
      let chainTip = cmdNode.id;

      // Incoming edge from external antenna response
      if (responsesFromPlugin) {
        const antennaId = antennaNameToId.get(responsesFromPlugin)!;
        edges.push({
          id: `fsm-e-${idx}-in`,
          source: antennaId,
          target: chainTip,
          sourceHandle: "out",
          targetHandle: "in",
          transitionIndex: idx,
          event: t.event,
          isPublic: t.public ?? false,
          isAntennaLink: true,
        });
      }

      // Chain through internal plugin antennae (data flows through each)
      for (let i = 0; i < internalRefs.length; i++) {
        const aId = antennaNameToId.get(internalRefs[i]);
        if (aId) {
          edges.push({
            id: `fsm-e-${idx}-int-${i}`,
            source: chainTip,
            target: aId,
            sourceHandle: "out",
            targetHandle: "in",
            transitionIndex: idx,
            event: "",
            isPublic: false,
            isAntennaLink: true,
          });
          chainTip = aId;
        }
      }

      // Outgoing edge to external antenna (send)
      if (sendsToAntenna) {
        const antennaId = antennaNameToId.get(pluginName!)!;
        edges.push({
          id: `fsm-e-${idx}-out`,
          source: chainTip,
          target: antennaId,
          sourceHandle: "out",
          targetHandle: "in",
          transitionIndex: idx,
          event: "",
          isPublic: false,
          isAntennaLink: true,
        });
      }
      return;
    }

    // State-based transitions
    let sourceId: string;
    let targetId: string;

    switch (kind) {
      case "start":
        sourceId = stateNameToId.get("start")!;
        targetId = t.to && t.to !== "*" && stateNameToId.has(t.to) ? stateNameToId.get(t.to)! : sourceId;
        break;
      case "wildcard":
        sourceId = stateNameToId.get("*")!;
        targetId = t.to && t.to !== "*" && stateNameToId.has(t.to) ? stateNameToId.get(t.to)! : sourceId;
        break;
      case "full":
      default:
        sourceId = stateNameToId.get(t.from!)!;
        targetId = t.to && t.to !== "*" && stateNameToId.has(t.to) ? stateNameToId.get(t.to)! : sourceId;
        break;
    }

    // Build inline chain: source → [external antenna in] → [internal antennae] → [external antenna out] → target
    const hasAntennaOrInternal = sendsToAntenna || responsesFromPlugin || internalRefs.length > 0;
    let chainTip = sourceId;
    let edgeCount = 0;

    // First edge: source → next node (with the transition event label)
    // If there are antennae/internals in between, first hop goes to the first antenna
    if (responsesFromPlugin) {
      // Response comes FROM external antenna, so antenna replaces source
      const antennaId = antennaNameToId.get(responsesFromPlugin)!;
      edges.push({
        id: `fsm-e-${idx}-${edgeCount++}`,
        source: antennaId,
        target: sourceId, // still show source state
        sourceHandle: "out",
        targetHandle: "in",
        transitionIndex: idx,
        event: t.event,
        isPublic: t.public ?? false,
        isAntennaLink: true,
      });
      // chainTip stays at sourceId — internal antennae chain from source
    }

    if (!hasAntennaOrInternal) {
      // Simple case: source → target
      edges.push({
        id: `fsm-e-${idx}`,
        source: sourceId,
        target: targetId,
        sourceHandle: "out",
        targetHandle: "in",
        transitionIndex: idx,
        event: t.event,
        isPublic: t.public ?? false,
        isAntennaLink: false,
      });
    } else {
      // Chain through internal plugin antennae
      // First hop carries the event label
      let firstHop = true;
      for (let i = 0; i < internalRefs.length; i++) {
        const aId = antennaNameToId.get(internalRefs[i]);
        if (aId) {
          edges.push({
            id: `fsm-e-${idx}-${edgeCount++}`,
            source: chainTip,
            target: aId,
            sourceHandle: "out",
            targetHandle: "in",
            transitionIndex: idx,
            event: firstHop && !responsesFromPlugin ? t.event : "",
            isPublic: firstHop && !responsesFromPlugin ? (t.public ?? false) : false,
            isAntennaLink: true,
          });
          chainTip = aId;
          firstHop = false;
        }
      }

      // Outgoing to external antenna (send)
      if (sendsToAntenna) {
        const antennaId = antennaNameToId.get(pluginName!)!;
        edges.push({
          id: `fsm-e-${idx}-${edgeCount++}`,
          source: chainTip,
          target: antennaId,
          sourceHandle: "out",
          targetHandle: "in",
          transitionIndex: idx,
          event: firstHop ? t.event : "",
          isPublic: firstHop ? (t.public ?? false) : false,
          isAntennaLink: true,
        });
        // External send is async — no edge to target (response comes via separate transition)
      } else {
        // Final hop: last antenna → target
        edges.push({
          id: `fsm-e-${idx}-${edgeCount++}`,
          source: chainTip,
          target: targetId,
          sourceHandle: "out",
          targetHandle: "in",
          transitionIndex: idx,
          event: firstHop ? t.event : "",
          isPublic: firstHop ? (t.public ?? false) : false,
          isAntennaLink: internalRefs.length > 0,
        });
      }
    }
  });

  // Compute chain tips BEFORE adding signal/send edges so that
  // branching edges don't pollute the chain tip lookup.
  function findChainTip(idx: number): string | undefined {
    const transEdges = edges.filter(e => e.transitionIndex === idx);
    if (transEdges.length > 0) {
      return transEdges[transEdges.length - 1].target;
    }
    const cmdNode = commandByTransIdx.get(idx);
    if (cmdNode) return cmdNode.id;
    return undefined;
  }

  const chainTips = new Map<number, string>();
  automation.transitions.forEach((_t, idx) => {
    const tip = findChainTip(idx);
    if (tip) chainTips.set(idx, tip);
  });

  // For merged instructions (command node suppressed because event matches a
  // state transition), redirect their signals/sends to the matching state
  // transition's chain tip.
  automation.transitions.forEach((t, idx) => {
    if (chainTips.has(idx)) return; // already has a chain tip
    const kind = classifyTransition(t);
    if (kind !== "instruction") return;
    // This instruction was merged — find first state transition with same event
    for (let sIdx = 0; sIdx < automation.transitions.length; sIdx++) {
      const st = automation.transitions[sIdx];
      if (classifyTransition(st) !== "instruction" && st.event === t.event && chainTips.has(sIdx)) {
        chainTips.set(idx, chainTips.get(sIdx)!);
        break;
      }
    }
  });

  // Add signal edges: from the transition's node (top) to each signal output node (bottom)
  automation.transitions.forEach((t, idx) => {
    const signals = signalsByTransIdx.get(idx);
    if (!signals || signals.length === 0) return;

    const sourceNodeId = chainTips.get(idx);
    if (!sourceNodeId) return;

    for (let sIdx = 0; sIdx < signals.length; sIdx++) {
      edges.push({
        id: `fsm-sig-e-${idx}-${sIdx}`,
        source: sourceNodeId,
        target: signals[sIdx].id,
        sourceHandle: "signal-out",
        targetHandle: "in",
        transitionIndex: idx,
        event: "",
        isPublic: signals[sIdx].isPublic,
        isAntennaLink: false,
      });
    }
  });

  // Add direct send edges: from the transition's chain tip to each send node
  automation.transitions.forEach((t, idx) => {
    const sends = sendsByTransIdx.get(idx);
    if (!sends || sends.length === 0) return;

    const sourceNodeId = chainTips.get(idx);
    if (!sourceNodeId) return;

    for (let dIdx = 0; dIdx < sends.length; dIdx++) {
      edges.push({
        id: `fsm-send-e-${idx}-${dIdx}`,
        source: sourceNodeId,
        target: sends[dIdx].id,
        sourceHandle: "out",
        targetHandle: "in",
        transitionIndex: idx,
        event: "",
        isPublic: false,
        isAntennaLink: false,
      });
    }
  });

  return edges;
}

/**
 * Auto-layout nodes using BFS from start/first node.
 * Positions send nodes near their chain tip, signals above their source,
 * and resolves overlaps.
 */
export function layoutStates(
  states: FSMState[],
  edges: FSMEdge[]
): Record<string, { x: number; y: number }> {
  const COL_WIDTH = 280;
  const STATE_ROW_GAP = 120;
  const FLOW_ROW_GAP = 100;
  const STATE_FLOW_GAP = 80;
  const SEND_OFFSET_X = 200;
  const SEND_STACK_Y = 60;
  const SIGNAL_OFFSET_Y = 100;
  const SIGNAL_SPREAD_X = 200;
  const NODE_WIDTH = 160;
  const NODE_HEIGHT = 50;
  const MARGIN = 60;

  // --- Phase 1: BFS depths ---

  const adj = new Map<string, Set<string>>();
  for (const s of states) adj.set(s.id, new Set());
  for (const e of edges) {
    if (e.source !== e.target) {
      adj.get(e.source)?.add(e.target);
    }
  }

  const hasIncoming = new Set<string>();
  for (const e of edges) {
    if (e.source !== e.target) hasIncoming.add(e.target);
  }

  const roots: string[] = [];
  const startState = states.find(s => s.isStart);
  const wildcardState = states.find(s => s.isWildcard);
  if (startState) roots.push(startState.id);
  if (wildcardState) roots.push(wildcardState.id);
  for (const s of states) {
    if (s.isStart || s.isWildcard) continue;
    if (!hasIncoming.has(s.id) && !roots.includes(s.id)) {
      roots.push(s.id);
    }
  }

  const depths = new Map<string, number>();
  const queue: string[] = [];
  for (const r of roots) {
    if (!depths.has(r)) {
      depths.set(r, 0);
      queue.push(r);
    }
  }
  while (queue.length > 0) {
    const cur = queue.shift()!;
    const curDepth = depths.get(cur)!;
    for (const next of adj.get(cur) ?? []) {
      if (!depths.has(next)) {
        depths.set(next, curDepth + 1);
        queue.push(next);
      }
    }
  }

  // --- Phase 2: Classify nodes into 5 groups ---

  const stateNodes: FSMState[] = [];
  const commandNodes: FSMState[] = [];
  const antennaNodes: FSMState[] = [];
  const signalNodes: FSMState[] = [];
  const sendNodes: FSMState[] = [];
  const unplaced: FSMState[] = [];

  for (const s of states) {
    if (s.isSignal) {
      signalNodes.push(s);
    } else if (s.isSend) {
      sendNodes.push(s);
    } else if (s.isCommand) {
      commandNodes.push(s);
    } else if (s.isAntenna) {
      antennaNodes.push(s);
    } else if (depths.has(s.id)) {
      stateNodes.push(s);
    } else {
      unplaced.push(s);
    }
  }

  // --- Phase 3: Build chain tip map ---

  const chainTipOf = new Map<string, string>();
  for (const node of [...sendNodes, ...signalNodes]) {
    for (const e of edges) {
      if (e.target === node.id) {
        chainTipOf.set(node.id, e.source);
        break;
      }
    }
  }

  // Pre-compute which nodes have signal children (used in phases 4 and 5)
  const nodesWithSignals = new Set<string>();
  for (const sig of signalNodes) {
    const sourceId = chainTipOf.get(sig.id);
    if (sourceId) nodesWithSignals.add(sourceId);
  }

  // --- Phase 4: Position state backbone ---

  const positions: Record<string, { x: number; y: number }> = {};

  const statesByDepth = new Map<number, FSMState[]>();
  for (const s of stateNodes) {
    const d = depths.get(s.id) ?? 0;
    if (!statesByDepth.has(d)) statesByDepth.set(d, []);
    statesByDepth.get(d)!.push(s);
  }

  const STATE_SIGNAL_GAP = SIGNAL_OFFSET_Y + NODE_HEIGHT + 60;
  for (const [depth, group] of statesByDepth) {
    let y = MARGIN;
    for (let row = 0; row < group.length; row++) {
      if (row > 0) {
        y += nodesWithSignals.has(group[row].id) ? STATE_SIGNAL_GAP : STATE_ROW_GAP;
      }
      positions[group[row].id] = {
        x: MARGIN + depth * COL_WIDTH,
        y,
      };
    }
  }

  // --- Phase 5: Position command + antenna nodes (flow band, no sends) ---

  const flowNodes = [...commandNodes, ...antennaNodes].filter(s => depths.has(s.id));
  const flowByDepth = new Map<number, FSMState[]>();
  for (const s of flowNodes) {
    const d = depths.get(s.id)!;
    if (!flowByDepth.has(d)) flowByDepth.set(d, []);
    flowByDepth.get(d)!.push(s);
  }

  const stateRowCount = Math.max(1, ...Array.from(statesByDepth.values()).map(g => g.length));
  const flowBaseY = statesByDepth.size > 0
    ? MARGIN + stateRowCount * STATE_ROW_GAP + STATE_FLOW_GAP
    : MARGIN;

  // Variable spacing: add extra room above nodes that have signals,
  // so the signal doesn't land on top of the previous node
  const SIGNAL_GROUP_GAP = SIGNAL_OFFSET_Y + NODE_HEIGHT + 60;
  for (const [depth, group] of flowByDepth) {
    let y = flowBaseY;
    for (let row = 0; row < group.length; row++) {
      if (row > 0) {
        y += nodesWithSignals.has(group[row].id) ? SIGNAL_GROUP_GAP : FLOW_ROW_GAP;
      }
      positions[group[row].id] = {
        x: MARGIN + depth * COL_WIDTH,
        y,
      };
    }
  }

  // Place unplaced commands/antennae that BFS didn't reach
  const unplacedFlow = [...commandNodes, ...antennaNodes].filter(s => !depths.has(s.id));
  const flowRowCount = Math.max(0, ...Array.from(flowByDepth.values()).map(g => g.length));
  for (let i = 0; i < unplacedFlow.length; i++) {
    positions[unplacedFlow[i].id] = {
      x: MARGIN + i * COL_WIDTH,
      y: flowBaseY + (flowRowCount > 0 ? flowRowCount : 0) * FLOW_ROW_GAP,
    };
  }

  // --- Phase 6a: Position signal nodes above their source ---

  const signalsBySource = new Map<string, FSMState[]>();
  for (const sig of signalNodes) {
    const sourceId = chainTipOf.get(sig.id);
    if (sourceId && positions[sourceId]) {
      if (!signalsBySource.has(sourceId)) signalsBySource.set(sourceId, []);
      signalsBySource.get(sourceId)!.push(sig);
    }
  }

  const SIGNAL_X_OFFSET = 100; // shift signals right so they don't sit on edge paths
  for (const [sourceId, sigs] of signalsBySource) {
    const sourcePos = positions[sourceId];
    for (let i = 0; i < sigs.length; i++) {
      positions[sigs[i].id] = {
        x: sourcePos.x + SIGNAL_X_OFFSET + (i - (sigs.length - 1) / 2) * SIGNAL_SPREAD_X,
        y: sourcePos.y - SIGNAL_OFFSET_Y,
      };
    }
  }

  // Nudge signals that overlap backbone nodes or other signals upward
  const signalIdSet = new Set(signalNodes.map(s => s.id));
  const sendIdSet = new Set(sendNodes.map(s => s.id));
  const backboneEntries = Object.entries(positions).filter(([id]) => !signalIdSet.has(id) && !sendIdSet.has(id));
  const SIG_PAD_X = 20;
  const SIG_PAD_Y = 10;
  for (const sig of signalNodes) {
    if (!positions[sig.id]) continue;
    let moved = true;
    let safety = 0;
    while (moved && safety < 20) {
      moved = false;
      safety++;
      const sp = positions[sig.id];
      // Check against backbone nodes
      for (const [, bp] of backboneEntries) {
        if (Math.abs(sp.x - bp.x) < NODE_WIDTH + SIG_PAD_X && Math.abs(sp.y - bp.y) < NODE_HEIGHT + SIG_PAD_Y) {
          sp.y = bp.y - NODE_HEIGHT - SIG_PAD_Y;
          moved = true;
        }
      }
      // Check against other already-placed signals
      for (const other of signalNodes) {
        if (other.id === sig.id || !positions[other.id]) continue;
        const op = positions[other.id];
        if (Math.abs(sp.x - op.x) < NODE_WIDTH + SIG_PAD_X && Math.abs(sp.y - op.y) < NODE_HEIGHT + SIG_PAD_Y) {
          sp.y = op.y - NODE_HEIGHT - SIG_PAD_Y;
          moved = true;
        }
      }
    }
  }

  // --- Phase 6b: Position send nodes to the right of their chain tip ---

  const sendsBySource = new Map<string, FSMState[]>();
  for (const send of sendNodes) {
    const sourceId = chainTipOf.get(send.id);
    if (sourceId && positions[sourceId]) {
      if (!sendsBySource.has(sourceId)) sendsBySource.set(sourceId, []);
      sendsBySource.get(sourceId)!.push(send);
    }
  }

  for (const [sourceId, sends] of sendsBySource) {
    const sourcePos = positions[sourceId];
    const startY = sourcePos.y - ((sends.length - 1) * SEND_STACK_Y) / 2;
    for (let i = 0; i < sends.length; i++) {
      positions[sends[i].id] = {
        x: sourcePos.x + SEND_OFFSET_X,
        y: startY + i * SEND_STACK_Y,
      };
    }
  }

  // --- Phase 7: Place orphan nodes ---

  const allPlacedMaxY = Object.values(positions).length > 0
    ? Math.max(...Object.values(positions).map(p => p.y))
    : MARGIN;

  let orphanX = MARGIN;
  for (const s of [...unplaced, ...signalNodes, ...sendNodes]) {
    if (!positions[s.id]) {
      positions[s.id] = { x: orphanX, y: allPlacedMaxY + STATE_ROW_GAP + 40 };
      orphanX += COL_WIDTH;
    }
  }

  // --- Phase 8: Overlap detection and nudging ---
  // Only resolve overlaps for backbone nodes (states, commands, antennae).
  // Signal and send nodes are positioned relative to their source and should stay put.

  const signalIds = new Set(signalNodes.map(s => s.id));
  const sendIds = new Set(sendNodes.map(s => s.id));
  const backboneIds = Object.keys(positions).filter(id => !signalIds.has(id) && !sendIds.has(id));
  const PADDING_X = 20;
  const PADDING_Y = 10;
  let changed = true;
  let iterations = 0;

  while (changed && iterations < 50) {
    changed = false;
    iterations++;
    for (let i = 0; i < backboneIds.length; i++) {
      for (let j = i + 1; j < backboneIds.length; j++) {
        const a = positions[backboneIds[i]];
        const b = positions[backboneIds[j]];
        const overlapX = (NODE_WIDTH + PADDING_X) - Math.abs(a.x - b.x);
        const overlapY = (NODE_HEIGHT + PADDING_Y) - Math.abs(a.y - b.y);
        if (overlapX > 0 && overlapY > 0) {
          b.y += overlapY + PADDING_Y;
          changed = true;
        }
      }
    }
  }

  return positions;
}
