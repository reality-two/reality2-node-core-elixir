<script lang="ts">
  import type { SentantModel } from "../models/canvas";
  import AutomationEditor from "./AutomationEditor.svelte";
  import DataEditor from "./DataEditor.svelte";
  import PluginEditor from "./PluginEditor.svelte";
  import {
    updateSentant,
    addAutomation,
    removeAutomation,
    updateAutomation,
    addTransition,
    removeTransition,
    updateTransition,
    addAction,
    removeAction,
    updateAction,
    addPlugin,
    removePlugin,
    updatePlugin,
    removeSentant,
  } from "../stores/canvas-store.svelte";

  let { sentant }: { sentant: SentantModel | null } = $props();

  let showData = $state(false);
  let showPlugins = $state(false);
  let showAutomations = $state(true);
</script>

{#if sentant}
  <div class="property-panel">
    <div class="panel-header">
      <strong>Properties</strong>
      <button class="ui mini icon button" title="Remove sentant"
        onclick={() => removeSentant(sentant._nodeId)}>
        <i class="trash icon"></i>
      </button>
    </div>

    <div class="panel-content">
      <div class="field-group">
        <label>Name</label>
        <div class="ui mini input fluid">
          <input type="text" value={sentant.name}
            oninput={(e) => updateSentant(sentant._nodeId, { name: (e.target as HTMLInputElement).value })} />
        </div>
      </div>

      <div class="field-group">
        <label>Description</label>
        <div class="ui mini input fluid">
          <textarea rows="2" style="width: 100%; font-size: 12px; padding: 6px;"
            value={sentant.description}
            oninput={(e) => updateSentant(sentant._nodeId, { description: (e.target as HTMLTextAreaElement).value })}
          ></textarea>
        </div>
      </div>

      <!-- Data section -->
      <div class="section-header" onclick={() => (showData = !showData)}
        role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showData = !showData; }}>
        <i class="icon {showData ? 'angle down' : 'angle right'}"></i>
        <span>Data ({Object.keys(sentant.data).length})</span>
      </div>
      {#if showData}
        <DataEditor
          data={sentant.data}
          onChange={(data) => updateSentant(sentant._nodeId, { data })}
        />
      {/if}

      <!-- Plugins section -->
      <div class="section-header" onclick={() => (showPlugins = !showPlugins)}
        role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showPlugins = !showPlugins; }}>
        <i class="icon {showPlugins ? 'angle down' : 'angle right'}"></i>
        <span>Plugins ({sentant.plugins.length})</span>
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
          <i class="plus icon"></i> Add Plugin
        </button>
      {/if}

      <!-- Automations section -->
      <div class="section-header" onclick={() => (showAutomations = !showAutomations)}
        role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showAutomations = !showAutomations; }}>
        <i class="icon {showAutomations ? 'angle down' : 'angle right'}"></i>
        <span>Automations ({sentant.automations.length})</span>
      </div>
      {#if showAutomations}
        {#each sentant.automations as automation, i}
          <AutomationEditor
            {automation}
            onUpdateName={(name) => updateAutomation(sentant._nodeId, i, { name })}
            onRemove={() => removeAutomation(sentant._nodeId, i)}
            onAddTransition={() => addTransition(sentant._nodeId, i)}
            onRemoveTransition={(ti) => removeTransition(sentant._nodeId, i, ti)}
            onUpdateTransition={(ti, updates) => updateTransition(sentant._nodeId, i, ti, updates)}
            onAddAction={(ti) => addAction(sentant._nodeId, i, ti)}
            onRemoveAction={(ti, ai) => removeAction(sentant._nodeId, i, ti, ai)}
            onUpdateAction={(ti, ai, updates) => updateAction(sentant._nodeId, i, ti, ai, updates)}
          />
        {/each}
        <button class="ui mini basic button" onclick={() => addAutomation(sentant._nodeId)}>
          <i class="plus icon"></i> Add Automation
        </button>
      {/if}
    </div>
  </div>
{:else}
  <div class="property-panel empty">
    <p style="color: #999; text-align: center; padding: 20px; font-size: 13px;">
      Select a sentant to edit its properties.<br/>
      Double-click the canvas to add one.
    </p>
  </div>
{/if}

<style>
  .property-panel {
    width: 350px;
    border-left: 2px solid #ddd;
    background: #fafafa;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .property-panel.empty {
    justify-content: center;
  }
  .panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 12px;
    background: #eee;
    border-bottom: 1px solid #ddd;
    flex-shrink: 0;
  }
  .panel-content {
    flex: 1;
    overflow-y: auto;
    padding: 10px 12px;
  }
  .field-group {
    margin-bottom: 10px;
  }
  .field-group label {
    display: block;
    font-size: 11px;
    font-weight: 600;
    color: #555;
    margin-bottom: 3px;
  }
  .section-header {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 6px 0;
    cursor: pointer;
    font-size: 12px;
    font-weight: 600;
    color: #333;
    border-top: 1px solid #eee;
    margin-top: 8px;
  }
  textarea {
    resize: vertical;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 4px;
  }
</style>
