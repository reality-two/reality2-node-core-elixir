<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";

  let { data } = $props();
  let isPublic = $derived(data.state.isPublic ?? false);
</script>

<div class="fsm-command" class:public={isPublic}>
  <Handle id="signal-out" type="source" position={Position.Top} style="width: 6px; height: 6px; background: #81c784; border: 1px solid #4caf50; min-width: 6px; min-height: 6px;" />
  <Handle id="in" type="target" position={Position.Left} style="width: 0; height: 0; border: none; opacity: 0;" />
  <span class="command-label">{data.state.name}</span>
  {#if isPublic}
    <span class="pub-badge">PUB</span>
  {/if}
  <Handle id="out" type="source" position={Position.Right} />
</div>

<style>
  .fsm-command {
    background: #fefcf5;
    border: 2px solid #d4a84d;
    border-radius: 20px;
    padding: 6px 16px;
    font-size: 11px;
    font-weight: 600;
    color: #7a6520;
    min-width: 60px;
    text-align: center;
    display: flex;
    align-items: center;
    gap: 5px;
    white-space: nowrap;
    cursor: pointer;
    box-shadow: 0 1px 4px rgba(200, 160, 0, 0.1);
  }
  .fsm-command.public {
    border-color: #43a047;
    color: #2e7d32;
    background: #f5fbf5;
    box-shadow: 0 1px 4px rgba(67, 160, 71, 0.1);
  }
  .command-label {
    max-width: 160px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .pub-badge {
    font-size: 8px;
    font-weight: 700;
    text-transform: uppercase;
    background: #43a047;
    color: #fff;
    padding: 1px 4px;
    border-radius: 3px;
    letter-spacing: 0.3px;
  }
</style>
