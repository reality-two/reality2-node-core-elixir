import {
  type CanvasModel,
  type SentantModel,
  type SwarmModel,
  type LiveSentantModel,
  type HiveGroupModel,
  type LiveSwarmGroupModel,
  createSentant,
  createSwarm,
  createAutomation,
  createTransition,
  createAction,
  createPlugin,
  createEmptyCanvas,
  resetCounters,
} from "../models/canvas";
import { canvasToYaml, canvasToJson, yamlToCanvas, jsonToCanvas, sentantToYaml, sentantToJson, swarmToYaml, swarmToJson } from "../models/serializer";

let nextId = 1;
function genId(): string {
  return `node-${nextId++}`;
}

// Reactive state
let model = $state<CanvasModel>(createEmptyCanvas());
let hiveGroups = $state<HiveGroupModel[]>([]);
let liveSwarmGroups = $state<LiveSwarmGroupModel[]>([]);
let selectedNodeId = $state<string | null>(null);
let signalMessages = $state<Record<string, Array<{ time: string; event: string; data: string }>>>({});

// --- Getters ---

export function getModel(): CanvasModel { return model; }
export function getYaml(): string { return canvasToYaml(model); }
export function getJson(): string { return canvasToJson(model); }
export function getSentantYaml(nodeId: string): string {
  const sentant = model.sentants.find(s => s._nodeId === nodeId);
  if (!sentant) return "";
  return sentantToYaml(sentant, model);
}
export function getSentantJson(nodeId: string): string {
  const sentant = model.sentants.find(s => s._nodeId === nodeId);
  if (!sentant) return "";
  return sentantToJson(sentant, model);
}
export function getSwarmYaml(nodeId: string): string {
  const swarm = model.swarms.find(s => s._nodeId === nodeId);
  if (!swarm) return "";
  return swarmToYaml(swarm, model);
}
export function getSwarmJson(nodeId: string): string {
  const swarm = model.swarms.find(s => s._nodeId === nodeId);
  if (!swarm) return "";
  return swarmToJson(swarm, model);
}
export function getSelectedNodeId(): string | null { return selectedNodeId; }

export function getSelectedSentant(): SentantModel | null {
  if (!selectedNodeId) return null;
  return model.sentants.find((s) => s._nodeId === selectedNodeId) ?? null;
}

export function getSelectedLiveSentant(): LiveSentantModel | null {
  if (!selectedNodeId) return null;
  return model.liveSentants.find((s) => s._nodeId === selectedNodeId) ?? null;
}

export function getSentants(): SentantModel[] { return model.sentants; }
export function getSwarms(): SwarmModel[] { return model.swarms; }
export function getLiveSentants(): LiveSentantModel[] { return model.liveSentants; }
export function getHiveGroups(): HiveGroupModel[] { return hiveGroups; }
export function getLiveSwarmGroups(): LiveSwarmGroupModel[] { return liveSwarmGroups; }

export function getSignalMessages(nodeId: string): Array<{ time: string; event: string; data: string }> {
  return signalMessages[nodeId] ?? [];
}

// --- Selection ---

export function selectNode(nodeId: string | null): void {
  selectedNodeId = nodeId;
}

// --- Placement ---

// Collect all occupied rectangles on the canvas (absolute positions)
function getOccupiedRects(): Array<{ x: number; y: number; w: number; h: number }> {
  const rects: Array<{ x: number; y: number; w: number; h: number }> = [];
  for (const sw of model.swarms) {
    rects.push({ x: sw._position.x, y: sw._position.y, w: sw._width, h: sw._height });
  }
  for (const s of model.sentants) {
    // Absolute position: if parented, offset by swarm position
    let ax = s._position.x;
    let ay = s._position.y;
    if (s._swarmId) {
      const sw = model.swarms.find((sw) => sw._nodeId === s._swarmId);
      if (sw) { ax += sw._position.x; ay += sw._position.y; }
    }
    rects.push({ x: ax, y: ay, w: 200, h: 120 });
  }
  for (const g of hiveGroups) {
    rects.push({ x: g._position.x, y: g._position.y, w: g._width, h: g._height });
  }
  for (const ls of model.liveSentants) {
    let ax = ls._position.x;
    let ay = ls._position.y;
    if (ls._hiveGroupId) {
      const g = hiveGroups.find((g) => g._nodeId === ls._hiveGroupId);
      if (g) { ax += g._position.x; ay += g._position.y; }
    }
    rects.push({ x: ax, y: ay, w: 200, h: 120 });
  }
  return rects;
}

