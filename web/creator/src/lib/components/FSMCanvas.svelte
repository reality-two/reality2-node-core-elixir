<script lang="ts">
  import { SvelteFlow, Controls, Background, BackgroundVariant, MarkerType } from "@xyflow/svelte";
  import "@xyflow/svelte/dist/style.css";
  import FSMStateNode from "./FSMStateNode.svelte";
  import FSMStartNode from "./FSMStartNode.svelte";
  import FSMWildcardNode from "./FSMWildcardNode.svelte";
  import FSMAntennaNode from "./FSMAntennaNode.svelte";
  import FSMCommandNode from "./FSMCommandNode.svelte";
  import FSMSignalNode from "./FSMSignalNode.svelte";
  import FSMSendNode from "./FSMSendNode.svelte";
  import { extractStates, extractEdges, layoutStates } from "../fsm/fsm-utils";
  import { updateAutomation } from "../stores/canvas-store.svelte";
  import type { AutomationModel, PluginModel } from "../models/canvas";

  let {
    automation,
    plugins = [],
    sentantNodeId,
    autoIndex,
    selectedTransitionIndex = null,
    onSelectTransition,
    onDeselectTransition,
    onAddTransitionBetween,
  }: {
    automation: AutomationModel;
    plugins?: PluginModel[];
    sentantNodeId: string;
    autoIndex: number;
    selectedTransitionIndex?: number | null;
    onSelectTransition: (idx: number) => void;
    onDeselectTransition: () => void;
    onAddTransitionBetween: (from: string | undefined, to: string | undefined) => void;
  } = $props();

  const nodeTypes = {
    fsmState: FSMStateNode,
    fsmStart: FSMStartNode,
    fsmWildcard: FSMWildcardNode,
    fsmAntenna: FSMAntennaNode,
    fsmCommand: FSMCommandNode,
    fsmSignal: FSMSignalNode,
    fsmSend: FSMSendNode,
  };

  let fsmStates = $derived(extractStates(automation, plugins));
  let fsmEdges = $derived(extractEdges(automation, fsmStates, plugins));
  let autoPositions = $derived(layoutStates(fsmStates, fsmEdges));

  function getPosition(state: { id: string; name: string }): { x: number; y: number } {
    // Use id for position lookup (unique per node, even for commands with same event names)
    return automation._fsmPositions?.[state.id] ?? autoPositions[state.id] ?? { x: 0, y: 0 };
  }

  function getNodeType(s: { isStart: boolean; isWildcard: boolean; isAntenna: boolean; isCommand: boolean; isSignal: boolean; isSend: boolean }): string {
    if (s.isStart) return "fsmStart";
    if (s.isWildcard) return "fsmWildcard";
    if (s.isAntenna) return "fsmAntenna";
    if (s.isSignal) return "fsmSignal";
    if (s.isSend) return "fsmSend";
    if (s.isCommand) return "fsmCommand";
    return "fsmState";
  }

  let nodes = $derived(
    fsmStates.map((s) => ({
      id: s.id,
      type: getNodeType(s),
      position: getPosition(s),
      data: { state: s },
      draggable: true,
    }))
  );

  // Build sets of special node IDs for edge coloring
  let signalNodeIds = $derived(new Set(fsmStates.filter(s => s.isSignal).map(s => s.id)));
  let sendNodeIds = $derived(new Set(fsmStates.filter(s => s.isSend).map(s => s.id)));
  let sendNodeTypes = $derived(new Map(fsmStates.filter(s => s.isSend).map(s => [s.id, s.sendType ?? "bee"])));

  function edgeColor(e: { isAntennaLink: boolean; target: string }, selected: boolean): string {
    if (selected) return "#e6a817";
    if (signalNodeIds.has(e.target)) return "#43a047";
    if (sendNodeIds.has(e.target)) {
      const st = sendNodeTypes.get(e.target);
      if (st === "reply") return "#00838f";
      if (st === "broadcast") return "#e65100";
      if (st === "self") return "#888";
      return "#ab7dd6";
    }
    if (e.isAntennaLink) return "#5b9bd5";
    return "#c4a84d";
  }

  // Detect reciprocal edges (A→B and B→A) and parallel edges (multiple A→B)
  // to offset their paths so labels don't overlap
  function buildEdgeOffsets(fedges: typeof fsmEdges) {
    const offsets = new Map();
    const pairEdges = new Map();
    for (const e of fedges) {
      const pair = [e.source, e.target].sort().join("||");
      if (!pairEdges.has(pair)) pairEdges.set(pair, []);
      pairEdges.get(pair).push(e.id);
    }
    for (const [, ids] of pairEdges) {
      if (ids.length < 2) continue;
      const step = 30;
      const start = -step * (ids.length - 1) / 2;
      for (let i = 0; i < ids.length; i++) {
        offsets.set(ids[i], start + i * step);
      }
    }
    return offsets;
  }

  let edgeOffsets = $derived(buildEdgeOffsets(fsmEdges));

  let edges = $derived(
    fsmEdges.map((e) => {
      const selected = selectedTransitionIndex === e.transitionIndex;
      const isSignalEdge = signalNodeIds.has(e.target);
      const isSendEdge = sendNodeIds.has(e.target);
      const color = edgeColor(e, selected);
      const hasLabel = e.event && e.event.length > 0;
      const offset = edgeOffsets.get(e.id) ?? 0;
      return {
        id: e.id,
        source: e.source,
        target: e.target,
        sourceHandle: e.sourceHandle,
        targetHandle: e.targetHandle,
        type: "smoothstep",
        pathOptions: offset !== 0 ? { offset } : undefined,
        label: hasLabel ? (e.isPublic ? `${e.event} [pub]` : e.event) : undefined,
        animated: selected || e.isAntennaLink,
        markerEnd: { type: MarkerType.ArrowClosed, color },
        style: selected
          ? `stroke: ${color}; stroke-width: 3px;`
          : isSignalEdge || isSendEdge
            ? `stroke: ${color}; stroke-width: 1.5px; stroke-dasharray: 6 3;`
            : `stroke: ${color}; stroke-width: 2px;`,
        labelStyle: hasLabel ? (selected
          ? `font-size: 10px; font-weight: 700; fill: ${color};`
          : `font-size: 10px; font-weight: 600; fill: ${e.isAntennaLink ? '#3a7bb8' : '#8a7530'};`) : undefined,
        labelBgStyle: undefined,
        labelBgPadding: undefined,
        labelBgBorderRadius: undefined,
        data: { transitionIndex: e.transitionIndex },
        zIndex: selected ? 1000 : undefined,
      };
    })
  );

  function handleEdgeClick({ edge }: { edge: any }) {
    onSelectTransition(edge.data.transitionIndex);
  }

  function handleNodeClick({ node }: { node: any }) {
    // Command and signal nodes are clickable to select their transition
    const state = node.data?.state;
    if ((state?.isCommand || state?.isSignal || state?.isSend) && state.transitionIndex !== undefined) {
      onSelectTransition(state.transitionIndex);
    }
  }

  function handlePaneClick() {
    onDeselectTransition();
  }

  function handleNodeDragStop({ targetNode }: { targetNode: any }) {
    if (!targetNode) return;
    const state = targetNode.data?.state;
    if (!state) return;

    const current = automation._fsmPositions ?? {};
    const updated = { ...current, [state.id]: targetNode.position };
    updateAutomation(sentantNodeId, autoIndex, { _fsmPositions: updated });
  }

  function handleConnect({ source, target }: { source: string; target: string }) {
    const sourceState = fsmStates.find((s) => s.id === source);
    const targetState = fsmStates.find((s) => s.id === target);
    if (!sourceState || !targetState) return;

    const from = sourceState.isWildcard ? "*" : sourceState.isStart ? "start" : (sourceState.isAntenna || sourceState.isCommand) ? undefined : sourceState.name;
    const to = targetState.isWildcard ? undefined : (targetState.isAntenna || targetState.isCommand) ? undefined : targetState.name;
    onAddTransitionBetween(from, to);
  }
</script>

<div class="fsm-canvas-wrapper">
  <SvelteFlow
    {nodes}
    {edges}
    {nodeTypes}
    onedgeclick={handleEdgeClick}
    onnodeclick={handleNodeClick}
    onpaneclick={handlePaneClick}
    onnodedragstop={handleNodeDragStop}
    onconnect={handleConnect}
    fitView
    defaultEdgeOptions={{ type: "smoothstep" }}
  >
    <Controls />
    <Background variant={BackgroundVariant.Dots} gap={20} size={1} color="#e8e0c8" />
  </SvelteFlow>
</div>

<style>
  .fsm-canvas-wrapper {
    width: 100%;
    height: 100%;
  }
</style>
