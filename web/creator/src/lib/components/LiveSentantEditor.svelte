<script lang="ts">
  import type { LiveSentantModel } from "../models/canvas";
  import { getSignalMessages } from "../stores/canvas-store.svelte";

  let {
    sentant,
    onSendEvent,
  }: {
    sentant: LiveSentantModel;
    onSendEvent: (sentantId: string, event: string, params: Record<string, unknown>) => Promise<boolean>;
  } = $props();

  let paramValues = $state<Record<string, Record<string, string>>>({});
  let messages = $derived(getSignalMessages(sentant._nodeId));
  let expandedMessage = $state<number | null>(null);
  let sentStatus = $state<Record<string, string>>({});

  function getParams(eventName: string): Record<string, string> {
    return paramValues[eventName] ?? {};
  }

  function setParam(eventName: string, key: string, value: string) {
    const current = { ...(paramValues[eventName] ?? {}) };
    current[key] = value;
    paramValues = { ...paramValues, [eventName]: current };
  }

  async function handleSend(eventName: string, paramDefs?: Record<string, string>) {
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
    const ok = await onSendEvent(sentant.id, eventName, params);
    sentStatus = { ...sentStatus, [eventName]: ok ? "sent" : "error" };
    setTimeout(() => {
      sentStatus = { ...sentStatus, [eventName]: "" };
    }, 1500);
  }
</script>

<div class="editor">
  <div class="editor-body">
    {#if sentant.description}
      <p class="description">{sentant.description}</p>
    {/if}

    <div class="editor-columns">
      <!-- Left column: events -->
      <div class="editor-col">
        <div class="ui segment">
          <h4 class="ui header">
            <i class="bolt icon" style="color: #2e7d32;"></i>
            Events ({sentant.events.length})
          </h4>
          {#if sentant.events.length === 0}
            <p class="empty-note">No public events</p>
          {:else}
            {#each sentant.events as evt}
              <div class="event-card">
                {#if evt.parameters && Object.keys(evt.parameters).length > 0}
                  <div class="param-grid">
                    {#each Object.entries(evt.parameters) as [key, type]}
                      <div class="param-row">
                        <label class="param-label">{key} <span class="param-type">({type})</span></label>
                        <div class="ui mini input fluid">
                          <input
                            type="text"
                            placeholder={key}
                            value={getParams(evt.event)[key] ?? ""}
                            oninput={(e) => setParam(evt.event, key, (e.target as HTMLInputElement).value)}
                          />
                        </div>
                      </div>
                    {/each}
                  </div>
                {/if}
                <button
                  class="ui small button fluid"
                  class:green={!sentStatus[evt.event]}
                  class:teal={sentStatus[evt.event] === "sent"}
                  class:red={sentStatus[evt.event] === "error"}
                  onclick={() => handleSend(evt.event, evt.parameters)}
                >
                  {#if sentStatus[evt.event] === "sent"}
                    <i class="check icon"></i> Sent
                  {:else if sentStatus[evt.event] === "error"}
                    <i class="times icon"></i> Error
                  {:else}
                    <i class="play icon"></i> {evt.event}
                  {/if}
                </button>
              </div>
            {/each}
          {/if}
        </div>
      </div>

      <!-- Right column: signals feed -->
      <div class="editor-col">
        <div class="ui segment">
          <h4 class="ui header">
            <i class="rss icon" style="color: #e65100;"></i>
            Signals ({sentant.signals.length})
          </h4>
          {#if sentant.signals.length > 0}
            <div class="signal-names">
              {#each sentant.signals as sig}
                <span class="signal-tag">{sig}</span>
              {/each}
            </div>
          {/if}

          <div class="feed-container">
            {#if messages.length === 0}
              <div class="feed-empty">Waiting for signals...</div>
            {:else}
              {#each messages as msg, i}
                <div
                  class="feed-row"
                  class:feed-latest={i === messages.length - 1}
                  onclick={() => expandedMessage = expandedMessage === i ? null : i}
                  role="button"
                  tabindex="0"
                  onkeydown={(e) => { if (e.key === 'Enter') expandedMessage = expandedMessage === i ? null : i; }}
                >
                  <span class="feed-time">{msg.time}</span>
                  <span class="feed-event">{msg.event}</span>
                  {#if expandedMessage !== i}
                    <span class="feed-preview">{msg.data}</span>
                  {/if}
                </div>
                {#if expandedMessage === i}
                  <pre class="feed-detail">{(() => { try { return JSON.stringify(JSON.parse(msg.data), null, 2); } catch { return msg.data; } })()}</pre>
                {/if}
              {/each}
            {/if}
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  .editor {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: #f5f5f5;
  }
  .editor-body {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
  }
  .description {
    font-size: 13px;
    color: #666;
    margin: 0 0 12px 0;
  }
  .editor-columns {
    display: flex;
    gap: 16px;
    max-width: 1200px;
  }
  .editor-col {
    flex: 1;
    min-width: 0;
  }
  .event-card {
    background: #f9fff9;
    border: 1px solid #c8e6c9;
    border-radius: 6px;
    padding: 10px;
    margin-bottom: 10px;
  }
  .param-grid {
    margin-bottom: 8px;
  }
  .param-row {
    margin-bottom: 6px;
  }
  .param-label {
    display: block;
    font-size: 11px;
    font-weight: 600;
    color: #555;
    margin-bottom: 2px;
  }
  .param-type {
    color: #999;
    font-weight: 400;
  }
  .signal-names {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-bottom: 10px;
  }
  .signal-tag {
    background: #fff3e0;
    color: #e65100;
    border: 1px solid #ffcc80;
    font-size: 11px;
    font-weight: 600;
    padding: 2px 8px;
    border-radius: 3px;
  }
  .feed-container {
    background: #1e1e2e;
    border-radius: 6px;
    padding: 8px;
    min-height: 120px;
    flex: 1;
    overflow-y: auto;
  }
  .feed-empty {
    color: #666;
    font-size: 12px;
    font-style: italic;
    padding: 20px;
    text-align: center;
  }
  .feed-row {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 8px;
    padding: 4px 6px;
    border-radius: 3px;
    cursor: pointer;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    border-bottom: 1px solid #2a2a3e;
  }
  .feed-row:hover {
    background: #2a2a3e;
  }
  .feed-latest {
    background: #1a3a2a;
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
  .feed-preview {
    color: #888;
    word-break: break-all;
    flex-basis: 100%;
  }
  .feed-detail {
    background: #252540;
    color: #cdd6f4;
    padding: 8px;
    margin: 2px 0 4px 0;
    border-radius: 3px;
    font-size: 11px;
    white-space: pre-wrap;
    word-break: break-word;
  }
  .empty-note {
    color: #999;
    font-size: 12px;
    font-style: italic;
  }
</style>
