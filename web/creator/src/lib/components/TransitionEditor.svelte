<script lang="ts">
  import type { TransitionModel } from "../models/canvas";
  import ActionEditor from "./ActionEditor.svelte";

  let {
    transition,
    onUpdate,
    onRemove,
    onAddAction,
    onRemoveAction,
    onUpdateAction,
  }: {
    transition: TransitionModel;
    onUpdate: (updates: Record<string, unknown>) => void;
    onRemove: () => void;
    onAddAction: () => void;
    onRemoveAction: (actionIndex: number) => void;
    onUpdateAction: (actionIndex: number, updates: Record<string, unknown>) => void;
  } = $props();

  let expanded = $state(false);
</script>

<div class="ui segment" style="padding: 8px 12px; margin: 4px 0;">
  <div style="display: flex; align-items: center; gap: 6px; cursor: pointer;"
    onclick={() => (expanded = !expanded)} role="button" tabindex="0"
    onkeydown={(e) => { if (e.key === 'Enter') expanded = !expanded; }}>
    <i class="icon {expanded ? 'angle down' : 'angle right'}"></i>
    <span style="font-weight: 600; font-size: 12px;">{transition.event}</span>
    {#if transition.from || transition.to}
      <span style="font-size: 11px; color: #888;">
        {transition.from ?? "*"} &rarr; {transition.to ?? "*"}
      </span>
    {/if}
    {#if transition.public}
      <span class="ui mini label" style="font-size: 10px;">public</span>
    {/if}
    <span style="font-size: 11px; color: #aaa; margin-left: auto;">{transition.actions.length} action{transition.actions.length !== 1 ? 's' : ''}</span>
    <button class="ui mini icon button" onclick={(e) => { e.stopPropagation(); onRemove(); }}><i class="close icon"></i></button>
  </div>

  {#if expanded}
    <div style="margin-top: 8px;">
      <div style="display: flex; gap: 4px; margin-bottom: 6px; flex-wrap: wrap;">
        <div class="ui mini input">
          <input type="text" placeholder="Event" value={transition.event} style="width: 120px;"
            oninput={(e) => onUpdate({ event: (e.target as HTMLInputElement).value })} />
        </div>
        <div class="ui mini input">
          <input type="text" placeholder="From" value={transition.from ?? ""} style="width: 80px;"
            oninput={(e) => onUpdate({ from: (e.target as HTMLInputElement).value || undefined })} />
        </div>
        <div class="ui mini input">
          <input type="text" placeholder="To" value={transition.to ?? ""} style="width: 80px;"
            oninput={(e) => onUpdate({ to: (e.target as HTMLInputElement).value || undefined })} />
        </div>
        <label style="display: flex; align-items: center; gap: 3px; font-size: 12px;">
          <input type="checkbox" checked={transition.public ?? false}
            onchange={(e) => onUpdate({ public: (e.target as HTMLInputElement).checked || undefined })} />
          Public
        </label>
      </div>

      <div style="font-size: 11px; font-weight: 600; color: #555; margin-bottom: 4px;">Actions</div>
      {#each transition.actions as action, i}
        <ActionEditor
          {action}
          onUpdate={(updates) => onUpdateAction(i, updates)}
          onRemove={() => onRemoveAction(i)}
        />
      {/each}
      <button class="ui mini basic button" style="margin-top: 4px;" onclick={onAddAction}>
        <i class="plus icon"></i> Add Action
      </button>
    </div>
  {/if}
</div>
