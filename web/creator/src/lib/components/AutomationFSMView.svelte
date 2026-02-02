<script lang="ts">
  import type { SentantModel } from "../models/canvas";
  import FSMCanvas from "./FSMCanvas.svelte";
  import TransitionDetailPanel from "./TransitionDetailPanel.svelte";
  import {
    addAutomation,
    removeAutomation,
    updateAutomation,
    addTransition,
    updateTransition,
  } from "../stores/canvas-store.svelte";

  let { sentant }: { sentant: SentantModel } = $props();

  let activeAutoIndex = $state(0);
  let selectedTransitionIndex = $state<number | null>(null);

  let automations = $derived(sentant?.automations ?? []);
  let sentantPlugins = $derived(sentant?.plugins ?? []);
  let sentantNodeId = $derived(sentant?._nodeId ?? "");
  let activeAutomation = $derived(automations[activeAutoIndex] ?? null);
  let selectedTransition = $derived(
    selectedTransitionIndex !== null && activeAutomation
      ? activeAutomation.transitions[selectedTransitionIndex] ?? null
      : null
  );

  // Clamp activeAutoIndex if automations change
  $effect(() => {
    if (activeAutoIndex >= automations.length) {
      activeAutoIndex = Math.max(0, automations.length - 1);
    }
  });

  function handleSwitchTab(index: number) {
    activeAutoIndex = index;
    selectedTransitionIndex = null;
  }

  function handleAddAutomation() {
    if (!sentant) return;
    addAutomation(sentantNodeId);
    activeAutoIndex = automations.length - 1;
    selectedTransitionIndex = null;
  }

  function handleRemoveAutomation() {
    if (!sentant || !activeAutomation) return;
    if (!confirm(`Delete behaviour "${activeAutomation.name}" and all its decisions?`)) return;
    removeAutomation(sentantNodeId, activeAutoIndex);
    selectedTransitionIndex = null;
  }

  function handleAddTransitionBetween(from: string | undefined, to: string | undefined) {
    if (!sentant || !activeAutomation) return;
    addTransition(sentantNodeId, activeAutoIndex);
    const newIndex = activeAutomation.transitions.length - 1;
    const updates: Record<string, unknown> = {};
    if (from) updates.from = from;
    if (to) updates.to = to;
    if (Object.keys(updates).length > 0) {
      updateTransition(sentantNodeId, activeAutoIndex, newIndex, updates);
    }
    selectedTransitionIndex = newIndex;
  }

  function handleAddTransitionButton() {
    if (!sentant || !activeAutomation) return;
    addTransition(sentantNodeId, activeAutoIndex);
    selectedTransitionIndex = activeAutomation.transitions.length - 1;
  }
</script>

<div class="fsm-view">
  <div class="tab-bar">
    {#each automations as auto, i}
      <button
        class="tab-btn"
        class:active={i === activeAutoIndex}
        onclick={() => handleSwitchTab(i)}
        title={auto.name}
      >
        {auto.name}
      </button>
    {/each}
    <button class="tab-btn add-btn" onclick={handleAddAutomation} title="Add behaviour">+</button>
    {#if sentant && activeAutomation}
      <div class="tab-actions">
        <div class="ui mini input" style="width: 140px;">
          <input type="text" placeholder="Behaviour name" value={activeAutomation.name}
            oninput={(e) => sentant && updateAutomation(sentantNodeId, activeAutoIndex, { name: (e.target as HTMLInputElement).value })} />
        </div>
        <button class="ui mini basic button" onclick={handleAddTransitionButton} title="Add a decision">
          <i class="plus icon"></i> Decision
        </button>
        <button class="ui mini icon button" style="color: #c0392b;" onclick={handleRemoveAutomation} title="Delete behaviour">
          <i class="trash icon"></i>
        </button>
      </div>
    {/if}
  </div>

  <div class="fsm-body">
    {#if sentant && activeAutomation}
      <div class="fsm-canvas-area">
        <FSMCanvas
          automation={activeAutomation}
          plugins={sentantPlugins ?? []}
          sentantNodeId={sentantNodeId}
          autoIndex={activeAutoIndex}
          {selectedTransitionIndex}
          onSelectTransition={(idx) => { selectedTransitionIndex = idx; }}
          onDeselectTransition={() => { selectedTransitionIndex = null; }}
          onAddTransitionBetween={handleAddTransitionBetween}
        />
      </div>
      {#if selectedTransition && selectedTransitionIndex !== null}
        <TransitionDetailPanel
          transition={selectedTransition}
          sentantNodeId={sentantNodeId}
          autoIndex={activeAutoIndex}
          transIndex={selectedTransitionIndex}
          onClose={() => { selectedTransitionIndex = null; }}
        />
      {/if}
    {:else}
      <div class="empty-state">
        <p>No behaviours yet.</p>
        <button class="ui small button" style="background: #e6a817; color: #fff;" onclick={handleAddAutomation}>
          <i class="plus icon"></i> Add a Behaviour
        </button>
      </div>
    {/if}
  </div>
</div>

<style>
  .fsm-view {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
  }
  .tab-bar {
    display: flex;
    align-items: center;
    gap: 0;
    border-bottom: 2px solid #e8e0c8;
    background: #fdf8e8;
    padding: 0 8px;
    flex-shrink: 0;
    flex-wrap: wrap;
  }
  .tab-btn {
    padding: 8px 14px;
    border: none;
    background: none;
    font-size: 12px;
    font-weight: 600;
    color: #998a50;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    margin-bottom: -2px;
    white-space: nowrap;
    max-width: 140px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .tab-btn:hover {
    color: #5a4a00;
  }
  .tab-btn.active {
    color: #5a4a00;
    border-bottom-color: #e6a817;
  }
  .tab-btn.add-btn {
    font-size: 16px;
    font-weight: 700;
    padding: 6px 12px;
    color: #c4a84d;
  }
  .tab-actions {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px 0;
  }
  .fsm-body {
    flex: 1;
    display: flex;
    overflow: hidden;
  }
  .fsm-canvas-area {
    flex: 1;
    min-width: 0;
  }
  .empty-state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    color: #999;
    font-size: 14px;
  }
</style>
