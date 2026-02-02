<script lang="ts">
  let { data } = $props();
  let group = $derived(data.group);
</script>

<div class="live-swarm-group">
  <div class="swarm-label">
    <i class="cubes icon" style="margin-right: 4px;"></i>
    {group.swarmName}
  </div>
</div>

<style>
  .live-swarm-group {
    width: 100%;
    height: 100%;
    border: 2px dashed #7b68ee;
    border-radius: 8px;
    background: rgba(123, 104, 238, 0.04);
    pointer-events: none;
  }
  .swarm-label {
    position: absolute;
    top: -10px;
    left: 12px;
    background: #7b68ee;
    color: #fff;
    font-size: 10px;
    font-weight: 700;
    padding: 1px 8px;
    border-radius: 3px;
    pointer-events: auto;
    white-space: nowrap;
  }
</style>
