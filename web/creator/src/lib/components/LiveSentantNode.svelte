<script lang="ts">
  import { getSignalMessages } from "../stores/canvas-store.svelte";

  let { data } = $props();
  const sentant = $derived(data.sentant);
  const messages = $derived(getSignalMessages(sentant._nodeId));
</script>

<div class="live-node">
  <div class="node-header">
    <span class="live-badge">LIVE</span>
    <span class="node-name">{sentant.name}</span>
  </div>
  {#if sentant.description}
    <div class="node-description">{sentant.description}</div>
  {/if}

  {#if sentant.events.length > 0}
    <div class="section-label">Events</div>
    <div class="tag-list">
      {#each sentant.events as evt}
        <span class="tag event-tag" title={evt.parameters ? Object.keys(evt.parameters).join(", ") : "no params"}>
          {evt.event}
        </span>
      {/each}
    </div>
  {/if}

  {#if sentant.signals.length > 0}
    <div class="section-label">Signals</div>
    <div class="tag-list">
      {#each sentant.signals as sig}
        <span class="tag signal-tag">{sig}</span>
      {/each}
    </div>
  {/if}

  {#if messages.length > 0}
    <div class="signal-feed">
      {#each messages as msg}
        <div class="feed-item" title={msg.data}>
          <span class="feed-time">{msg.time}</span>
          <span class="feed-event">{msg.event}</span>
        </div>
      {/each}
    </div>
  {/if}
</div>


<style>
  .live-node {
    background: #f8f8f8;
    border: 2px solid #999;
    border-left: 5px solid #999;
    border-radius: 8px;
    padding: 10px 14px;
    min-width: 180px;
    max-width: 280px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
  }
  .node-header {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .live-badge {
    background: #43a047;
    color: #fff;
    font-size: 9px;
    font-weight: 700;
    padding: 1px 5px;
    border-radius: 3px;
    letter-spacing: 0.5px;
    flex-shrink: 0;
  }
  .node-name {
    font-weight: 600;
    font-size: 13px;
    color: #333;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .node-description {
    font-size: 11px;
    color: #777;
    margin-top: 4px;
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
  }
  .section-label {
    font-size: 9px;
    font-weight: 700;
    text-transform: uppercase;
    color: #999;
    margin-top: 6px;
    letter-spacing: 0.5px;
  }
  .tag-list {
    display: flex;
    flex-wrap: wrap;
    gap: 3px;
    margin-top: 3px;
  }
  .tag {
    font-size: 10px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 3px;
    white-space: nowrap;
  }
  .event-tag {
    background: #e8f5e9;
    color: #2e7d32;
    border: 1px solid #a5d6a7;
  }
  .signal-tag {
    background: #fff3e0;
    color: #e65100;
    border: 1px solid #ffcc80;
  }
  .signal-feed {
    margin-top: 6px;
    max-height: 80px;
    overflow-y: auto;
    border-top: 1px solid #ddd;
    padding-top: 4px;
  }
  .feed-item {
    display: flex;
    gap: 6px;
    font-size: 10px;
    padding: 1px 0;
    color: #555;
  }
  .feed-time {
    color: #aaa;
    flex-shrink: 0;
  }
  .feed-event {
    color: #e65100;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