function rectsOverlap(a: { x: number; y: number; w: number; h: number }, b: { x: number; y: number; w: number; h: number }): boolean {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

export function findEmptyPosition(w: number, h: number, padding = 30): { x: number; y: number } {
  const rects = getOccupiedRects();
  // Try positions in a grid pattern, scanning right then down
  for (let row = 0; row < 20; row++) {
    for (let col = 0; col < 10; col++) {
      const candidate = { x: 50 + col * (w + padding), y: 50 + row * (h + padding), w, h };
      if (!rects.some((r) => rectsOverlap(candidate, r))) {
        return { x: candidate.x, y: candidate.y };
      }
    }
  }
  // Fallback: place far right
  const maxX = rects.reduce((mx, r) => Math.max(mx, r.x + r.w), 0);
  return { x: maxX + padding, y: 50 };
}

// --- Sentant CRUD ---

export function addSentant(position?: { x: number; y: number }): SentantModel {
  const pos = position ?? findEmptyPosition(200, 120);
  const sentant = createSentant(genId(), pos);

  // Check if the position falls inside a swarm — auto-assign if so
  for (const sw of model.swarms) {
    if (
      pos.x >= sw._position.x &&
      pos.x <= sw._position.x + sw._width &&
      pos.y >= sw._position.y &&
      pos.y <= sw._position.y + sw._height
    ) {
      sentant._swarmId = sw._nodeId;
      sentant._position = { x: pos.x - sw._position.x, y: pos.y - sw._position.y };
      break;
    }
  }

  model.sentants = [...model.sentants, sentant];
  selectedNodeId = sentant._nodeId;
  return sentant;
}

export function removeSentant(nodeId: string): void {
  model.sentants = model.sentants.filter((s) => s._nodeId !== nodeId);
  if (selectedNodeId === nodeId) selectedNodeId = null;
}

export function updateSentant(nodeId: string, updates: Partial<SentantModel>): void {
  model.sentants = model.sentants.map((s) => (s._nodeId === nodeId ? { ...s, ...updates } : s));
}

export function updateSentantPosition(nodeId: string, position: { x: number; y: number }): void {
  if (model.sentants.find((s) => s._nodeId === nodeId)) {
    updateSentant(nodeId, { _position: position });
  } else if (model.liveSentants.find((s) => s._nodeId === nodeId)) {
    updateLiveSentantPosition(nodeId, position);
  }
}

// --- Swarm CRUD ---

export function addSwarm(position?: { x: number; y: number }): SwarmModel {
  const pos = position ?? findEmptyPosition(400, 300);
  const swarm = createSwarm(genId(), pos);
  model.swarms = [...model.swarms, swarm];
  return swarm;
}

export function removeSwarm(nodeId: string): void {
  // Delete sentants that belong to this swarm
  model.sentants = model.sentants.filter((s) => s._swarmId !== nodeId);
  model.swarms = model.swarms.filter((s) => s._nodeId !== nodeId);
}

export function updateSwarm(nodeId: string, updates: Partial<SwarmModel>): void {
  model.swarms = model.swarms.map((s) => (s._nodeId === nodeId ? { ...s, ...updates } : s));
}

export function assignSentantToSwarm(sentantNodeId: string, swarmNodeId: string | undefined): void {
  updateSentant(sentantNodeId, { _swarmId: swarmNodeId });
}

export function getSelectedSwarm(): SwarmModel | null {
  if (!selectedNodeId) return null;
  return model.swarms.find((s) => s._nodeId === selectedNodeId) ?? null;
}

// --- Automation/Transition/Action/Plugin CRUD (unchanged) ---

export function addAutomation(nodeId: string): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return;
  updateSentant(nodeId, { automations: [...sentant.automations, createAutomation()] });
}

export function removeAutomation(nodeId: string, index: number): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return;
  updateSentant(nodeId, { automations: sentant.automations.filter((_, i) => i !== index) });
}

export function updateAutomation(nodeId: string, index: number, updates: Record<string, unknown>): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return;
  const automations = sentant.automations.map((a, i) => (i === index ? { ...a, ...updates } : a));
  updateSentant(nodeId, { automations });
}

export function addTransition(nodeId: string, autoIndex: number): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant || !sentant.automations[autoIndex]) return;
  const automations = [...sentant.automations];
  automations[autoIndex] = {
    ...automations[autoIndex],
    transitions: [...automations[autoIndex].transitions, createTransition()],
  };
  updateSentant(nodeId, { automations });
}

export function removeTransition(nodeId: string, autoIndex: number, transIndex: number): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant || !sentant.automations[autoIndex]) return;
  const automations = [...sentant.automations];
  automations[autoIndex] = {
    ...automations[autoIndex],
    transitions: automations[autoIndex].transitions.filter((_, i) => i !== transIndex),
  };
  updateSentant(nodeId, { automations });
}

