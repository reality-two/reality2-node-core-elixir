import yaml from "js-yaml";
import type {
  CanvasModel,
  SentantModel,
  SwarmModel,
  AutomationModel,
  TransitionModel,
  ActionModel,
  PluginModel,
} from "./canvas";
import { createEmptyCanvas } from "./canvas";

function stripCanvasMetadata(sentant: SentantModel): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  result.name = sentant.name;
  if (sentant.description) result.description = sentant.description;
  if (Object.keys(sentant.data).length > 0) result.data = sentant.data;
  if (sentant.plugins.length > 0) result.plugins = sentant.plugins.map(serializePlugin);
  if (sentant.automations.length > 0) {
    result.automations = sentant.automations.map(serializeAutomation);
  }
  return result;
}

function serializeAutomation(auto: AutomationModel): Record<string, unknown> {
  const result: Record<string, unknown> = { name: auto.name };
  if (auto.description) result.description = auto.description;
  if (auto.transitions.length > 0) {
    result.transitions = auto.transitions.map(serializeTransition);
  }
  return result;
}

function serializeTransition(trans: TransitionModel): Record<string, unknown> {
  const result: Record<string, unknown> = { event: trans.event };
  if (trans.from) result.from = trans.from;
  if (trans.to) result.to = trans.to;
  if (trans.public) result.public = trans.public;
  if (trans.parameters && Object.keys(trans.parameters).length > 0) {
    result.parameters = trans.parameters;
  }
  if (trans.actions.length > 0) {
    result.actions = trans.actions.map(serializeAction);
  }
  return result;
}

function serializeAction(action: ActionModel): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  if (action.plugin) result.plugin = action.plugin;
  result.command = action.command;
  if (action.parameters && Object.keys(action.parameters).length > 0) {
    result.parameters = action.parameters;
  }
  return result;
}

function serializePlugin(plugin: PluginModel): Record<string, unknown> {
  const result: Record<string, unknown> = { name: plugin.name };
  if (plugin.description) result.description = plugin.description;
  result.url = plugin.url;
  result.method = plugin.method;
  if (Object.keys(plugin.headers).length > 0) result.headers = plugin.headers;
  if (plugin.parameters && Object.keys(plugin.parameters).length > 0) {
    result.parameters = plugin.parameters;
  }
  if (plugin.body !== undefined && plugin.body !== null) result.body = plugin.body;
  if (plugin.output) result.output = plugin.output;
  return result;
}

/** Generate YAML for a single sentant, or its containing swarm if it belongs to one. */
export function sentantToYaml(sentant: SentantModel, model: CanvasModel): string {
  if (sentant._swarmId) {
    const swarm = model.swarms.find((s) => s._nodeId === sentant._swarmId);
    if (swarm) {
      return swarmToYaml(swarm, model);
    }
  }
  const block = { sentant: stripCanvasMetadata(sentant) };
  return yaml.dump(block, { sortKeys: false, lineWidth: -1, noRefs: true });
}

/** Generate YAML for a swarm and all its member sentants. */
export function swarmToYaml(swarm: SwarmModel, model: CanvasModel): string {
  const members = model.sentants.filter((s) => s._swarmId === swarm._nodeId);
  const block = {
    swarm: {
      name: swarm.name || "New Swarm",
      ...(swarm.description ? { description: swarm.description } : {}),
      sentants: members.map(stripCanvasMetadata),
    },
  };
  return yaml.dump(block, { sortKeys: false, lineWidth: -1, noRefs: true });
}

/** Generate JSON for a single sentant, or its containing swarm if it belongs to one. */
export function sentantToJson(sentant: SentantModel, model: CanvasModel): string {
  if (sentant._swarmId) {
    const swarm = model.swarms.find((s) => s._nodeId === sentant._swarmId);
    if (swarm) {
      return swarmToJson(swarm, model);
    }
  }
  return JSON.stringify({ sentant: stripCanvasMetadata(sentant) }, null, 2);
}

/** Generate JSON for a swarm and all its member sentants. */
export function swarmToJson(swarm: SwarmModel, model: CanvasModel): string {
  const members = model.sentants.filter((s) => s._swarmId === swarm._nodeId);
  return JSON.stringify({
    swarm: {
      name: swarm.name || "New Swarm",
      ...(swarm.description ? { description: swarm.description } : {}),
      sentants: members.map(stripCanvasMetadata),
    },
  }, null, 2);
}

export function canvasToYaml(model: CanvasModel): string {
  const blocks = canvasToBlocks(model);
  if (blocks.length === 0) return "";
  if (blocks.length === 1) {
    return yaml.dump(blocks[0], { sortKeys: false, lineWidth: -1, noRefs: true });
  }
  // Multiple definitions: output each separated by ---
  return blocks.map((b) =>
    yaml.dump(b, { sortKeys: false, lineWidth: -1, noRefs: true })
  ).join("---\n");
}

export function canvasToJson(model: CanvasModel): string {
  const blocks = canvasToBlocks(model);
  if (blocks.length === 0) return "{}";
  if (blocks.length === 1) return JSON.stringify(blocks[0], null, 2);
  return JSON.stringify(blocks, null, 2);
}

