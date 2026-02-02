<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";

  let { data } = $props();
</script>

<div class="fsm-antenna">
  <Handle id="signal-out" type="source" position={Position.Top} style="width: 6px; height: 6px; background: #81c784; border: 1px solid #4caf50; min-width: 6px; min-height: 6px;" />
  <Handle id="in" type="target" position={Position.Left} />
  <i class="wifi icon" style="font-size: 11px; margin: 0;"></i>
  <span class="antenna-label">{data.state.name}</span>
  <Handle id="out" type="source" position={Position.Right} />
</div>

<style>
  .fsm-antenna {
    background: #f0f7ff;
    border: 2px solid #5b9bd5;
    border-radius: 20px;
    padding: 6px 16px;
    font-size: 11px;
    font-weight: 600;
    color: #2c5f8a;
    min-width: 60px;
    text-align: center;
    display: flex;
    align-items: center;
    gap: 5px;
    white-space: nowrap;
    cursor: default;
    box-shadow: 0 1px 4px rgba(91, 155, 213, 0.15);
  }
  .antenna-label {
    max-width: 140px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
