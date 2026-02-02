<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";
  let { data } = $props();
</script>

<div class="fsm-state">
  <Handle id="signal-out" type="source" position={Position.Top} style="width: 6px; height: 6px; background: #81c784; border: 1px solid #4caf50; min-width: 6px; min-height: 6px;" />
  <Handle id="in" type="target" position={Position.Left} />
  <span class="state-name">{data.state.name}</span>
  <Handle id="out" type="source" position={Position.Right} />
</div>

<style>
  .fsm-state {
    background: #fffdf5;
    border: 2px solid #e6a817;
    border-radius: 20px;
    padding: 8px 20px;
    font-size: 13px;
    font-weight: 600;
    color: #5a4a00;
    min-width: 70px;
    text-align: center;
    cursor: default;
    box-shadow: 0 1px 4px rgba(200, 160, 0, 0.15);
  }
</style>