export function updateTransition(nodeId: string, autoIndex: number, transIndex: number, updates: Record<string, unknown>): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant || !sentant.automations[autoIndex]) return;
  const automations = [...sentant.automations];
  const transitions = automations[autoIndex].transitions.map((t, i) => i === transIndex ? { ...t, ...updates } : t);
  automations[autoIndex] = { ...automations[autoIndex], transitions };
  updateSentant(nodeId, { automations });
}

export function addAction(nodeId: string, autoIndex: number, transIndex: number): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant || !sentant.automations[autoIndex]) return;
  const trans = sentant.automations[autoIndex].transitions[transIndex];
  if (!trans) return;
  const automations = [...sentant.automations];
  const transitions = [...automations[autoIndex].transitions];
  transitions[transIndex] = { ...trans, actions: [...trans.actions, createAction()] };
  automations[autoIndex] = { ...automations[autoIndex], transitions };
  updateSentant(nodeId, { automations });
}

export function removeAction(nodeId: string, autoIndex: number, transIndex: number, actionIndex: number): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant || !sentant.automations[autoIndex]) return;
  const trans = sentant.automations[autoIndex].transitions[transIndex];
  if (!trans) return;
  const automations = [...sentant.automations];
  const transitions = [...automations[autoIndex].transitions];
  transitions[transIndex] = { ...trans, actions: trans.actions.filter((_, i) => i !== actionIndex) };
  automations[autoIndex] = { ...automations[autoIndex], transitions };
  updateSentant(nodeId, { automations });
}

export function updateAction(nodeId: string, autoIndex: number, transIndex: number, actionIndex: number, updates: Record<string, unknown>): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant || !sentant.automations[autoIndex]) return;
  const trans = sentant.automations[autoIndex].transitions[transIndex];
  if (!trans) return;
  const automations = [...sentant.automations];
  const transitions = [...automations[autoIndex].transitions];
  const actions = trans.actions.map((a, i) => (i === actionIndex ? { ...a, ...updates } : a));
  transitions[transIndex] = { ...trans, actions };
  automations[autoIndex] = { ...automations[autoIndex], transitions };
  updateSentant(nodeId, { automations });
}

export function addPlugin(nodeId: string): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return;
  updateSentant(nodeId, { plugins: [...sentant.plugins, createPlugin()] });
}

export function removePlugin(nodeId: string, index: number): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return;
  updateSentant(nodeId, { plugins: sentant.plugins.filter((_, i) => i !== index) });
}

export function updatePlugin(nodeId: string, index: number, updates: Record<string, unknown>): void {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return;
  const plugins = sentant.plugins.map((p, i) => (i === index ? { ...p, ...updates } : p));
  updateSentant(nodeId, { plugins });
}

// --- Import ---

export function loadFromYaml(yamlStr: string): void {
  const parsed = yamlToCanvas(yamlStr);
  model.swarms = parsed.swarms;
  model.sentants = parsed.sentants;
  nextId = parsed.sentants.length + parsed.swarms.length + 1;
  selectedNodeId = null;
}

export function loadFromContent(content: string, format: "yaml" | "json"): void {
  const parsed = format === "json" ? jsonToCanvas(content) : yamlToCanvas(content);
  model.swarms = parsed.swarms;
  model.sentants = parsed.sentants;
  nextId = parsed.sentants.length + parsed.swarms.length + 1;
  selectedNodeId = null;
}

/** Merge parsed content into the existing canvas (append, don't replace). */
export function mergeContent(content: string, format: "yaml" | "json"): void {
  const parsed = format === "json" ? jsonToCanvas(content) : yamlToCanvas(content);
  if (parsed.sentants.length === 0 && parsed.swarms.length === 0) return;

  // Re-key all parsed items with fresh IDs to avoid collisions
  const idMap = new Map<string, string>();
  for (const sw of parsed.swarms) {
    const newId = genId();
    idMap.set(sw._nodeId, newId);
    sw._nodeId = newId;
  }
  for (const s of parsed.sentants) {
    const newId = genId();
    idMap.set(s._nodeId, newId);
    s._nodeId = newId;
    if (s._swarmId && idMap.has(s._swarmId)) {
      s._swarmId = idMap.get(s._swarmId);
    }
  }

  // Position new swarms to avoid overlapping existing content
  for (const sw of parsed.swarms) {
    sw._position = findEmptyPosition(sw._width, sw._height);
    // Reposition member sentants relative to swarm
    const members = parsed.sentants.filter((s) => s._swarmId === sw._nodeId);
    // Members keep their relative positions inside the swarm — no adjustment needed
  }

  // Position standalone sentants
  for (const s of parsed.sentants) {
    if (!s._swarmId) {
      s._position = findEmptyPosition(200, 120);
    }
  }

  model.swarms = [...model.swarms, ...parsed.swarms];
  model.sentants = [...model.sentants, ...parsed.sentants];
}

