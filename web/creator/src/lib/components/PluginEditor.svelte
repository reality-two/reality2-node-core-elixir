<script lang="ts">
  import type { PluginModel } from "../models/canvas";

  let {
    plugin,
    onUpdate,
    onRemove,
  }: {
    plugin: PluginModel;
    onUpdate: (updates: Record<string, unknown>) => void;
    onRemove: () => void;
  } = $props();

  let showHeaders = $state(false);
  let showParams = $state(false);
  let showBody = $state(false);
  let showOutput = $state(false);

  const hasBody = $derived(plugin.method === "POST" || plugin.method === "PUT" || plugin.method === "DELETE");

  // Body as editable text
  const bodyText = $derived(
    plugin.body === undefined || plugin.body === null
      ? ""
      : typeof plugin.body === "string"
        ? plugin.body
        : JSON.stringify(plugin.body, null, 2)
  );

  function handleBodyChange(text: string) {
    if (!text.trim()) {
      onUpdate({ body: undefined });
      return;
    }
    try {
      onUpdate({ body: JSON.parse(text) });
    } catch {
      // Not valid JSON — store as string (e.g. form-encoded)
      onUpdate({ body: text });
    }
  }

  function headerEntries(): [string, string][] {
    return Object.entries(plugin.headers || {});
  }

  function paramEntries(): [string, string][] {
    return Object.entries(plugin.parameters || {});
  }

  function updateHeader(oldKey: string, newKey: string, value: string) {
    const h = { ...(plugin.headers || {}) };
    if (oldKey !== newKey) delete h[oldKey];
    h[newKey] = value;
    onUpdate({ headers: h });
  }

  function removeHeader(key: string) {
    const h = { ...(plugin.headers || {}) };
    delete h[key];
    onUpdate({ headers: h });
  }

  function addHeader() {
    const h = { ...(plugin.headers || {}), "": "" };
    onUpdate({ headers: h });
  }

  function updateParam(oldKey: string, newKey: string, value: string) {
    const p = { ...(plugin.parameters || {}) };
    if (oldKey !== newKey) delete p[oldKey];
    p[newKey] = value;
    onUpdate({ parameters: p });
  }

  function removeParam(key: string) {
    const p = { ...(plugin.parameters || {}) };
    delete p[key];
    onUpdate({ parameters: Object.keys(p).length > 0 ? p : undefined });
  }

  function addParam() {
    const p = { ...(plugin.parameters || {}), "": "" };
    onUpdate({ parameters: p });
  }

  function updateOutput(field: string, value: string) {
    const out = { key: "", event: "", ...(plugin.output || {}), [field]: value };
    if (!out.key && !out.event && !out.value) {
      onUpdate({ output: undefined });
    } else {
      onUpdate({ output: out });
    }
  }
</script>

