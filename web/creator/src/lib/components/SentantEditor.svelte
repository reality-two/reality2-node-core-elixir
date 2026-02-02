<script lang="ts">
  import type { SentantModel } from "../models/canvas";
  import AutomationFSMView from "./AutomationFSMView.svelte";
  import DataEditor from "./DataEditor.svelte";
  import PluginEditor from "./PluginEditor.svelte";
  import {
    updateSentant,
    addPlugin,
    removePlugin,
    updatePlugin,
  } from "../stores/canvas-store.svelte";

  let { sentant }: { sentant: SentantModel } = $props();

  let showData = $state(true);
  let showPlugins = $state(true);
</script>

{#if sentant}
<div class="editor">
  <div class="editor-layout">
    <!-- Left sidebar: identity, data, plugins -->
    <div class="editor-sidebar">
      <div class="sidebar-scroll">
        <div class="ui segment">
          <h4 class="ui header"><i class="bug icon"></i> Bee Identity</h4>
          <div class="field-group">
            <label>Name</label>
            <div class="ui input fluid">
              <input type="text" value={sentant.name}
                oninput={(e) => updateSentant(sentant._nodeId, { name: (e.target as HTMLInputElement).value })} />
            </div>
          </div>
          <div class="field-group">
            <label>Description</label>
            <textarea rows="3" class="fluid-textarea"
              value={sentant.description}
              oninput={(e) => updateSentant(sentant._nodeId, { description: (e.target as HTMLTextAreaElement).value })}
            ></textarea>
          </div>
        </div>

        <div class="ui segment">
          <div class="section-toggle" onclick={() => (showData = !showData)}
            role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showData = !showData; }}>
            <i class="icon {showData ? 'angle down' : 'angle right'}"></i>
            <h4 class="ui header" style="margin: 0;">Data ({Object.keys(sentant.data).length})</h4>
          </div>
          {#if showData}
            <DataEditor
              data={sentant.data}
              onChange={(data) => updateSentant(sentant._nodeId, { data })}
            />
          {/if}
        </div>

        <div class="ui segment">
          <div class="section-toggle" onclick={() => (showPlugins = !showPlugins)}
            role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showPlugins = !showPlugins; }}>
            <i class="icon {showPlugins ? 'angle down' : 'angle right'}"></i>
            <h4 class="ui header" style="margin: 0;"><i class="wifi icon"></i> Antennae ({sentant.plugins.length})</h4>
          </div>
          {#if showPlugins}
            {#each sentant.plugins as plugin, i}
              <PluginEditor
                {plugin}
                onUpdate={(updates) => updatePlugin(sentant._nodeId, i, updates)}
                onRemove={() => removePlugin(sentant._nodeId, i)}
              />
            {/each}
            <button class="ui mini basic button" onclick={() => addPlugin(sentant._nodeId)}>
              <i class="wifi icon"></i> Add Antenna
            </button>
          {/if}
        </div>
      </div>
    </div>

    <!-- Right area: FSM view -->
    <div class="editor-main">
      <AutomationFSMView {sentant} />
    </div>
  </div>
</div>
{/if}

<style>
  .editor {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: #f5f5f5;
  }
  .editor-layout {
    flex: 1;
    display: flex;
    overflow: hidden;
  }
  .editor-sidebar {
    width: 320px;
    min-width: 320px;
    border-right: 1px solid #ddd;
    background: #f5f5f5;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
  .sidebar-scroll {
    flex: 1;
    overflow-y: auto;
    padding: 12px;
  }
  .editor-main {
    flex: 1;
    min-width: 0;
    display: flex;
    overflow: hidden;
  }
  .field-group {
    margin-bottom: 12px;
  }
  .field-group label {
    display: block;
    font-size: 12px;
    font-weight: 600;
    color: #555;
    margin-bottom: 4px;
  }
  .fluid-textarea {
    width: 100%;
    font-size: 13px;
    padding: 8px;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 4px;
    resize: vertical;
    font-family: inherit;
  }
  .section-toggle {
    display: flex;
    align-items: center;
    gap: 6px;
    cursor: pointer;
    margin-bottom: 8px;
  }
</style>
