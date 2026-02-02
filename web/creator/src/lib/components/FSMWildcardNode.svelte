<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";
</script>

<div class="fsm-wildcard">
  <Handle id="signal-out" type="source" position={Position.Top} style="width: 6px; height: 6px; background: #81c784; border: 1px solid #4caf50; min-width: 6px; min-height: 6px;" />
  <Handle id="in" type="target" position={Position.Left} />
  <span class="wildcard-label">Any State</span>
  <Handle id="out" type="source" position={Position.Right} />
</div>

<style>
  .fsm-wildcard {
    background: #faf8f0;
    border: 2px dashed #c4a84d;
    border-radius: 20px;
    padding: 8px 20px;
    font-size: 12px;
    font-weight: 600;
    color: #998a50;
    min-width: 70px;
    text-align: center;
    cursor: default;
  }
</style>
