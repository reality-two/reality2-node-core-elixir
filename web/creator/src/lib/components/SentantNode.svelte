<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";
  import { getPublicEvents, getSignalEvents } from "../stores/canvas-store.svelte";

  let { data } = $props();
  const sentant = $derived(data.sentant);
  const autoCount = $derived(sentant.automations?.length ?? 0);
  const publicEvents = $derived(getPublicEvents(sentant._nodeId));
  const signalEvents = $derived(getSignalEvents(sentant._nodeId));
</script>

<div class="sentant-node">
  <Handle type="target" position={Position.Left} style="width: 8px; height: 8px; background: #4183c4; border: 2px solid #fff; opacity: 0.6;" />
  <Handle type="source" position={Position.Right} style="width: 8px; height: 8px; background: #4183c4; border: 2px solid #fff; opacity: 0.6;" />
  <div class="node-header">
    <span class="node-name"><i class="bug icon" style="color: #c48d00; font-size: 11px;"></i> {sentant.name}</span>
    {#if autoCount > 0}
      <span class="badge">{autoCount}</span>
    {/if}
  </div>
  {#if sentant.description}
    <div class="node-description">{sentant.description}</div>
  {/if}
  {#if publicEvents.length > 0}
    <div class="event-list">
      {#each publicEvents as evt}
        <span class="event-tag public-event" title="Public event: {evt}">{evt}</span>
      {/each}
    </div>
  {/if}
  {#if signalEvents.length > 0}
    <div class="event-list">
      {#each signalEvents as sig}
        <span class="event-tag signal-event" title="Signal: {sig}">{sig}</span>
      {/each}
    </div>
  {/if}
</div>


<style>
  .sentant-node {
    background: #fffdf5;
    border: 2px solid #e6a817;
    border-left: 5px solid #e6a817;
    border-radius: 6px;
    padding: 10px 14px;
    min-width: 160px;
    max-width: 260px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    box-shadow: 0 2px 6px rgba(200, 160, 0, 0.12);
  }
  .node-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .node-name {
    font-weight: 600;
    font-size: 13px;
    color: #1a1a2e;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .badge {
    background: #e6a817;
    color: #fff;
    font-size: 11px;
    font-weight: 600;
    padding: 1px 7px;
    border-radius: 10px;
    flex-shrink: 0;
  }
  .node-description {
    font-size: 11px;
    color: #666;
    margin-top: 4px;
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
  }
  .event-list {
    display: flex;
    flex-wrap: wrap;
    gap: 3px;
    margin-top: 6px;
  }
  .event-tag {
    font-size: 10px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 3px;
    white-space: nowrap;
  }
  .public-event {
    background: #e8f5e9;
    color: #2e7d32;
    border: 1px solid #a5d6a7;
  }
  .signal-event {
    background: #fff3e0;
    color: #e65100;
    border: 1px solid #ffcc80;
  }
</style>
