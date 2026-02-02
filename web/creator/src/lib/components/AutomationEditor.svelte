<script lang="ts">
  import type { AutomationModel } from "../models/canvas";
  import TransitionEditor from "./TransitionEditor.svelte";

  let {
    automation,
    onUpdateName,
    onRemove,
    onAddTransition,
    onRemoveTransition,
    onUpdateTransition,
    onAddAction,
    onRemoveAction,
    onUpdateAction,
  }: {
    automation: AutomationModel;
    onUpdateName: (name: string) => void;
    onRemove: () => void;
    onAddTransition: () => void;
    onRemoveTransition: (transIndex: number) => void;
    onUpdateTransition: (transIndex: number, updates: Record<string, unknown>) => void;
    onAddAction: (transIndex: number) => void;
    onRemoveAction: (transIndex: number, actionIndex: number) => void;
    onUpdateAction: (transIndex: number, actionIndex: number, updates: Record<string, unknown>) => void;
  } = $props();

  let expanded = $state(true);
</script>

<div class="ui segment" style="padding: 10px 12px; margin: 6px 0;">
  <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 6px;">
    <button class="ui mini icon button basic" onclick={() => (expanded = !expanded)}>
      <i class="icon {expanded ? 'angle down' : 'angle right'}"></i>
    </button>
    <div class="ui mini input" style="flex: 1;">
      <input type="text" value={automation.name}
        oninput={(e) => onUpdateName((e.target as HTMLInputElement).value)} />
    </div>
    <button class="ui mini icon button" onclick={onRemove}><i class="close icon"></i></button>
  </div>

  {#if expanded}
    <div style="font-size: 11px; font-weight: 600; color: #555; margin: 4px 0;">
      Transitions ({automation.transitions.length})
    </div>
    {#each automation.transitions as transition, i}
      <TransitionEditor
        {transition}
        onUpdate={(updates) => onUpdateTransition(i, updates)}
        onRemove={() => onRemoveTransition(i)}
        onAddAction={() => onAddAction(i)}
        onRemoveAction={(actionIndex) => onRemoveAction(i, actionIndex)}
        onUpdateAction={(actionIndex, updates) => onUpdateAction(i, actionIndex, updates)}
      />
    {/each}
    <button class="ui mini basic button" style="margin-top: 4px;" onclick={onAddTransition}>
      <i class="plus icon"></i> Add Transition
    </button>
  {/if}
</div>