/** Replace a single sentant in-place from edited YAML/JSON. Preserves _nodeId, _position, _swarmId. */
export function updateSentantFromContent(nodeId: string, content: string, format: "yaml" | "json"): { ok: boolean; error?: string } {
  try {
    const parsed = format === "json" ? jsonToCanvas(content) : yamlToCanvas(content);
    // The parsed result may be a single sentant or a swarm containing the sentant
    const idx = model.sentants.findIndex(s => s._nodeId === nodeId);
    if (idx < 0) return { ok: false, error: "Sentant not found" };
    const existing = model.sentants[idx];

    if (parsed.swarms.length > 0) {
      // Edited as a swarm — update the swarm and all its member sentants
      const swarmId = existing._swarmId;
      if (swarmId) {
        const swarmIdx = model.swarms.findIndex(s => s._nodeId === swarmId);
        if (swarmIdx >= 0) {
          const oldSwarm = model.swarms[swarmIdx];
          model.swarms[swarmIdx] = { ...oldSwarm, name: parsed.swarms[0].name || oldSwarm.name, description: parsed.swarms[0].description || "" };
        }
        // Replace member sentants, preserving canvas metadata
        const oldMembers = model.sentants.filter(s => s._swarmId === swarmId);
        const newMembers = parsed.sentants;
        const remaining = model.sentants.filter(s => s._swarmId !== swarmId);
        for (let i = 0; i < newMembers.length; i++) {
          const old = oldMembers[i];
          if (old) {
            newMembers[i]._nodeId = old._nodeId;
            newMembers[i]._position = old._position;
            newMembers[i]._swarmId = swarmId;
          } else {
            newMembers[i]._nodeId = `node-${nextId++}`;
            newMembers[i]._position = { x: 30 + i * 320, y: 50 };
            newMembers[i]._swarmId = swarmId;
          }
        }
        model.sentants = [...remaining, ...newMembers];
      }
    } else if (parsed.sentants.length > 0) {
      // Single sentant edit — update in place preserving canvas metadata
      const updated = parsed.sentants[0];
      updated._nodeId = existing._nodeId;
      updated._position = existing._position;
      updated._swarmId = existing._swarmId;
      model.sentants[idx] = updated;
    } else {
      return { ok: false, error: "No sentants or swarms found in definition" };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, error: (err as Error).message || "Parse error" };
  }
}

/** Replace a swarm and its members in-place from edited YAML/JSON. */
export function updateSwarmFromContent(nodeId: string, content: string, format: "yaml" | "json"): { ok: boolean; error?: string } {
  try {
    const parsed = format === "json" ? jsonToCanvas(content) : yamlToCanvas(content);
    if (parsed.swarms.length === 0) return { ok: false, error: "No swarm found in definition" };
    const swarmIdx = model.swarms.findIndex(s => s._nodeId === nodeId);
    if (swarmIdx < 0) return { ok: false, error: "Swarm not found" };
    const oldSwarm = model.swarms[swarmIdx];

    // Update swarm metadata
    model.swarms[swarmIdx] = { ...oldSwarm, name: parsed.swarms[0].name || oldSwarm.name, description: parsed.swarms[0].description || "" };

    // Replace member sentants, preserving canvas metadata
    const oldMembers = model.sentants.filter(s => s._swarmId === nodeId);
    const newMembers = parsed.sentants;
    const remaining = model.sentants.filter(s => s._swarmId !== nodeId);
    for (let i = 0; i < newMembers.length; i++) {
      const old = oldMembers[i];
      if (old) {
        newMembers[i]._nodeId = old._nodeId;
        newMembers[i]._position = old._position;
        newMembers[i]._swarmId = nodeId;
      } else {
        newMembers[i]._nodeId = `node-${nextId++}`;
        newMembers[i]._position = { x: 30 + i * 320, y: 50 };
        newMembers[i]._swarmId = nodeId;
      }
    }
    model.sentants = [...remaining, ...newMembers];
    return { ok: true };
  } catch (err) {
    return { ok: false, error: (err as Error).message || "Parse error" };
  }
}

