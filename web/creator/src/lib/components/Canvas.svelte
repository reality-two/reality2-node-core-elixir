<script lang="ts">
  import { SvelteFlow, Controls, Background, BackgroundVariant, MarkerType } from "@xyflow/svelte";
  import "@xyflow/svelte/dist/style.css";
  import SentantNode from "./SentantNode.svelte";
  import LiveSentantNode from "./LiveSentantNode.svelte";
  import SwarmGroupNode from "./SwarmGroupNode.svelte";
  import HiveGroupNode from "./HiveGroupNode.svelte";
  import LiveSwarmGroupNode from "./LiveSwarmGroupNode.svelte";
  import FitViewOnChange from "./FitViewOnChange.svelte";
  import {
    getSentants,
    getSwarms,
    getLiveSentants,
    getHiveGroups,
    getLiveSwarmGroups,
    getEdges,
    selectNode,
    addSentant,
    updateSentantPosition,
    updateSwarm,
    assignSentantToSwarm,
    updateHiveGroupPosition,
  } from "../stores/canvas-store.svelte";

  let { onEnterNode }: { onEnterNode?: (nodeId: string) => void } = $props();

  const nodeTypes = {
    sentant: SentantNode,
    liveSentant: LiveSentantNode,
    swarmGroup: SwarmGroupNode,
    hiveGroup: HiveGroupNode,
    liveSwarmGroup: LiveSwarmGroupNode,
  };

  // Swarm group nodes
  let swarmNodes = $derived(
    getSwarms().map((s) => ({
      id: s._nodeId,
      type: "swarmGroup" as const,
      position: { ...s._position },
      data: { swarm: s },
      style: `width: ${s._width}px; height: ${s._height}px;`,
      zIndex: 0,
    }))
  );

  // Hive group nodes
  let hiveNodes = $derived(
    getHiveGroups().map((g) => ({
      id: g._nodeId,
      type: "hiveGroup" as const,
      position: { ...g._position },
      data: { group: g },
      style: `width: ${g._width}px; height: ${g._height}px;`,
      zIndex: 0,
    }))
  );

  // Live swarm group nodes (nested inside hive groups)
  let liveSwarmNodes = $derived(
    getLiveSwarmGroups().map((g) => ({
      id: g._nodeId,
      type: "liveSwarmGroup" as const,
      position: { ...g._position },
      data: { group: g },
      style: `width: ${g._width}px; height: ${g._height}px;`,
      zIndex: 0,
      parentId: g._hiveGroupId,
      extent: "parent" as const,
    }))
  );

  // Draft sentant nodes
  let draftNodes = $derived(
    getSentants().map((s) => ({
      id: s._nodeId,
      type: "sentant" as const,
      position: { ...s._position },
      data: { sentant: s },
      zIndex: 1,
      ...(s._swarmId ? { parentId: s._swarmId, extent: "parent" as const, expandParent: true } : {}),
    }))
  );

  // Live sentant nodes
  let liveNodes = $derived(
    getLiveSentants().map((s) => ({
      id: s._nodeId,
      type: "liveSentant" as const,
      position: { ...s._position },
      data: { sentant: s },
      zIndex: 1,
      ...(s._hiveGroupId ? { parentId: s._hiveGroupId, extent: "parent" as const, expandParent: true } : {}),
    }))
  );

  // All nodes: groups first (so children render on top)
  let nodes = $derived([...swarmNodes, ...hiveNodes, ...liveSwarmNodes, ...draftNodes, ...liveNodes]);

  let edges = $derived(
    getEdges().map((e) => ({
      id: e.id,
      source: e.source,
      target: e.target,
      label: e.label,
      animated: e.animated,
      type: "smoothstep",
      markerEnd: { type: MarkerType.ArrowClosed, color: "#4183c4" },
      style: "stroke: #4183c4; stroke-width: 2px;",
      labelStyle: "font-size: 11px; font-weight: 600; fill: #4183c4;",
      labelBgStyle: { fill: "#fff", fillOpacity: 0.9 },
      labelBgPadding: [4, 6] as [number, number],
      labelBgBorderRadius: 3,
    }))
  );

  // Double-click detection
  let lastClickNodeId: string | null = null;
  let lastClickTime = 0;
  const DBLCLICK_MS = 400;

  function handleNodeClick({ node, event }: { node: any; event: MouseEvent | TouchEvent }) {
    // Ignore clicks on hive group nodes
    if (node.type === "hiveGroup") {
      selectNode(node.id);
      return;
    }
    const now = Date.now();
    if (lastClickNodeId === node.id && now - lastClickTime < DBLCLICK_MS) {
      lastClickNodeId = null;
      lastClickTime = 0;
      selectNode(node.id);
      onEnterNode?.(node.id);
    } else {
      lastClickNodeId = node.id;
      lastClickTime = now;
      selectNode(node.id);
    }
  }

  function handleNodeDragStop({ targetNode }: { targetNode: any; nodes: any[]; event: MouseEvent | TouchEvent }) {
    if (!targetNode) return;

    if (targetNode.type === "swarmGroup") {
      updateSwarm(targetNode.id, { _position: targetNode.position });
      return;
    }

    if (targetNode.type === "hiveGroup") {
      updateHiveGroupPosition(targetNode.id, targetNode.position);
      return;
    }

    // For sentant nodes: check if dropped inside a swarm
    if (targetNode.type === "sentant") {
      const sentant = getSentants().find((s) => s._nodeId === targetNode.id);
      if (!sentant) return;

      // Absolute position of the dropped node
      const absX = targetNode.positionAbsolute?.x ?? targetNode.position.x;
      const absY = targetNode.positionAbsolute?.y ?? targetNode.position.y;

      // Find which swarm (if any) the sentant was dropped into
      const swarms = getSwarms();
      let targetSwarm: string | undefined;
      for (const sw of swarms) {
        if (
          absX >= sw._position.x &&
          absX <= sw._position.x + sw._width &&
          absY >= sw._position.y &&
          absY <= sw._position.y + sw._height
        ) {
          targetSwarm = sw._nodeId;
          break;
        }
      }

      const currentSwarm = sentant._swarmId;

      if (targetSwarm && targetSwarm !== currentSwarm) {
        // Dropped into a (different) swarm — convert position to relative
        const sw = swarms.find((s) => s._nodeId === targetSwarm)!;
        const relX = absX - sw._position.x;
        const relY = absY - sw._position.y;
        assignSentantToSwarm(targetNode.id, targetSwarm);
        updateSentantPosition(targetNode.id, { x: relX, y: relY });
      } else if (!targetSwarm && currentSwarm) {
        // Dragged out of a swarm — unparent and use absolute position
        assignSentantToSwarm(targetNode.id, undefined);
        updateSentantPosition(targetNode.id, { x: absX, y: absY });
      } else {
        // Stayed in same context — just update position
        updateSentantPosition(targetNode.id, targetNode.position);
      }
    } else {
      updateSentantPosition(targetNode.id, targetNode.position);
    }
  }

  function handlePaneClick() {
    selectNode(null);
    lastClickNodeId = null;
  }
</script>

<div class="canvas-wrapper">
  <SvelteFlow
    {nodes}
    {edges}
    {nodeTypes}
    onnodeclick={handleNodeClick}
    onnodedragstop={handleNodeDragStop}
    onpaneclick={handlePaneClick}
    fitView
  >
    <FitViewOnChange nodeCount={nodes.length} />
    <Controls />
    <Background variant={BackgroundVariant.Dots} />
  </SvelteFlow>
</div>

<style>
  .canvas-wrapper {
    width: 100%;
    height: 100%;
  }
</style>
