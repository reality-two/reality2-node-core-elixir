<script lang="ts">
  import type { SwarmModel } from "../models/canvas";
  import { updateSwarm, getSentants } from "../stores/canvas-store.svelte";

  let { swarm }: { swarm: SwarmModel } = $props();

  let memberSentants = $derived(
    getSentants().filter((s) => s._swarmId === swarm._nodeId)
  );
</script>

<div class="editor">
  <div class="editor-body">
    <div class="ui segment">
      <h4 class="ui header"><i class="cubes icon"></i> Swarm Identity</h4>
      <div class="field-group">
        <label>Name</label>
        <div class="ui input fluid">
          <input type="text" value={swarm.name}
            oninput={(e) => updateSwarm(swarm._nodeId, { name: (e.target as HTMLInputElement).value })} />
        </div>
      </div>
      <div class="field-group">
        <label>Description</label>
        <textarea rows="3" class="fluid-textarea"
          value={swarm.description}
          oninput={(e) => updateSwarm(swarm._nodeId, { description: (e.target as HTMLTextAreaElement).value })}
        ></textarea>
      </div>
    </div>

    <div class="ui segment">
      <h4 class="ui header"><i class="bug icon"></i> Bees ({memberSentants.length})</h4>
      {#if memberSentants.length === 0}
        <p style="color: #999; font-size: 13px;">No bees in this swarm yet. Drag bees into the swarm group on the canvas.</p>
      {:else}
        <div class="member-list">
          {#each memberSentants as s}
            <div class="member-card">
              <span class="member-name">{s.name}</span>
              <span class="member-detail">{s.automations.length} behaviour{s.automations.length !== 1 ? 's' : ''}</span>
            </div>
          {/each}
        </div>
      {/if}
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
    max-width: 600px;
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
  .member-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .member-card {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: #fff;
    border: 1px solid #ddd;
    border-left: 3px solid #4183c4;
    border-radius: 4px;
    padding: 8px 12px;
  }
  .member-name {
    font-weight: 600;
    font-size: 13px;
  }
  .member-detail {
    font-size: 11px;
    color: #888;
  }
</style>