<div class="plugin-card">
  <div class="plugin-header">
    <strong class="plugin-name">{plugin.name || "Antenna"}</strong>
    <button class="ui mini icon button" onclick={onRemove}><i class="close icon"></i></button>
  </div>

  <!-- Name -->
  <div class="field-row">
    <label>Name</label>
    <div class="ui mini input fluid">
      <input type="text" placeholder="com.example.api" value={plugin.name}
        oninput={(e) => onUpdate({ name: (e.target as HTMLInputElement).value })} />
    </div>
  </div>

  <!-- Description -->
  <div class="field-row">
    <label>Description</label>
    <div class="ui mini input fluid">
      <input type="text" placeholder="What this antenna does" value={plugin.description || ""}
        oninput={(e) => onUpdate({ description: (e.target as HTMLInputElement).value || undefined })} />
    </div>
  </div>

  <!-- URL -->
  <div class="field-row">
    <label>URL</label>
    <div class="ui mini input fluid">
      <input type="text" placeholder="https://api.example.com/endpoint" value={plugin.url}
        oninput={(e) => onUpdate({ url: (e.target as HTMLInputElement).value })} />
    </div>
  </div>

  <!-- Method -->
  <div class="field-row">
    <label>Method</label>
    <select class="ui mini fluid dropdown" value={plugin.method}
      onchange={(e) => onUpdate({ method: (e.target as HTMLSelectElement).value })}>
      <option value="GET">GET</option>
      <option value="POST">POST</option>
      <option value="PUT">PUT</option>
      <option value="DELETE">DELETE</option>
    </select>
  </div>

  <!-- Headers (collapsible) -->
  <div class="section-toggle" onclick={() => (showHeaders = !showHeaders)}
    role="button" tabindex="0" onkeydown={(e) => { if (e.key === "Enter") showHeaders = !showHeaders; }}>
    <i class="icon {showHeaders ? 'angle down' : 'angle right'}"></i>
    <span>Headers ({headerEntries().length})</span>
  </div>
  {#if showHeaders}
    <div class="kv-section">
      {#each headerEntries() as [key, val], i}
        <div class="kv-row">
          <input class="kv-key" type="text" placeholder="Header name" value={key}
            onblur={(e) => updateHeader(key, (e.target as HTMLInputElement).value, val)} />
          <input class="kv-val" type="text" placeholder="Value" value={val}
            oninput={(e) => updateHeader(key, key, (e.target as HTMLInputElement).value)} />
          <button class="ui mini icon button kv-remove" onclick={() => removeHeader(key)}>
            <i class="minus icon"></i>
          </button>
        </div>
      {/each}
      <button class="ui mini basic button" onclick={addHeader}>
        <i class="plus icon"></i> Header
      </button>
    </div>
  {/if}

  <!-- Parameters / Query String (collapsible) -->
  <div class="section-toggle" onclick={() => (showParams = !showParams)}
    role="button" tabindex="0" onkeydown={(e) => { if (e.key === "Enter") showParams = !showParams; }}>
    <i class="icon {showParams ? 'angle down' : 'angle right'}"></i>
    <span>Query Parameters ({paramEntries().length})</span>
  </div>
  {#if showParams}
    <div class="kv-section">
      {#each paramEntries() as [key, val], i}
        <div class="kv-row">
          <input class="kv-key" type="text" placeholder="Param name" value={key}
            onblur={(e) => updateParam(key, (e.target as HTMLInputElement).value, val)} />
          <input class="kv-val" type="text" placeholder="Value" value={val}
            oninput={(e) => updateParam(key, key, (e.target as HTMLInputElement).value)} />
          <button class="ui mini icon button kv-remove" onclick={() => removeParam(key)}>
            <i class="minus icon"></i>
          </button>
        </div>
      {/each}
      <button class="ui mini basic button" onclick={addParam}>
        <i class="plus icon"></i> Parameter
      </button>
    </div>
  {/if}

  <!-- Body (collapsible, only for POST/PUT/DELETE) -->
  {#if hasBody}
    <div class="section-toggle" onclick={() => (showBody = !showBody)}
      role="button" tabindex="0" onkeydown={(e) => { if (e.key === "Enter") showBody = !showBody; }}>
      <i class="icon {showBody ? 'angle down' : 'angle right'}"></i>
      <span>Body {plugin.body ? "●" : ""}</span>
    </div>
    {#if showBody}
      <div class="body-section">
        <textarea class="body-editor" rows="6" placeholder={"JSON object or key=__var__&key2=val"}
          value={bodyText}
          onblur={(e) => handleBodyChange((e.target as HTMLTextAreaElement).value)}
        ></textarea>
        <div class="hint">JSON object or URL-encoded string. Use __name__ for variables.</div>
      </div>
    {/if}
  {/if}

  <!-- Output (collapsible) -->
  <div class="section-toggle" onclick={() => (showOutput = !showOutput)}
    role="button" tabindex="0" onkeydown={(e) => { if (e.key === "Enter") showOutput = !showOutput; }}>
    <i class="icon {showOutput ? 'angle down' : 'angle right'}"></i>
    <span>Output {plugin.output?.event ? "●" : ""}</span>
  </div>
  {#if showOutput}
    <div class="output-section">
      <div class="field-row">
        <label>Event</label>
        <div class="ui mini input fluid">
          <input type="text" placeholder="response_event" value={plugin.output?.event || ""}
            oninput={(e) => updateOutput("event", (e.target as HTMLInputElement).value)} />
        </div>
      </div>
      <div class="field-row">
        <label>Key</label>
        <div class="ui mini input fluid">
          <input type="text" placeholder="result" value={plugin.output?.key || ""}
            oninput={(e) => updateOutput("key", (e.target as HTMLInputElement).value)} />
        </div>
      </div>
      <div class="field-row">
        <label>JSONPath</label>
        <div class="ui mini input fluid">
          <input type="text" placeholder="choices.0.message.content" value={plugin.output?.value || ""}
            oninput={(e) => updateOutput("value", (e.target as HTMLInputElement).value)} />
        </div>
      </div>
      <div class="hint">Extract a value from the response using dot notation. Leave empty for full response.</div>
    </div>
  {/if}
</div>

<style>
  .plugin-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 8px 10px;
    margin: 4px 0;
  }
  .plugin-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 6px;
  }
  .plugin-name {
    font-size: 12px;
    color: #333;
  }
  .field-row {
    margin-bottom: 5px;
  }
  .field-row label {
    display: block;
    font-size: 11px;
    font-weight: 600;
    color: #666;
    margin-bottom: 2px;
  }
  select {
    width: 100%;
    padding: 6px 8px;
    font-size: 12px;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 4px;
    background: #fff;
  }
  .section-toggle {
    display: flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    font-size: 11px;
    font-weight: 600;
    color: #555;
    padding: 4px 0;
    user-select: none;
  }
  .kv-section {
    padding: 0 0 4px 16px;
  }
  .kv-row {
    display: flex;
    gap: 4px;
    margin-bottom: 3px;
    align-items: center;
  }
  .kv-key, .kv-val {
    flex: 1;
    padding: 4px 6px;
    font-size: 11px;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 3px;
  }
  .kv-key {
    max-width: 40%;
  }
  .kv-remove {
    padding: 4px !important;
    min-width: 24px;
  }
  .body-section {
    padding: 0 0 4px 16px;
  }
  .body-editor {
    width: 100%;
    font-family: "Cascadia Code", "Fira Code", monospace;
    font-size: 11px;
    padding: 6px;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 3px;
    resize: vertical;
    tab-size: 2;
  }
  .output-section {
    padding: 0 0 4px 16px;
  }
  .output-section .field-row label {
    font-size: 10px;
  }
  .hint {
    font-size: 10px;
    color: #888;
    margin-top: 2px;
    padding-left: 2px;
  }
</style>
