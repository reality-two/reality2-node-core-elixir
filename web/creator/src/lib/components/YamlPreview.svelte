<script lang="ts">
  import { getYaml, getJson, loadFromContentSafe } from "../stores/canvas-store.svelte";

  let {
    yamlGetter,
    jsonGetter,
    onApply,
  }: {
    yamlGetter?: () => string;
    jsonGetter?: () => string;
    onApply?: (content: string, format: "yaml" | "json") => { ok: boolean; error?: string };
  } = $props();

  let showJson = $state(false);
  let collapsed = $state(false);
  let editMode = $state(false);
  let editBuffer = $state("");
  let parseError = $state("");
  let panelHeight = $state(200);

  const effectiveYaml = $derived(yamlGetter ? yamlGetter() : getYaml());
  const effectiveJson = $derived(jsonGetter ? jsonGetter() : getJson());
  let output = $derived(showJson ? effectiveJson : effectiveYaml);
  let format = $derived<"yaml" | "json">(showJson ? "json" : "yaml");

  function enterEditMode() {
    editBuffer = output || "";
    parseError = "";
    editMode = true;
  }

  function exitEditMode() {
    editMode = false;
    editBuffer = "";
    parseError = "";
  }

  function handleApply() {
    parseError = "";
    const result = onApply
      ? onApply(editBuffer, format)
      : loadFromContentSafe(editBuffer, format);
    if (result.ok) {
      editBuffer = showJson ? effectiveJson : effectiveYaml;
    } else {
      parseError = result.error || "Unknown error";
    }
  }

  function handleFormatToggle() {
    showJson = !showJson;
    if (editMode) {
      editBuffer = showJson ? effectiveJson : effectiveYaml;
      parseError = "";
    }
  }

  // --- Drag resize ---
  let dragging = $state(false);
  let dragStartY = 0;
  let dragStartHeight = 0;

  function onDragStart(e: MouseEvent) {
    dragging = true;
    dragStartY = e.clientY;
    dragStartHeight = panelHeight;
    e.preventDefault();
    window.addEventListener("mousemove", onDragMove);
    window.addEventListener("mouseup", onDragEnd);
  }

  function onDragMove(e: MouseEvent) {
    if (!dragging) return;
    const delta = dragStartY - e.clientY;
    const maxH = window.innerHeight * 0.8;
    panelHeight = Math.max(100, Math.min(maxH, dragStartHeight + delta));
  }

  function onDragEnd() {
    dragging = false;
    window.removeEventListener("mousemove", onDragMove);
    window.removeEventListener("mouseup", onDragEnd);
  }
</script>

{#if !collapsed}
  <div class="yaml-preview" style="height: {panelHeight}px;">
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="drag-handle" class:active={dragging} onmousedown={onDragStart}></div>
    <div class="preview-header">
      <div class="header-left">
        <strong style="font-size: 12px;">Definition</strong>
        <div class="mode-toggle">
          <button class="mode-btn" class:active={!editMode} onclick={exitEditMode}>Preview</button>
          <button class="mode-btn" class:active={editMode} onclick={enterEditMode}>Edit</button>
        </div>
        <label class="format-toggle">
          <input type="checkbox" checked={showJson} onchange={handleFormatToggle} /> JSON
        </label>
      </div>
      <button class="ui mini icon button basic" onclick={() => (collapsed = true)}>
        <i class="angle down icon"></i>
      </button>
    </div>

    {#if editMode}
      <textarea class="edit-content" bind:value={editBuffer} spellcheck="false"></textarea>
      {#if parseError}
        <div class="error-bar"><i class="exclamation triangle icon"></i> {parseError}</div>
      {/if}
      <div class="action-bar">
        <button class="ui mini button primary" onclick={handleApply}>Apply</button>
      </div>
    {:else}
      <pre class="preview-content">{output || "# Add a sentant to get started"}</pre>
    {/if}
  </div>
{:else}
  <div class="yaml-collapsed">
    <button class="ui mini button basic" onclick={() => (collapsed = false)}>
      <i class="angle up icon"></i> Show Preview
    </button>
  </div>
{/if}

<style>
  .yaml-preview {
    border-top: 2px solid #ddd;
    background: #1e1e2e;
    color: #cdd6f4;
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
  }
  .drag-handle {
    height: 6px;
    background: #313244;
    cursor: ns-resize;
    flex-shrink: 0;
    transition: background 0.15s, height 0.15s;
  }
  .drag-handle:hover {
    background: #4183c4;
    height: 4px;
  }
  .drag-handle.active {
    background: #4183c4;
    height: 4px;
  }
  .preview-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 4px 12px;
    background: #313244;
    color: #cdd6f4;
    flex-shrink: 0;
  }
  .header-left {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .mode-toggle {
    display: flex;
    border: 1px solid #585b70;
    border-radius: 4px;
    overflow: hidden;
  }
  .mode-btn {
    background: transparent;
    color: #a6adc8;
    border: none;
    padding: 2px 10px;
    font-size: 11px;
    cursor: pointer;
    font-weight: 600;
  }
  .mode-btn:hover {
    background: #45475a;
  }
  .mode-btn.active {
    background: #585b70;
    color: #cdd6f4;
  }
  .format-toggle {
    display: flex;
    align-items: center;
    gap: 3px;
    font-size: 11px;
    cursor: pointer;
    color: #a6adc8;
  }
  .preview-content {
    flex: 1;
    overflow: auto;
    margin: 0;
    padding: 8px 12px;
    font-size: 12px;
    line-height: 1.5;
    font-family: "SF Mono", "Fira Code", "Cascadia Code", monospace;
    white-space: pre-wrap;
    word-break: break-word;
  }
  .edit-content {
    flex: 1;
    overflow: auto;
    margin: 0;
    padding: 8px 12px;
    font-size: 12px;
    line-height: 1.5;
    font-family: "SF Mono", "Fira Code", "Cascadia Code", monospace;
    white-space: pre;
    background: #181825;
    color: #cdd6f4;
    border: none;
    outline: none;
    resize: none;
    tab-size: 2;
  }
  .edit-content:focus {
    background: #11111b;
  }
  .error-bar {
    padding: 4px 12px;
    background: #45171a;
    color: #f38ba8;
    font-size: 11px;
    flex-shrink: 0;
  }
  .action-bar {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    background: #313244;
    flex-shrink: 0;
  }
  .yaml-collapsed {
    border-top: 2px solid #ddd;
    padding: 4px 12px;
    background: #f5f5f5;
  }
</style>
