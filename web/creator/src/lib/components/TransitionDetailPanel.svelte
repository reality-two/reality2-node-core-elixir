<script lang="ts">
  import type { TransitionModel } from "../models/canvas";
  import ActionEditor from "./ActionEditor.svelte";
  import DataEditor from "./DataEditor.svelte";
  import {
    updateTransition,
    addAction,
    removeAction,
    updateAction,
    reorderAction,
    removeTransition,
  } from "../stores/canvas-store.svelte";

  let {
    transition,
    sentantNodeId,
    autoIndex,
    transIndex,
    onClose,
  }: {
    transition: TransitionModel;
    sentantNodeId: string;
    autoIndex: number;
    transIndex: number;
    onClose: () => void;
  } = $props();

  let showParams = $state(false);

  // Drag-and-drop reordering for actions
  let dragIndex = $state<number | null>(null);
  let dropIndex = $state<number | null>(null);

  function handleDragStart(e: DragEvent, index: number) {
    dragIndex = index;
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", String(index));
    }
  }

  function handleDragOver(e: DragEvent, index: number) {
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = "move";
    dropIndex = index;
  }

  function handleDragLeave() {
    dropIndex = null;
  }

  function handleDrop(e: DragEvent, index: number) {
    e.preventDefault();
    if (dragIndex !== null && dragIndex !== index) {
      reorderAction(sentantNodeId, autoIndex, transIndex, dragIndex, index);
    }
    dragIndex = null;
    dropIndex = null;
  }

  function handleDragEnd() {
    dragIndex = null;
    dropIndex = null;
  }

  function handleUpdate(updates: Record<string, unknown>) {
    updateTransition(sentantNodeId, autoIndex, transIndex, updates);
  }

  function handleDelete() {
    onClose();
    removeTransition(sentantNodeId, autoIndex, transIndex);
  }

  let hasParams = $derived(
    transition.parameters && Object.keys(transition.parameters).length > 0
  );

  // Derive the decision type from from/to fields
  type DecisionType = "start" | "instruction" | "event";
  let decisionType = $derived<DecisionType>(
    transition.from === "start"
      ? "start"
      : transition.from === undefined && transition.to === undefined
        ? "instruction"
        : "event"
  );

  function handleTypeChange(newType: DecisionType) {
    switch (newType) {
      case "start":
        handleUpdate({ from: "start", to: transition.to || undefined, event: transition.event === "new_decision" ? "init" : transition.event });
        break;
      case "instruction":
        handleUpdate({ from: undefined, to: undefined });
        break;
      case "event":
        handleUpdate({ from: transition.from === "start" ? "" : (transition.from || ""), to: transition.to || "" });
        break;
    }
  }
</script>