function canvasToBlocks(model: CanvasModel): Record<string, unknown>[] {
  const blocks: Record<string, unknown>[] = [];

  // Swarm blocks
  for (const swarm of model.swarms) {
    const members = model.sentants.filter((s) => s._swarmId === swarm._nodeId);
    if (members.length > 0) {
      blocks.push({
        swarm: {
          name: swarm.name || "New Swarm",
          ...(swarm.description ? { description: swarm.description } : {}),
          sentants: members.map(stripCanvasMetadata),
        },
      });
    }
  }

  // Standalone sentants (not in any swarm)
  const standalone = model.sentants.filter((s) => !s._swarmId);
  for (const s of standalone) {
    blocks.push({ sentant: stripCanvasMetadata(s) });
  }

  return blocks;
}

export function jsonToCanvas(jsonStr: string): CanvasModel {
  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonStr);
  } catch {
    return createEmptyCanvas();
  }
  return parsedToCanvas(parsed);
}

export function yamlToCanvas(yamlStr: string): CanvasModel {
  let parsed: unknown;
  try {
    parsed = yaml.load(yamlStr);
  } catch {
    return createEmptyCanvas();
  }
  return parsedToCanvas(parsed);
}

function parsedToCanvas(parsed: unknown): CanvasModel {
  if (!parsed || typeof parsed !== "object") {
    return createEmptyCanvas();
  }

  const obj = parsed as Record<string, unknown>;

  if (obj.sentant) {
    const sentant = parseSentant(obj.sentant as Record<string, unknown>, "node-1", { x: 100, y: 100 });
    return { swarms: [], sentants: [sentant], liveSentants: [] };
  }

  if (obj.swarm) {
    const swarm = obj.swarm as Record<string, unknown>;
    const swarmId = "swarm-1";
    const sentantDefs = (swarm.sentants as Record<string, unknown>[]) || [];
    const CARD_COL = 320;
    const CARD_ROW = 280;
    const PAD_X = 30;
    const PAD_TOP = 50;
    const PAD_BOT = 20;
    const MAX_COLS = 4;
    const sentants = sentantDefs.map((s, i) => {
      const sentant = parseSentant(s, `node-${i + 1}`, { x: PAD_X + (i % MAX_COLS) * CARD_COL, y: PAD_TOP + Math.floor(i / MAX_COLS) * CARD_ROW });
      sentant._swarmId = swarmId;
      return sentant;
    });
    const cols = Math.min(sentants.length, MAX_COLS);
    const rows = Math.ceil(sentants.length / MAX_COLS);
    return {
      swarms: [{
        _nodeId: swarmId,
        _position: { x: 20, y: 20 },
        _width: cols * CARD_COL + PAD_X * 2,
        _height: rows * CARD_ROW + PAD_TOP + PAD_BOT,
        name: (swarm.name as string) || "",
        description: (swarm.description as string) || "",
      }],
      sentants,
      liveSentants: [],
    };
  }

  return createEmptyCanvas();
}

function parseSentant(
  obj: Record<string, unknown>,
  nodeId: string,
  position: { x: number; y: number }
): SentantModel {
  return {
    _nodeId: nodeId,
    _position: position,
    name: (obj.name as string) || "Unnamed",
    description: (obj.description as string) || "",
    data: (obj.data as Record<string, unknown>) || {},
    plugins: ((obj.plugins as Record<string, unknown>[]) || []).map(parsePlugin),
    automations: ((obj.automations as Record<string, unknown>[]) || []).map(parseAutomation),
  };
}

function parsePlugin(obj: Record<string, unknown>): PluginModel {
  return {
    name: (obj.name as string) || "",
    description: obj.description as string | undefined,
    url: (obj.url as string) || "",
    method: (obj.method as string) || "GET",
    headers: (obj.headers as Record<string, string>) || {},
    parameters: obj.parameters as Record<string, string> | undefined,
    body: obj.body as Record<string, unknown> | string | undefined,
    output: obj.output as { key: string; value?: string; event: string } | undefined,
  };
}

function parseAutomation(obj: Record<string, unknown>): AutomationModel {
  return {
    name: (obj.name as string) || "",
    description: obj.description as string | undefined,
    transitions: ((obj.transitions as Record<string, unknown>[]) || []).map(parseTransition),
  };
}

function parseTransition(obj: Record<string, unknown>): TransitionModel {
  return {
    event: (obj.event as string) || "",
    from: obj.from as string | undefined,
    to: obj.to as string | undefined,
    public: obj.public as boolean | undefined,
    parameters: obj.parameters as Record<string, string> | undefined,
    actions: ((obj.actions as Record<string, unknown>[]) || []).map(parseAction),
  };
}

function parseAction(obj: Record<string, unknown>): ActionModel {
  return {
    command: (obj.command as string) || "signal",
    plugin: obj.plugin as string | undefined,
    parameters: obj.parameters as Record<string, unknown> | undefined,
  };
}
