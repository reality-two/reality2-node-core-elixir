<script lang="ts">
  let { data } = $props();
  const swarm = $derived(data.swarm);
</script>

<div class="swarm-group">
  <div class="swarm-label">
    <i class="cubes icon" style="margin-right: 4px;"></i>
    {swarm.name}
  </div>
</div>

<style>
  .swarm-group {
    width: 100%;
    height: 100%;
    border: 2px dashed #7b68ee;
    border-radius: 10px;
    background: rgba(123, 104, 238, 0.04);
    pointer-events: none;
  }
  .swarm-label {
    position: absolute;
    top: -12px;
    left: 12px;
    background: #7b68ee;
    color: #fff;
    font-size: 11px;
    font-weight: 700;
    padding: 2px 10px;
    border-radius: 4px;
    pointer-events: auto;
    cursor: pointer;
    white-space: nowrap;
  }
</style>