export function loadFromContentSafe(content: string, format: "yaml" | "json"): { ok: boolean; error?: string } {
  try {
    const parsed = format === "json" ? jsonToCanvas(content) : yamlToCanvas(content);
    if (parsed.sentants.length === 0 && parsed.swarms.length === 0) {
      return { ok: false, error: "No sentants or swarms found in definition" };
    }
    model.swarms = parsed.swarms;
    model.sentants = parsed.sentants;
    nextId = parsed.sentants.length + parsed.swarms.length + 1;
    selectedNodeId = null;
    return { ok: true };
  } catch (err) {
    return { ok: false, error: (err as Error).message || "Parse error" };
  }
}

// --- Live sentant functions ---

export function setLiveSentants(sentants: LiveSentantModel[]): void {
  model.liveSentants = sentants;
}

export function clearLiveSentants(): void {
  signalMessages = {};
  model.liveSentants = [];
  hiveGroups = [];
  liveSwarmGroups = [];
}

export function updateLiveSentantPosition(nodeId: string, position: { x: number; y: number }): void {
  model.liveSentants = model.liveSentants.map((s) =>
    s._nodeId === nodeId ? { ...s, _position: position } : s
  );
}

export function addSignalMessage(nodeId: string, event: string, data: string): void {
  const MAX_MESSAGES = 10;
  const current = signalMessages[nodeId] ?? [];
  const time = new Date().toLocaleTimeString();
  const updated = [...current, { time, event, data }];
  if (updated.length > MAX_MESSAGES) updated.splice(0, updated.length - MAX_MESSAGES);
  signalMessages = { ...signalMessages, [nodeId]: updated };
}

// --- Hive group functions ---

export function setHiveGroups(groups: HiveGroupModel[]): void {
  hiveGroups = groups;
}

export function setLiveSwarmGroups(groups: LiveSwarmGroupModel[]): void {
  liveSwarmGroups = groups;
}

export function updateHiveGroupPosition(nodeId: string, position: { x: number; y: number }): void {
  hiveGroups = hiveGroups.map((g) =>
    g._nodeId === nodeId ? { ...g, _position: position } : g
  );
}

// --- Edge derivation ---

export function getEdges(): Array<{ id: string; source: string; target: string; label: string; animated: boolean }> {
  const nameToNodeId = new Map<string, string>();
  for (const s of model.sentants) nameToNodeId.set(s.name, s._nodeId);
  for (const s of model.liveSentants) nameToNodeId.set(s.name, s._nodeId);

  // Collect events per source→target pair, then consolidate into single edges
  const pairEvents = new Map<string, { source: string; target: string; events: Set<string> }>();

  for (const s of model.sentants) {
    for (const auto of s.automations) {
      for (const trans of auto.transitions) {
        for (const action of trans.actions) {
          if (action.command === "send" && action.parameters) {
            const targetName = action.parameters.to as string | undefined;
            const eventName = action.parameters.event as string | undefined;
            if (targetName && nameToNodeId.has(targetName)) {
              const targetNodeId = nameToNodeId.get(targetName)!;
              if (targetNodeId !== s._nodeId) {
                const pairKey = `${s._nodeId}||${targetNodeId}`;
                if (!pairEvents.has(pairKey)) {
                  pairEvents.set(pairKey, { source: s._nodeId, target: targetNodeId, events: new Set() });
                }
                pairEvents.get(pairKey)!.events.add(eventName ?? "send");
              }
            }
          }
        }
      }
    }
  }

  const edges: Array<{ id: string; source: string; target: string; label: string; animated: boolean }> = [];
  for (const [pairKey, pair] of pairEvents) {
    const label = [...pair.events].join(", ");
    edges.push({ id: `edge-${pairKey}`, source: pair.source, target: pair.target, label, animated: true });
  }
  return edges;
}

export function getPublicEvents(nodeId: string): string[] {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return [];
  const events = new Set<string>();
  for (const auto of sentant.automations) {
    for (const trans of auto.transitions) {
      if (trans.public) events.add(trans.event);
    }
  }
  return [...events];
}

export function getSignalEvents(nodeId: string): string[] {
  const sentant = model.sentants.find((s) => s._nodeId === nodeId);
  if (!sentant) return [];
  const signals = new Set<string>();
  for (const auto of sentant.automations) {
    for (const trans of auto.transitions) {
      for (const action of trans.actions) {
        if (action.command === "signal" && action.parameters?.event) {
          signals.add(action.parameters.event as string);
        }
      }
    }
  }
  return [...signals];
}

export function clearCanvas(): void {
  model.swarms = [];
  model.sentants = [];
  nextId = 1;
  selectedNodeId = null;
  resetCounters();
}
