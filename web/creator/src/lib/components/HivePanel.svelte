<script lang="ts">
  let {
    nodeInfo,
    peers,
    directory,
    onRefresh,
  }: {
    nodeInfo: any;
    peers: any[];
    directory: any;
    onRefresh?: () => void;
  } = $props();

  const STALE_HOURS = 1;

  function timeAgo(isoStr: string | null | undefined): string {
    if (!isoStr) return "unknown";
    const then = new Date(isoStr).getTime();
    if (isNaN(then)) return isoStr;
    const diffMs = Date.now() - then;
    if (diffMs < 0) return "just now";
    const secs = Math.floor(diffMs / 1000);
    if (secs < 60) return `${secs}s ago`;
    const mins = Math.floor(secs / 60);
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  }

  function isStale(isoStr: string | null | undefined): boolean {
    if (!isoStr) return true;
    const then = new Date(isoStr).getTime();
    if (isNaN(then)) return true;
    return (Date.now() - then) > STALE_HOURS * 60 * 60 * 1000;
  }
</script>

<div class="hive-panel">
  <div class="panel-body">
    <!-- This Node -->
    <div class="ui segment">
      <h4 class="ui header">
        <i class="server icon"></i>
        This Node
      </h4>
      {#if nodeInfo}
        <table class="ui very basic compact small table">
          <tbody>
            <tr><td class="label-cell">Node Name</td><td><strong>{nodeInfo.nodeName}</strong></td></tr>
            <tr><td class="label-cell">Node ID</td><td class="mono">{nodeInfo.nodeId}</td></tr>
            {#if nodeInfo.hiveName}
              <tr><td class="label-cell">Hive</td><td><strong>{nodeInfo.hiveName}</strong></td></tr>
              <tr><td class="label-cell">Hive ID</td><td class="mono">{nodeInfo.hiveId}</td></tr>
              <tr><td class="label-cell">Role</td><td>
                <span class="ui mini label" class:blue={nodeInfo.hiveMode === 'key_holder'} class:grey={nodeInfo.hiveMode !== 'key_holder'}>
                  {nodeInfo.hiveMode === 'key_holder' ? 'Key Holder' : 'Member'}
                </span>
              </td></tr>
              {#if nodeInfo.hiveCompressedId}
                <tr><td class="label-cell">Compressed ID</td><td class="mono">{nodeInfo.hiveCompressedId}</td></tr>
              {/if}
            {:else}
              <tr><td class="label-cell">Hive</td><td style="color: #999;">Not configured</td></tr>
            {/if}
          </tbody>
        </table>
      {:else}
        <p style="color: #999;">Loading...</p>
      {/if}
    </div>

    <!-- Discovered Peers -->
    <div class="ui segment">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
        <h4 class="ui header" style="margin: 0;">
          <i class="wifi icon"></i>
          Nearby Peers
          {#if peers.length > 0}
            <span class="ui mini circular label" style="margin-left: 6px;">{peers.length}</span>
          {/if}
        </h4>
        <button class="ui mini basic icon button" onclick={onRefresh} title="Refresh">
          <i class="sync icon"></i>
        </button>
      </div>

      {#if peers.length === 0}
        <p style="color: #999; font-size: 13px;">No peers discovered yet.</p>
      {:else}
        <div class="peer-list">
          {#each peers as peer}
            <div class="peer-card" class:same-hive={peer.isSameHive}>
              <div class="peer-header">
                <span class="peer-name">{peer.nodeName || 'Unknown'}</span>
                <div class="peer-badges">
                  {#if peer.isSameHive}
                    <span class="ui mini label" style="background: #43a047; color: #fff;">Same Hive</span>
                  {/if}
                  {#if peer.hiveVerified}
                    <span class="ui mini label" style="background: #1976d2; color: #fff;">Verified</span>
                  {/if}
                  <span class="ui mini label">{peer.transport || '?'}</span>
                </div>
              </div>
              <div class="peer-details">
                <span class="peer-detail" title="Node ID">{peer.nodeId?.slice(0, 8)}...</span>
                {#if peer.rssi != null}
                  <span class="peer-detail" title="Signal strength">{peer.rssi} dBm</span>
                {/if}
                {#if peer.sentantCount > 0}
                  <span class="peer-detail">{peer.sentantCount} sentant{peer.sentantCount !== 1 ? 's' : ''}</span>
                {/if}
                <span class="peer-detail">{peer.connectionState}</span>
              </div>
              {#if peer.reachability}
                <div class="transport-row">
                  {#if peer.reachability.ble?.confidence > 0}
                    <span class="transport-badge ble" title="BLE: confidence {peer.reachability.ble.confidence}">
                      BLE {peer.reachability.ble.rssi != null ? `${peer.reachability.ble.rssi}dBm` : ''}
                    </span>
                  {/if}
                  {#if peer.reachability.wifi?.confidence > 0}
                    <span class="transport-badge wifi" title="WiFi: {peer.reachability.wifi.ip || ''}">
                      WiFi {peer.reachability.wifi.ip || ''}
                    </span>
                  {/if}
                  {#if peer.reachability.lora?.confidence > 0}
                    <span class="transport-badge lora" title="LoRa: confidence {peer.reachability.lora.confidence}">
                      LoRa
                    </span>
                  {/if}
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <!-- Hive Directory -->
    {#if directory}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="sitemap icon"></i>
          Hive Directory
          {#if directory.hiveName}
            <span style="font-weight: 400; font-size: 13px; color: #666;"> — {directory.hiveName}</span>
          {/if}
        </h4>
        {#if directory.nodes && directory.nodes.length > 0}
          <div class="peer-list">
            {#each directory.nodes as node}
              {@const stale = node.nodeId !== directory.myNodeId && isStale(node.updatedAt)}
              <div class="peer-card" class:is-me={node.nodeId === directory.myNodeId} class:stale-node={stale}>
                <div class="peer-header">
                  <span class="peer-name">
                    {node.name || 'Unknown'}
                    {#if node.nodeId === directory.myNodeId}
                      <span style="font-weight: 400; opacity: 0.7;"> (this node)</span>
                    {/if}
                  </span>
                  <div class="peer-badges">
                    {#if stale}
                      <span class="ui mini label" style="background: #ff9800; color: #fff;">stale</span>
                    {:else}
                      <span class="ui mini label" class:green={node.status === 'active'} class:red={node.status === 'revoked'} class:grey={node.status === 'absent'}>
                        {node.status}
                      </span>
                    {/if}
                  </div>
                </div>
                <div class="peer-details">
                  <span class="peer-detail" title="Node ID">{node.nodeId?.slice(0, 8)}...</span>
                  {#if node.sentants && node.sentants.length > 0}
                    <span class="peer-detail">{node.sentants.length} sentant{node.sentants.length !== 1 ? 's' : ''}</span>
                  {/if}
                  {#if node.updatedAt}
                    <span class="peer-detail" title={node.updatedAt}>updated {timeAgo(node.updatedAt)}</span>
                  {/if}
                </div>
              </div>
            {/each}
          </div>
        {:else}
          <p style="color: #999; font-size: 13px;">No nodes in directory yet.</p>
        {/if}
        <div style="margin-top: 6px; font-size: 11px; color: #aaa;">
          Directory version: {directory.directoryVersion ?? 0}
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  .hive-panel {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: #f5f5f5;
  }
  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
    max-width: 800px;
  }
  .label-cell {
    color: #888;
    font-size: 12px;
    font-weight: 600;
    width: 120px;
    white-space: nowrap;
  }
  .mono {
    font-family: monospace;
    font-size: 12px;
    color: #555;
    word-break: break-all;
  }
  .peer-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .peer-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 10px 12px;
    border-left: 4px solid #999;
  }
  .peer-card.same-hive {
    border-left-color: #43a047;
  }
  .peer-card.is-me {
    border-left-color: #1976d2;
    background: #f0f7ff;
  }
  .peer-card.stale-node {
    opacity: 0.5;
    border-left-color: #ccc;
  }
  .peer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .peer-name {
    font-weight: 600;
    font-size: 13px;
  }
  .peer-badges {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }
  .peer-details {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 4px;
  }
  .peer-detail {
    font-size: 11px;
    color: #777;
  }
  .transport-row {
    display: flex;
    gap: 4px;
    margin-top: 6px;
  }
  .transport-badge {
    font-size: 10px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 3px;
    white-space: nowrap;
  }
  .transport-badge.ble {
    background: #e3f2fd;
    color: #1565c0;
    border: 1px solid #90caf9;
  }
  .transport-badge.wifi {
    background: #e8f5e9;
    color: #2e7d32;
    border: 1px solid #a5d6a7;
  }
  .transport-badge.lora {
    background: #fff3e0;
    color: #e65100;
    border: 1px solid #ffcc80;
  }
</style>
