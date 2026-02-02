<script lang="ts">
  let { data } = $props();
  const group = $derived(data.group);
</script>

<div class="hive-group" class:local={group.isLocal}>
  <div class="hive-label" class:local={group.isLocal}>
    <i class="server icon" style="margin-right: 4px;"></i>
    {group.nodeName}
    {#if group.isLocal}
      <span style="font-weight: 400; opacity: 0.8;"> (local)</span>
    {/if}
  </div>
</div>

<style>
  .hive-group {
    width: 100%;
    height: 100%;
    border: 2px dashed #999;
    border-radius: 10px;
    background: rgba(150, 150, 150, 0.04);
    pointer-events: none;
  }
  .hive-group.local {
    border-color: #43a047;
    background: rgba(67, 160, 71, 0.04);
  }
  .hive-label {
    position: absolute;
    top: -12px;
    left: 12px;
    background: #888;
    color: #fff;
    font-size: 11px;
    font-weight: 700;
    padding: 2px 10px;
    border-radius: 4px;
    pointer-events: auto;
    cursor: pointer;
    white-space: nowrap;
  }
  .hive-label.local {
    background: #43a047;
  }
</style>
