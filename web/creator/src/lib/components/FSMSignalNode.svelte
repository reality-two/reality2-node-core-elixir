<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";

  let { data } = $props();
  let isPublic = $derived(data.state.isPublic ?? false);
</script>

<div class="fsm-signal" class:public={isPublic}>
  <Handle id="in" type="target" position={Position.Bottom} />
  <i class="broadcast tower icon" style="font-size: 10px; margin: 0;"></i>
  <span class="signal-label">{data.state.name}</span>
  {#if isPublic}
    <span class="pub-badge">pub</span>
  {/if}
</div>

<style>
  .fsm-signal {
    background: #f5faf5;
    border: 2px solid #81c784;
    border-radius: 20px;
    padding: 5px 14px;
    font-size: 10px;
    font-weight: 600;
    color: #4a7a4d;
    min-width: 50px;
    text-align: center;
    display: flex;
    align-items: center;
    gap: 4px;
    white-space: nowrap;
    cursor: default;
    box-shadow: 0 1px 3px rgba(76, 175, 80, 0.1);
  }
  .fsm-signal.public {
    border-color: #43a047;
    color: #2e7d32;
    background: #eef7ee;
  }
  .signal-label {
    max-width: 140px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .pub-badge {
    font-size: 7px;
    font-weight: 700;
    text-transform: uppercase;
    background: #43a047;
    color: #fff;
    padding: 1px 3px;
    border-radius: 2px;
    letter-spacing: 0.3px;
  }
</style>
