<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import Canvas from "./lib/components/Canvas.svelte";
  import Toolbar from "./lib/components/Toolbar.svelte";
  import SentantEditor from "./lib/components/SentantEditor.svelte";
  import SwarmEditor from "./lib/components/SwarmEditor.svelte";
  import LiveSentantEditor from "./lib/components/LiveSentantEditor.svelte";
  import HivePanel from "./lib/components/HivePanel.svelte";
  import LibraryPanel from "./lib/components/LibraryPanel.svelte";
  import YamlPreview from "./lib/components/YamlPreview.svelte";
  import R2 from "./lib/reality2";
  import { DEFAULT_PORT, RESERVED_SENTANT_NAMES } from "./lib/constants";
  import {
    addSentant,
    addSwarm,
    getModel,
    getSelectedSentant,
    getSelectedLiveSentant,
    getSelectedSwarm,
    getSentants,
    getSwarms,
    getLiveSentants,
    getYaml,
    getSentantYaml,
    getSentantJson,
    getSwarmYaml,
    getSwarmJson,
    loadFromYaml,
    loadFromContent,
    mergeContent,
    clearCanvas,
    setLiveSentants,
    clearLiveSentants,
    setHiveGroups,
    addSignalMessage,
    selectNode,
    removeSentant,
    removeSwarm,
    assignSentantToSwarm,
    findEmptyPosition,
    updateSentantFromContent,
    updateSwarmFromContent,
    setLiveSwarmGroups,
  } from "./lib/stores/canvas-store.svelte";
  import { sentantToYaml, swarmToYaml } from "./lib/models/serializer";
  import { replaceVariables, getVariableCount } from "./lib/stores/variables-store.svelte";
  import VariablesPanel from "./lib/components/VariablesPanel.svelte";
  import type { HiveGroupModel, LiveSwarmGroupModel } from "./lib/models/canvas";

  const r2 = new R2(window.location.hostname, parseInt(DEFAULT_PORT), true);

  onMount(() => {
    handleBrowseNode();
  });

  let statusMessage = $state("");
  let editingNodeId = $state<string | null>(null);
  let showHivePanel = $state(false);
  let showLibraryPanel = $state(false);
  let showVariablesPanel = $state(false);

  // Hive panel data
  let hiveNodeInfo = $state<any>(null);
  let hivePeers = $state<any[]>([]);
  let hiveDirectory = $state<any>(null);

  let liveSentantCount = $derived(getLiveSentants().length);

  // The item being edited (drill-in view)
  let editingSentant = $derived(
    editingNodeId
      ? getSentants().find((s) => s._nodeId === editingNodeId) ?? null
      : null
  );
  let editingSwarm = $derived(
    editingNodeId && !editingSentant
      ? getSwarms().find((s) => s._nodeId === editingNodeId) ?? null
      : null
  );
  let editingLiveSentant = $derived(
    editingNodeId && !editingSentant && !editingSwarm
      ? getLiveSentants().find((s) => s._nodeId === editingNodeId) ?? null
      : null
  );

  // Toolbar mode
  let toolbarMode = $derived<"canvas" | "editing" | "swarm" | "live" | "hive" | "library" | "variables">(
    showVariablesPanel
      ? "variables"
      : showLibraryPanel
        ? "library"
        : showHivePanel
          ? "hive"
          : editingSwarm
            ? "swarm"
            : editingNodeId
              ? (editingNodeId.startsWith("live-") ? "live" : "editing")
              : "canvas"
  );

  let editingName = $derived(editingSentant?.name ?? editingSwarm?.name ?? editingLiveSentant?.name ?? "");

  function handleDeleteSentant() {
    if (editingNodeId) {
      const id = editingNodeId;
      editingNodeId = null;
      removeSentant(id);
    }
  }

  function handleDeleteSwarm() {
    if (!editingSwarm) return;
    if (!confirm(`Delete swarm "${editingSwarm.name}"? Sentants inside will be unparented.`)) return;
    const id = editingNodeId!;
    editingNodeId = null;
    removeSwarm(id);
  }

  async function handleUnload() {
    if (!editingLiveSentant) return;
    if (!confirm(`Unload "${editingLiveSentant.name}" from the node?`)) return;
    try {
      const sentantId = editingLiveSentant.id;
      const name = editingLiveSentant.name;
      const nodeId = editingLiveSentant._nodeId;

      const toRemove = activeSubscriptions.filter((s) => s.id === sentantId);
      for (const sub of toRemove) {
        r2.unsubscribe(sub.id, sub.signal);
      }
      activeSubscriptions = activeSubscriptions.filter((s) => s.id !== sentantId);

      await r2.sentantUnload(sentantId);

      editingNodeId = null;
      const remaining = getLiveSentants().filter((s) => s._nodeId !== nodeId);
      setLiveSentants(remaining);

      showStatus(`Unloaded: ${name}`);
    } catch (err) {
      showStatus("Unload error: " + (err as Error).message);
    }
  }

  // Track active signal subscriptions
  let activeSubscriptions: Array<{ id: string; signal: string }> = [];

  function showStatus(msg: string) {
    statusMessage = msg;
    setTimeout(() => { statusMessage = ""; }, 3000);
  }

  function cleanupSubscriptions() {
    for (const sub of activeSubscriptions) {
      r2.unsubscribe(sub.id, sub.signal);
    }
    activeSubscriptions = [];
  }

  onDestroy(() => {
    cleanupSubscriptions();
  });

  function handleEnterNode(nodeId: string) {
    editingNodeId = nodeId;
  }

  function handleBackToCanvas() {
    editingNodeId = null;
    showHivePanel = false;
    showLibraryPanel = false;
    showVariablesPanel = false;
    handleBrowseNode();
  }

  function handleOpenLibrary() {
    showLibraryPanel = true;
    showHivePanel = false;
    showVariablesPanel = false;
    editingNodeId = null;
  }

  function handleOpenVariables() {
    showVariablesPanel = true;
    showHivePanel = false;
    showLibraryPanel = false;
    editingNodeId = null;
  }

  function handleLibraryLoad(content: string, name: string, format: "yaml" | "json" = "yaml") {
    mergeContent(content, format);
    showLibraryPanel = false;
    showStatus(`Loaded: ${name}`);
  }

  // --- Hive panel ---

  async function fetchHiveData() {
    try {
      const [infoResult, peersResult, dirResult]: any[] = await Promise.all([
        r2.nodeInfo({}, "nodeId nodeName hiveId hiveName hiveMode hiveCompressedId isProvisional version buildId"),
        r2.peers(),
        r2.hiveDirectory(),
      ]);
      hiveNodeInfo = infoResult?.data?.nodeInfo ?? null;
      hivePeers = peersResult?.data?.peers ?? [];
      hiveDirectory = dirResult?.data?.hiveDirectory ?? null;
    } catch (err) {
      showStatus("Hive fetch error: " + (err as Error).message);
    }
  }

  function handleOpenHive() {
    showHivePanel = true;
    showVariablesPanel = false;
    showLibraryPanel = false;
    editingNodeId = null;
    fetchHiveData();
  }

  // --- Browse Node ---

  async function handleBrowseNode() {
    try {
      const [nodeInfoResult, sentantsResult]: any[] = await Promise.all([
        r2.nodeInfo({}, "nodeId nodeName hiveId hiveName hiveMode version buildId"),
        r2.sentantAll({}, "id name swarm description events { event parameters } signals nodeId nodeName"),
      ]);

      const info = nodeInfoResult?.data?.nodeInfo;
      const thisNodeId = info?.nodeId;

      const sentants = sentantsResult?.data?.sentantAll ?? [];
      const reserved = Object.values(RESERVED_SENTANT_NAMES);
      const filtered = sentants.filter(
        (s: any) => !reserved.includes(s.name)
      );

      if (filtered.length === 0) {
        clearLiveSentants();
        showStatus("No sentants on node");
        return;
      }

      cleanupSubscriptions();

      // Group sentants by node, then by swarm within each node
      type NodeGroup = { nodeId: string; nodeName: string; swarms: Map<string, any[]>; loose: any[] };
      const nodeGroups: Map<string, NodeGroup> = new Map();
      for (const s of filtered) {
        const nid = s.nodeId || thisNodeId || "local";
        if (!nodeGroups.has(nid)) {
          nodeGroups.set(nid, { nodeId: nid, nodeName: s.nodeName || "Unknown Node", swarms: new Map(), loose: [] });
        }
        const ng = nodeGroups.get(nid)!;
        if (s.swarm) {
          if (!ng.swarms.has(s.swarm)) ng.swarms.set(s.swarm, []);
          ng.swarms.get(s.swarm)!.push(s);
        } else {
          ng.loose.push(s);
        }
      }

      const CARD_COL = 320;
      const CARD_ROW = 280;
      const NODE_PAD_X = 30;
      const NODE_PAD_TOP = 50;
      const NODE_PAD_BOT = 20;
      const SWARM_PAD_X = 20;
      const SWARM_PAD_TOP = 40;
      const SWARM_PAD_BOT = 10;
      const SWARM_GAP = 30;
      const MAX_COLS = 4;
      const NODE_GAP = 40;

      // Sort: local node first
      const sortedNodes = [...nodeGroups.entries()].sort(([, a], [, b]) => {
        const aLocal = a.nodeId === thisNodeId ? 0 : 1;
        const bLocal = b.nodeId === thisNodeId ? 0 : 1;
        return aLocal - bLocal;
      });

      const hiveGroupsList: HiveGroupModel[] = [];
      const swarmGroupsList: LiveSwarmGroupModel[] = [];
      const liveSentants: any[] = [];

      let cursorX = 50;
      const startY = 50;

      for (const [, ng] of sortedNodes) {
        const hiveNodeId = `hive-${ng.nodeId}`;

        // Calculate layout: swarms stacked vertically, then loose bees
        let innerCursorY = NODE_PAD_TOP;
        let maxInnerWidth = 0;

        // Swarm sub-groups
        for (const [swarmName, members] of ng.swarms) {
          const swarmNodeId = `liveswarm-${ng.nodeId}-${swarmName}`;
          const cols = Math.min(members.length, MAX_COLS);
          const rows = Math.ceil(members.length / MAX_COLS);
          const swarmWidth = cols * CARD_COL + SWARM_PAD_X * 2;
          const swarmHeight = rows * CARD_ROW + SWARM_PAD_TOP + SWARM_PAD_BOT;

          swarmGroupsList.push({
            _nodeId: swarmNodeId,
            _position: { x: NODE_PAD_X, y: innerCursorY },
            _width: swarmWidth,
            _height: swarmHeight,
            _hiveGroupId: hiveNodeId,
            swarmName,
          });

          for (let i = 0; i < members.length; i++) {
            const s = members[i];
            liveSentants.push({
              _nodeId: `live-${s.id}`,
              _position: { x: SWARM_PAD_X + (i % MAX_COLS) * CARD_COL, y: SWARM_PAD_TOP + Math.floor(i / MAX_COLS) * CARD_ROW },
              _hiveGroupId: swarmNodeId,
              id: s.id,
              name: s.name,
              description: s.description || "",
              events: (s.events ?? []).map((e: any) => ({ event: e.event, parameters: e.parameters ?? undefined })),
              signals: s.signals ?? [],
              nodeId: s.nodeId,
              nodeName: s.nodeName,
            });
          }

          maxInnerWidth = Math.max(maxInnerWidth, swarmWidth);
          innerCursorY += swarmHeight + SWARM_GAP;
        }

        // Loose (non-swarm) bees
        if (ng.loose.length > 0) {
          const cols = Math.min(ng.loose.length, MAX_COLS);
          const looseWidth = cols * CARD_COL + SWARM_PAD_X * 2;
          maxInnerWidth = Math.max(maxInnerWidth, looseWidth);

          for (let i = 0; i < ng.loose.length; i++) {
            const s = ng.loose[i];
            liveSentants.push({
              _nodeId: `live-${s.id}`,
              _position: { x: NODE_PAD_X + (i % MAX_COLS) * CARD_COL, y: innerCursorY + Math.floor(i / MAX_COLS) * CARD_ROW },
              _hiveGroupId: hiveNodeId,
              id: s.id,
              name: s.name,
              description: s.description || "",
              events: (s.events ?? []).map((e: any) => ({ event: e.event, parameters: e.parameters ?? undefined })),
              signals: s.signals ?? [],
              nodeId: s.nodeId,
              nodeName: s.nodeName,
            });
          }

          const looseRows = Math.ceil(ng.loose.length / MAX_COLS);
          innerCursorY += looseRows * CARD_ROW;
        }

        const nodeWidth = maxInnerWidth + NODE_PAD_X * 2;
        const nodeHeight = innerCursorY + NODE_PAD_BOT;

        hiveGroupsList.push({
          _nodeId: hiveNodeId,
          _position: { x: cursorX, y: startY },
          _width: nodeWidth,
          _height: nodeHeight,
          nodeId: ng.nodeId,
          nodeName: ng.nodeName,
          isLocal: ng.nodeId === thisNodeId,
        });

        cursorX += nodeWidth + NODE_GAP;
      }

      setHiveGroups(hiveGroupsList);
      setLiveSwarmGroups(swarmGroupsList);
      setLiveSentants(liveSentants);

      for (const ls of liveSentants) {
        // Only subscribe to signals on local sentants — remote sentants
        // don't exist on this node's subscription system
        if (ls.nodeId && ls.nodeId !== thisNodeId) continue;

        for (const signal of ls.signals) {
          r2.awaitSignal(ls.id, signal, (data: any) => {
            if (data?.event) {
              addSignalMessage(
                ls._nodeId,
                data.event,
                JSON.stringify(data.parameters ?? {})
              );
            }
          });
          activeSubscriptions.push({ id: ls.id, signal });
        }
      }

      const nodeCount = nodeGroups.size;
      showStatus(`Found ${filtered.length} sentant(s) on ${nodeCount} node(s)`);
    } catch (err) {
      showStatus("Browse error: " + (err as Error).message);
    }
  }

  async function handleSendEvent(sentantId: string, event: string, params: Record<string, unknown>): Promise<boolean> {
    try {
      await r2.sentantSend(sentantId, event, params);
      return true;
    } catch {
      return false;
    }
  }

  async function handleDeploy() {
    try {
      // Deploying from swarm editor
      if (editingSwarm) {
        const yamlStr = replaceVariables(swarmToYaml(editingSwarm, getModel()));
        if (!yamlStr) { showStatus("Nothing to deploy"); return; }
        const result: any = await r2.swarmLoad(yamlStr, {}, "id name");
        if (result?.data?.swarmLoad) {
          showStatus(`Deployed swarm: ${editingSwarm.name || result.data.swarmLoad.name}`);
        } else {
          showStatus("Deploy failed — check definition");
        }
        return;
      }

      // Deploying from sentant editor
      if (!editingSentant) {
        showStatus("Open a bee or swarm to deploy it");
        return;
      }

      const yamlStr = replaceVariables(sentantToYaml(editingSentant, getModel()));
      if (!yamlStr) { showStatus("Nothing to deploy"); return; }

      if (editingSentant._swarmId) {
        const result: any = await r2.swarmLoad(yamlStr, {}, "id name");
        if (result?.data?.swarmLoad) {
          const swarm = getSwarms().find((s) => s._nodeId === editingSentant._swarmId);
          showStatus(`Deployed swarm: ${swarm?.name || result.data.swarmLoad.name}`);
        } else {
          showStatus("Deploy failed — check definition");
        }
      } else {
        const name = editingSentant.name;
        const existing: any = await r2.sentantGetByName(name, {}, "id name");
        if (existing?.data?.sentantGet?.id) {
          await r2.sentantUnload(existing.data.sentantGet.id);
        }
        const result: any = await r2.sentantLoad(yamlStr, {}, "id name");
        if (result?.data?.sentantLoad) {
          showStatus(`Deployed: ${result.data.sentantLoad.name}`);
        } else {
          showStatus("Deploy failed — check definition");
        }
      }
    } catch (err) {
      showStatus("Deploy error: " + (err as Error).message);
    }
  }

  function downloadYaml(yamlContent: string, filename: string) {
    const blob = new Blob([yamlContent], { type: "text/yaml" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${filename.replace(/\s+/g, "_")}.bee.yaml`;
    a.click();
    URL.revokeObjectURL(url);
    showStatus("Saved");
  }

  function handleSave() {
    const yaml = getYaml();
    const name = getSwarms()[0]?.name || getSentants()[0]?.name || "definition";
    downloadYaml(yaml, name);
  }

  function handleSaveContext() {
    if (editingSentant) {
      downloadYaml(getSentantYaml(editingSentant._nodeId), editingSentant.name || "bee");
    } else if (editingSwarm) {
      downloadYaml(getSwarmYaml(editingSwarm._nodeId), editingSwarm.name || "swarm");
    }
  }

  function handleImport() {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".yaml,.yml,.json,.toml";
    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        const text = reader.result as string;
        loadFromYaml(text);
        showStatus(`Imported: ${file.name}`);
      };
      reader.readAsText(file);
    };
    input.click();
  }

  function handleClear() {
    cleanupSubscriptions();
    clearLiveSentants();
    clearCanvas();
    editingNodeId = null;
    showStatus("Canvas cleared");
  }
</script>

<main>
  <Toolbar
    mode={toolbarMode}
    {editingName}
    onBack={handleBackToCanvas}
    onAddSentant={() => addSentant()}
    onAddSwarm={() => addSwarm()}
    onDeploy={handleDeploy}
    onBrowseNode={handleBrowseNode}
    onHive={handleOpenHive}
    onLibrary={handleOpenLibrary}
    onSave={editingSentant || editingSwarm ? handleSaveContext : handleSave}
    onImport={handleImport}
    onClear={handleClear}
    onDeleteSentant={handleDeleteSentant}
    onDeleteSwarm={handleDeleteSwarm}
    onUnload={handleUnload}
    onRefreshHive={fetchHiveData}
    onLoadVariables={handleOpenVariables}
    {liveSentantCount}
    variableCount={getVariableCount()}
  />

  <div class="workspace">
    {#if showVariablesPanel}
      <VariablesPanel />
    {:else if showLibraryPanel}
      <LibraryPanel onLoad={handleLibraryLoad} />
    {:else if showHivePanel}
      <HivePanel
        nodeInfo={hiveNodeInfo}
        peers={hivePeers}
        directory={hiveDirectory}
        {r2}
        onRefresh={fetchHiveData}
        onStatus={showStatus}
      />
    {:else if editingSwarm}
      <SwarmEditor swarm={editingSwarm} />
    {:else if editingSentant}
      <SentantEditor sentant={editingSentant} />
    {:else if editingLiveSentant}
      <LiveSentantEditor sentant={editingLiveSentant} onSendEvent={handleSendEvent} />
    {:else}
      <Canvas onEnterNode={handleEnterNode} />
    {/if}
  </div>

  {#if editingSentant}
    <YamlPreview
      yamlGetter={() => getSentantYaml(editingSentant._nodeId)}
      jsonGetter={() => getSentantJson(editingSentant._nodeId)}
      onApply={(content, fmt) => updateSentantFromContent(editingSentant._nodeId, content, fmt)}
    />
  {:else if editingSwarm}
    <YamlPreview
      yamlGetter={() => getSwarmYaml(editingSwarm._nodeId)}
      jsonGetter={() => getSwarmJson(editingSwarm._nodeId)}
      onApply={(content, fmt) => updateSwarmFromContent(editingSwarm._nodeId, content, fmt)}
    />
  {/if}

  {#if statusMessage}
    <div class="toast">{statusMessage}</div>
  {/if}
</main>

<style>
  main {
    display: flex;
    flex-direction: column;
    height: 100vh;
    overflow: hidden;
  }
  .workspace {
    flex: 1;
    display: flex;
    overflow: hidden;
  }
  .toast {
    position: fixed;
    top: 50px;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(0, 0, 0, 0.8);
    color: #fff;
    padding: 8px 20px;
    border-radius: 6px;
    font-size: 13px;
    z-index: 9999;
    pointer-events: none;
    animation: toast-fade 3s ease-in-out;
  }
  @keyframes toast-fade {
    0% { opacity: 0; transform: translateX(-50%) translateY(-8px); }
    10% { opacity: 1; transform: translateX(-50%) translateY(0); }
    80% { opacity: 1; }
    100% { opacity: 0; }
  }
</style>
