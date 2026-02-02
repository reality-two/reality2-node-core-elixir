<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";
</script>

<div class="fsm-start">
  <div class="start-circle"></div>
  <span class="start-label">start</span>
  <Handle id="out" type="source" position={Position.Right} />
</div>

<style>
  .fsm-start {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
  }
  .start-circle {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: #e6a817;
    border: 3px solid #c48d00;
  }
  .start-label {
    font-size: 10px;
    font-weight: 600;
    color: #a08000;
  }
</style>