<div class="detail-panel">
  <div class="panel-header">
    <span class="panel-title">Decision</span>
    <button class="ui mini icon button basic" onclick={onClose} title="Close" aria-label="Close panel">
      <i class="close icon"></i>
    </button>
  </div>

  <div class="panel-body">
    <div class="field-row">
      <div class="field-group" style="flex: 0 0 auto;">
        <label>Type</label>
        <select class="type-select"
          value={decisionType}
          onchange={(e) => handleTypeChange((e.target as HTMLSelectElement).value as DecisionType)}>
          <option value="start">Start</option>
          <option value="instruction">Instruction</option>
          <option value="event">Event</option>
        </select>
      </div>
      <div class="field-group" style="flex: 1;">
        <label>Event</label>
        <div class="ui mini input fluid">
          <input type="text" value={transition.event}
            oninput={(e) => handleUpdate({ event: (e.target as HTMLInputElement).value })} />
        </div>
      </div>
    </div>

    {#if decisionType === "start"}
      <div class="field-group">
        <label>To state</label>
        <div class="ui mini input fluid">
          <input type="text" placeholder="initial state" value={transition.to ?? ""}
            oninput={(e) => handleUpdate({ to: (e.target as HTMLInputElement).value || undefined })} />
        </div>
      </div>
    {:else if decisionType === "event"}
      <div class="field-row">
        <div class="field-group" style="flex: 1;">
          <label>From state</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="(any)" value={transition.from ?? ""}
              oninput={(e) => handleUpdate({ from: (e.target as HTMLInputElement).value || undefined })} />
          </div>
        </div>
        <div class="field-group" style="flex: 1;">
          <label>To state</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="(same)" value={transition.to ?? ""}
              oninput={(e) => handleUpdate({ to: (e.target as HTMLInputElement).value || undefined })} />
          </div>
        </div>
      </div>
    {/if}

    <div class="field-group">
      <label style="display: flex; align-items: center; gap: 6px;">
        <input type="checkbox" checked={transition.public ?? false}
          onchange={(e) => handleUpdate({ public: (e.target as HTMLInputElement).checked || undefined })} />
        Public (external access)
      </label>
    </div>

    <div class="section-divider"></div>

    <!-- Data flow: parameters → tasks → output -->
    <div class="actions-header">
      <span class="section-label">
        <i class="tasks icon" style="color: #c4a84d;"></i>
        Tasks ({transition.actions.length})
      </span>
      <button class="ui mini basic button" onclick={() => addAction(sentantNodeId, autoIndex, transIndex)}>
        <i class="plus icon"></i> Task
      </button>
    </div>

    <div class="task-flow">
      <!-- Event data in: shows parameters as part of the flow -->
      <div class="flow-entry">
        <div class="flow-dot entry"></div>
        <div class="flow-entry-content">
          <span class="flow-label">event data in</span>
          {#if hasParams}
            <div class="flow-params">
              {#each Object.entries(transition.parameters!) as [key, val]}
                <span class="param-tag" title="{key}: {val}">{key}</span>
              {/each}
            </div>
          {/if}
        </div>
      </div>

      <!-- Expandable parameter editor -->
      <div class="flow-connector"></div>
      <div class="flow-action">
        <div class="param-editor-toggle" onclick={() => (showParams = !showParams)}
          role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showParams = !showParams; }}>
          <i class="icon {showParams ? 'angle down' : 'angle right'}" style="font-size: 10px; color: #998a50;"></i>
          <span class="param-toggle-label">Parameters {hasParams ? `(${Object.keys(transition.parameters!).length})` : ""}</span>
          {#if !hasParams}
            <span class="param-hint">click to define</span>
          {/if}
        </div>
        {#if showParams}
          <div class="param-editor-body">
            <DataEditor
              data={(transition.parameters ?? {}) as Record<string, unknown>}
              onChange={(params) => handleUpdate({ parameters: params })}
            />
          </div>
        {/if}
      </div>

      {#each transition.actions as action, i}
        <div class="flow-connector"></div>
        <div class="flow-action"
          class:drag-over={dropIndex === i && dragIndex !== i}
          class:dragging={dragIndex === i}
          draggable="true"
          ondragstart={(e) => handleDragStart(e, i)}
          ondragover={(e) => handleDragOver(e, i)}
          ondragleave={handleDragLeave}
          ondrop={(e) => handleDrop(e, i)}
          ondragend={handleDragEnd}
          role="listitem">
          <ActionEditor
            {action}
            onUpdate={(updates) => updateAction(sentantNodeId, autoIndex, transIndex, i, updates)}
            onRemove={() => removeAction(sentantNodeId, autoIndex, transIndex, i)}
          />
        </div>
      {/each}

      <div class="flow-connector"></div>
      <div class="flow-entry">
        <div class="flow-dot exit"></div>
        <span class="flow-label">data out</span>
      </div>
    </div>

    <div class="section-divider"></div>

    <button class="ui mini button" style="background: #e74c3c; color: #fff;" onclick={handleDelete}>
      <i class="trash icon"></i> Delete Decision
    </button>
  </div>
</div>

<style>
  .detail-panel {
    width: 320px;
    min-width: 320px;
    height: 100%;
    background: #fff;
    border-left: 1px solid #ddd;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 12px;
    border-bottom: 1px solid #eee;
    background: #fdf8e8;
  }
  .panel-title {
    font-weight: 700;
    font-size: 13px;
    color: #5a4a00;
  }
  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: 12px;
  }
  .field-group {
    margin-bottom: 10px;
  }
  .field-group label {
    display: block;
    font-size: 11px;
    font-weight: 600;
    color: #666;
    margin-bottom: 3px;
  }
  .field-row {
    display: flex;
    gap: 8px;
  }
  .type-select {
    font-size: 12px;
    font-weight: 600;
    padding: 5px 8px;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 4px;
    background: #fff;
    color: #333;
    cursor: pointer;
  }
  .toggle-row {
    display: flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    padding: 4px 0;
  }
  .toggle-label {
    font-size: 11px;
    font-weight: 600;
    color: #888;
  }
  .hint {
    font-size: 10px;
    color: #aaa;
    margin-bottom: 4px;
  }
  .section-divider {
    border-top: 1px solid #eee;
    margin: 12px 0;
  }
  .actions-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 6px;
  }
  .section-label {
    font-size: 12px;
    font-weight: 700;
    color: #555;
  }

  /* Data flow visual */
  .task-flow {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    border-left: 3px solid #e8dfc0;
    margin-left: 12px;
    padding-left: 0;
  }
  .flow-entry {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 3px 0;
    margin-left: -7px;
  }
  .flow-dot {
    width: 11px;
    height: 11px;
    border-radius: 50%;
    flex-shrink: 0;
    border: 2px solid #fff;
  }
  .flow-dot.entry {
    background: #c4a84d;
    box-shadow: 0 0 0 2px #c4a84d;
  }
  .flow-dot.exit {
    background: #888;
    box-shadow: 0 0 0 2px #888;
  }
  .flow-label {
    font-size: 10px;
    color: #998a50;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .flow-connector {
    width: 3px;
    height: 8px;
    background: #e8dfc0;
    margin-left: -3px;
  }
  .flow-action {
    margin-left: 8px;
    cursor: grab;
    transition: opacity 0.15s, border-color 0.15s;
  }
  .flow-action:active {
    cursor: grabbing;
  }
  .flow-action.dragging {
    opacity: 0.4;
  }
  .flow-action.drag-over {
    border-top: 2px solid #4183c4;
    margin-top: -2px;
  }
  .flow-entry-content {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .flow-params {
    display: flex;
    flex-wrap: wrap;
    gap: 3px;
  }
  .param-tag {
    font-size: 9px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 3px;
    background: #fdf3d0;
    color: #8a7530;
    border: 1px solid #e8dfc0;
    white-space: nowrap;
  }
  .param-editor-toggle {
    display: flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    padding: 4px 8px;
    border-radius: 4px;
    background: #fdf8e8;
    border: 1px dashed #e8dfc0;
  }
  .param-editor-toggle:hover {
    background: #faf0d0;
  }
  .param-toggle-label {
    font-size: 10px;
    font-weight: 600;
    color: #998a50;
  }
  .param-hint {
    font-size: 9px;
    color: #c4b880;
    font-style: italic;
  }
  .param-editor-body {
    margin-top: 4px;
    padding: 6px 8px;
    background: #fdf8e8;
    border: 1px solid #e8dfc0;
    border-radius: 4px;
  }
</style>
