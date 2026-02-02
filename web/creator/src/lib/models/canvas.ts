export interface CanvasModel {
  swarms: SwarmModel[];
  sentants: SentantModel[];
  liveSentants: LiveSentantModel[];
}

export interface SwarmModel {
  _nodeId: string;
  _position: { x: number; y: number };
  _width: number;
  _height: number;
  name: string;
  description: string;
}

export interface SentantModel {
  _nodeId: string;
  _position: { x: number; y: number };
  _swarmId?: string;
  name: string;
  description: string;
  data: Record<string, unknown>;
  plugins: PluginModel[];
  automations: AutomationModel[];
}

export interface LiveSentantModel {
  _nodeId: string;
  _position: { x: number; y: number };
  _hiveGroupId?: string;
  id: string;
  name: string;
  description: string;
  events: Array<{ event: string; parameters?: Record<string, string> }>;
  signals: string[];
  nodeId?: string;
  nodeName?: string;
}

export interface PluginModel {
  name: string;
  description?: string;
  url: string;
  method: string;
  headers: Record<string, string>;
  parameters?: Record<string, string>;
  body?: Record<string, unknown> | string;
  output?: { key: string; value?: string; event: string };
}

export interface AutomationModel {
  name: string;
  description?: string;
  transitions: TransitionModel[];
  _fsmPositions?: Record<string, { x: number; y: number }>;
}

export interface TransitionModel {
  event: string;
  from?: string;
  to?: string;
  public?: boolean;
  parameters?: Record<string, string>;
  actions: ActionModel[];
}

export interface ActionModel {
  command: string;
  plugin?: string;
  parameters?: Record<string, unknown>;
}

export interface HiveGroupModel {
  _nodeId: string;
  _position: { x: number; y: number };
  _width: number;
  _height: number;
  nodeId: string;
  nodeName: string;
  isLocal: boolean;
}

export interface LiveSwarmGroupModel {
  _nodeId: string;
  _position: { x: number; y: number };
  _width: number;
  _height: number;
  _hiveGroupId: string;
  swarmName: string;
}

let sentantCounter = 1;
let swarmCounter = 1;

export function resetCounters(): void {
  sentantCounter = 1;
  swarmCounter = 1;
}

export function createSentant(nodeId: string, position: { x: number; y: number }): SentantModel {
  return {
    _nodeId: nodeId,
    _position: position,
    name: `bee_${sentantCounter++}`,
    description: "",
    data: {},
    plugins: [],
    automations: [],
  };
}

export function createSwarm(nodeId: string, position: { x: number; y: number }): SwarmModel {
  return {
    _nodeId: nodeId,
    _position: position,
    _width: 400,
    _height: 300,
    name: `swarm_${swarmCounter++}`,
    description: "",
  };
}

export function createAutomation(): AutomationModel {
  return {
    name: "New Behaviour",
    transitions: [],
  };
}

export function createTransition(): TransitionModel {
  return {
    event: "new_decision",
    actions: [],
  };
}

export function createAction(): ActionModel {
  return {
    command: "signal",
    parameters: {},
  };
}

export function createPlugin(): PluginModel {
  return {
    name: "com.example.api",
    url: "https://api.example.com",
    method: "GET",
    headers: {},
  };
}

export function createEmptyCanvas(): CanvasModel {
  return {
    swarms: [],
    sentants: [],
    liveSentants: [],
  };
}
