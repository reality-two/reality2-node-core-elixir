<script lang="ts">
  import type { LiveSentantModel } from "../models/canvas";
  import { getSignalMessages } from "../stores/canvas-store.svelte";

  let {
    sentant,
    onSendEvent,
  }: {
    sentant: LiveSentantModel;
    onSendEvent: (sentantId: string, event: string, params: Record<string, unknown>) => void;
  } = $props();

  let paramValues = $state<Record<string, Record<string, string>>>({});
  let messages = $derived(getSignalMessages(sentant._nodeId));

  function getParams(eventName: string): Record<string, string> {
    return paramValues[eventName] ?? {};
  }

  function setParam(eventName: string, key: string, value: string) {
    const current = { ...(paramValues[eventName] ?? {}) };
    current[key] = value;
    paramValues = { ...paramValues, [eventName]: current };
  }

  function handleSend(eventName: string, paramDefs?: Record<string, string>) {
    const raw = getParams(eventName);
    const params: Record<string, unknown> = {};
    if (paramDefs) {
      for (const [key, type] of Object.entries(paramDefs)) {
        const val = raw[key] ?? "";
        if (type === "number" || type === "Number") {
          params[key] = parseFloat(val) || 0;
        } else if (type === "boolean" || type === "Boolean") {
          params[key] = val === "true" || val === "1";
        } else {
          if (val) params[key] = val;
        }
      }
    }
    onSendEvent(sentant.id, eventName, params);
  }
</script>

<div class="live-panel">
  <div class="panel-header">
    <span class="live-badge">LIVE</span>
    <strong>{sentant.name}</strong>
  </div>

  <div class="panel-content">
    {#if sentant.description}
      <p class="description">{sentant.description}</p>
    {/if}

    {#if sentant.events.length > 0}
      <div class="section-label">Send Events</div>
      {#each sentant.events as evt}
        <div class="event-group">
          {#if evt.parameters && Object.keys(evt.parameters).length > 0}
            <div class="param-fields">
              {#each Object.entries(evt.parameters) as [key, type]}
                <div class="ui mini input" style="margin-bottom: 3px;">
                  <input
                    type="text"
                    placeholder="{key} ({type})"
                    value={getParams(evt.event)[key] ?? ""}
                    oninput={(e) => setParam(evt.event, key, (e.target as HTMLInputElement).value)}
                    style="width: 100%;"
                  />
                </div>
              {/each}
            </div>
          {/if}
          <button
            class="ui mini green button fluid"
            onclick={() => handleSend(evt.event, evt.parameters)}
          >
            {evt.event}
          </button>
        </div>
      {/each}
    {:else}
      <p class="empty-note">No public events</p>
    {/if}

    {#if sentant.signals.length > 0}
      <div class="section-label" style="margin-top: 12px;">Signal Feed</div>
      <div class="signal-list">
        {#each sentant.signals as sig}
          <span class="signal-name">{sig}</span>
        {/each}
      </div>
      <div class="feed-container">
        {#if messages.length === 0}
          <p class="empty-note">Waiting for signals...</p>
        {:else}
          {#each messages as msg}
            <div class="feed-item" title={msg.data}>
              <span class="feed-time">{msg.time}</span>
              <span class="feed-event">{msg.event}</span>
              <span class="feed-data">{msg.data}</span>
            </div>
          {/each}
        {/if}
      </div>
    {:else}
      <p class="empty-note" style="margin-top: 8px;">No signals</p>
    {/if}
  </div>
</div>

<style>
  .live-panel {
    width: 350px;
    border-left: 2px solid #ddd;
    background: #f5f5f5;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .panel-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    background: #e8e8e8;
    border-bottom: 1px solid #ddd;
    flex-shrink: 0;
  }
  .live-badge {
    background: #43a047;
    color: #fff;
    font-size: 9px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: 3px;
    letter-spacing: 0.5px;
  }
  .panel-content {
    flex: 1;
    overflow-y: auto;
    padding: 10px 12px;
  }
  .description {
    font-size: 12px;
    color: #666;
    margin: 0 0 8px 0;
  }
  .section-label {
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    color: #888;
    letter-spacing: 0.5px;
    margin-bottom: 6px;
    border-top: 1px solid #ddd;
    padding-top: 8px;
  }
  .event-group {
    margin-bottom: 8px;
  }
  .param-fields {
    margin-bottom: 4px;
  }
  .signal-list {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-bottom: 6px;
  }
  .signal-name {
    background: #fff3e0;
    color: #e65100;
    border: 1px solid #ffcc80;
    font-size: 10px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 3px;
  }
  .feed-container {
    background: #1e1e2e;
    border-radius: 4px;
    padding: 6px 8px;
    max-height: 200px;
    overflow-y: auto;
  }
  .feed-item {
    display: flex;
    gap: 6px;
    font-size: 11px;
    padding: 2px 0;
    font-family: "SF Mono", "Fira Code", monospace;
    border-bottom: 1px solid #2a2a3e;
  }
  .feed-time {
    color: #666;
    flex-shrink: 0;
  }
  .feed-event {
    color: #f0c040;
    font-weight: 600;
    flex-shrink: 0;
  }
  .feed-data {
    color: #cdd6f4;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .empty-note {
    font-size: 11px;
    color: #aaa;
    margin: 4px 0;
    font-style: italic;
  }
</style>
