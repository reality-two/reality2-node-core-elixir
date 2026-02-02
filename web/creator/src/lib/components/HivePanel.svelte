<script lang="ts">
  declare const __APP_VERSION__: string;
  declare const __BUILD_TIME__: string;

  import R2 from "../reality2";
  import { DEFAULT_PORT } from "../constants";

  let {
    nodeInfo,
    peers,
    directory,
    r2,
    onRefresh,
    onStatus,
  }: {
    nodeInfo: any;
    peers: any[];
    directory: any;
    r2: R2;
    onRefresh?: () => void;
    onStatus?: (msg: string) => void;
  } = $props();

  const STALE_HOURS = 1;

  // --- Hive creation ---
  let newHiveName = $state("");
  let creating = $state(false);

  // --- Key management ---
  let exportPassphrase = $state("");
  let importPassphrase = $state("");
  let importData = $state("");
  let showKeySection = $state(false);

  // --- Approval-based joining (joiner side) ---
  let joiningPeerId = $state<string | null>(null);       // peer nodeId we're requesting to join
  let joinRequestId = $state<string | null>(null);        // request ID returned by key holder
  let joinTargetR2 = $state<R2 | null>(null);             // R2 client for key holder node
  let joinPollingTimer: ReturnType<typeof setInterval> | null = null;

  // --- Approval-based joining (key holder side) ---
  let pendingRequests = $state<any[]>([]);
  let requestsPollingTimer: ReturnType<typeof setInterval> | null = null;
  let approvingId = $state<string | null>(null);

  function status(msg: string) {
    onStatus?.(msg);
  }

  async function handleCreateHive() {
    const name = newHiveName.trim();
    if (!name) return;
    creating = true;
    try {
      const result: any = await r2.hiveCreate(name);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        newHiveName = "";
        status("Hive created: " + name);
        onRefresh?.();
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    } finally {
      creating = false;
    }
  }

  async function handleMarkEstablished() {
    try {
      const result: any = await r2.hiveMarkEstablished();
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        status("Hive marked as established");
        onRefresh?.();
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    }
  }

  async function handleExportKey() {
    const pass = exportPassphrase.trim();
    if (!pass) return;
    try {
      const result: any = await r2.hiveExportKey(pass);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
        return;
      }
      const data = result?.data?.hiveExportKey;
      if (data?.encryptedData) {
        const blob = new Blob([data.encryptedData], { type: "text/plain" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `hive-key-${nodeInfo?.hiveName || "export"}.enc`;
        a.click();
        URL.revokeObjectURL(url);
        exportPassphrase = "";
        status("Key exported");
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    }
  }

  async function handleImportKey() {
    const pass = importPassphrase.trim();
    const data = importData.trim();
    if (!pass || !data) return;
    try {
      const result: any = await r2.hiveImportKey(data, pass);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        importPassphrase = "";
        importData = "";
        status("Key imported successfully");
        onRefresh?.();
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    }
  }

  function handleImportFile(e: Event) {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      importData = (reader.result as string).trim();
    };
    reader.readAsText(file);
  }

  // --- Joiner: Request to join a peer's hive ---

  async function handleRequestToJoin(peer: any) {
    const ip = getPeerIp(peer);
    if (!ip) {
      status("Cannot reach peer — no IP address");
      return;
    }
    joiningPeerId = peer.nodeId;
    try {
      // 1. Get our public key
      const keyResult: any = await r2.hiveGetPublicKey();
      if (keyResult?.errors) {
        status("Error getting public key: " + keyResult.errors[0]?.message);
        joiningPeerId = null;
        return;
      }
      const publicKey = keyResult?.data?.hiveGetPublicKey;
      if (!publicKey) {
        status("Error: no public key returned");
        joiningPeerId = null;
        return;
      }

      // 2. Connect to key holder and submit join request
      const port = parseInt(DEFAULT_PORT);
      let remoteR2: R2;
      let submitResult: any;
      try {
        remoteR2 = new R2(ip, port, true);
        submitResult = await remoteR2.hiveSubmitJoinRequest(nodeInfo?.nodeName || "unknown", publicKey);
      } catch {
        remoteR2 = new R2(ip, port, false);
        submitResult = await remoteR2.hiveSubmitJoinRequest(nodeInfo?.nodeName || "unknown", publicKey);
      }

      if (submitResult?.errors) {
        status("Error: " + submitResult.errors[0]?.message);
        joiningPeerId = null;
        return;
      }

      const reqData = submitResult?.data?.hiveSubmitJoinRequest;
      if (!reqData?.id) {
        status("Error: no request ID returned");
        joiningPeerId = null;
        return;
      }

      // 3. Start polling for approval
      joinRequestId = reqData.id;
      joinTargetR2 = remoteR2;
      startJoinPolling();
    } catch (err) {
      status("Join request error: " + (err as Error).message);
      joiningPeerId = null;
    }
  }

  function startJoinPolling() {
    if (joinPollingTimer) clearInterval(joinPollingTimer);
    joinPollingTimer = setInterval(pollJoinStatus, 3000);
  }

  async function pollJoinStatus() {
    if (!joinRequestId || !joinTargetR2) return;
    try {
      const result: any = await joinTargetR2.hiveJoinRequestStatus(joinRequestId);
      if (result?.errors) return; // keep polling

      const data = result?.data?.hiveJoinRequestStatus;
      if (!data) return;

      if (data.status === "approved" && data.certificate && data.hivePublicInfo) {
        // Auto-finalize
        stopJoinPolling();
        const memberResult: any = await r2.hiveJoinAsMember(data.hivePublicInfo, data.certificate);
        if (memberResult?.errors) {
          status("Error finalizing join: " + memberResult.errors[0]?.message);
        } else {
          status("Joined hive successfully!");
          onRefresh?.();
        }
        joiningPeerId = null;
        joinRequestId = null;
        joinTargetR2 = null;
      } else if (data.status === "denied") {
        stopJoinPolling();
        status("Join request was denied");
        joiningPeerId = null;
        joinRequestId = null;
        joinTargetR2 = null;
      }
    } catch {
      // network error, keep polling
    }
  }

  function stopJoinPolling() {
    if (joinPollingTimer) { clearInterval(joinPollingTimer); joinPollingTimer = null; }
  }

  function cancelJoinRequest() {
    stopJoinPolling();
    joiningPeerId = null;
    joinRequestId = null;
    joinTargetR2 = null;
  }

  // --- Key holder: Manage incoming join requests ---

  function startRequestsPolling() {
    if (requestsPollingTimer) return;
    pollPendingRequests();
    requestsPollingTimer = setInterval(pollPendingRequests, 3000);
  }

  function stopRequestsPolling() {
    if (requestsPollingTimer) { clearInterval(requestsPollingTimer); requestsPollingTimer = null; }
  }

  async function pollPendingRequests() {
    try {
      const result: any = await r2.hivePendingJoinRequests();
      if (result?.errors) return;
      const data = result?.data?.hivePendingJoinRequests;
      if (Array.isArray(data)) {
        pendingRequests = data;
      }
    } catch {
      // ignore
    }
  }

  async function handleApprove(requestId: string) {
    approvingId = requestId;
    try {
      const result: any = await r2.hiveApproveJoinRequest(requestId);
      if (result?.errors) {
        status("Approve error: " + result.errors[0]?.message);
      } else {
        status("Join request approved");
        pollPendingRequests();
      }
    } catch (err) {
      status("Approve error: " + (err as Error).message);
    } finally {
      approvingId = null;
    }
  }

  async function handleDeny(requestId: string) {
    try {
      const result: any = await r2.hiveDenyJoinRequest(requestId);
      if (result?.errors) {
        status("Deny error: " + result.errors[0]?.message);
      } else {
        status("Join request denied");
        pollPendingRequests();
      }
    } catch (err) {
      status("Deny error: " + (err as Error).message);
    }
  }

  // --- Start/stop key holder polling based on state ---
  $effect(() => {
    if (hasHive && isKeyHolder) {
      startRequestsPolling();
    } else {
      stopRequestsPolling();
    }
    return () => {
      stopRequestsPolling();
      stopJoinPolling();
    };
  });

  // --- Utility ---

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

  let isKeyHolder = $derived(nodeInfo?.hiveMode === "key_holder");
  let hasHive = $derived(!!nodeInfo?.hiveName);

  function getPeerIp(peer: any): string | null {
    const ip = peer.reachability?.wifi?.ip;
    if (ip) return ip;
    // peer.address may be a MAC address (contains colons but no dots) — skip those
    if (peer.address && /^\d+\.\d+\.\d+\.\d+$/.test(peer.address)) return peer.address;
    return null;
  }

  // Peers that have a hive and we could join
  let joinablePeers = $derived(
    peers.filter((p: any) => p.hiveId && !p.isSameHive && getPeerIp(p))
  );
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
                <span class="ui mini label" class:blue={isKeyHolder} class:grey={!isKeyHolder}>
                  {isKeyHolder ? 'Key Holder' : 'Member'}
                </span>
              </td></tr>
              {#if nodeInfo.hiveCompressedId}
                <tr><td class="label-cell">Compressed ID</td><td class="mono">{nodeInfo.hiveCompressedId}</td></tr>
              {/if}
            {:else}
              <tr><td class="label-cell">Hive</td><td style="color: #999;">Not configured</td></tr>
            {/if}
            <tr><td class="label-cell">Server</td><td class="mono">{nodeInfo.version || '?'} <span class="build-time">({nodeInfo.buildTime || '?'})</span></td></tr>
            <tr><td class="label-cell">Creator</td><td class="mono">{__APP_VERSION__} <span class="build-time">({__BUILD_TIME__})</span></td></tr>
          </tbody>
        </table>

        <!-- Hive actions -->
        <div class="hive-actions">
          {#if !hasHive}
            <div class="action-group">
              <label class="action-label">Create a new hive</label>
              <div class="inline-form">
                <div class="ui mini input">
                  <input type="text" placeholder="Hive name" bind:value={newHiveName}
                    onkeydown={(e) => { if (e.key === "Enter") handleCreateHive(); }} />
                </div>
                <button class="ui mini primary button" disabled={creating || !newHiveName.trim()} onclick={handleCreateHive}>
                  {creating ? "Creating..." : "Create"}
                </button>
              </div>
            </div>
          {:else}
            {#if nodeInfo.isProvisional}
              <button class="ui mini button" style="background: #43a047; color: #fff;" onclick={handleMarkEstablished}>
                <i class="check icon"></i> Confirm Hive
              </button>
            {/if}
            {#if isKeyHolder}
              <div class="action-group">
                <label class="action-label">Rename hive</label>
                <div class="inline-form">
                  <div class="ui mini input">
                    <input type="text" placeholder="New name" bind:value={newHiveName}
                      onkeydown={(e) => { if (e.key === "Enter") handleCreateHive(); }} />
                  </div>
                  <button class="ui mini button" disabled={creating || !newHiveName.trim()} onclick={handleCreateHive}>
                    Rename
                  </button>
                </div>
              </div>
            {/if}
          {/if}
        </div>
      {:else}
        <p style="color: #999;">Loading...</p>
      {/if}
    </div>

    <!-- Join Requests (key holder only) -->
    {#if hasHive && isKeyHolder}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="user plus icon"></i>
          Join Requests
          {#if pendingRequests.length > 0}
            <span class="ui mini circular red label" style="margin-left: 6px;">{pendingRequests.length}</span>
          {/if}
        </h4>
        {#if pendingRequests.length === 0}
          <p style="color: #999; font-size: 13px;">No pending join requests.</p>
        {:else}
          <div class="request-list">
            {#each pendingRequests as req}
              <div class="request-card">
                <div class="request-header">
                  <span class="request-name">
                    <i class="laptop icon"></i>
                    {req.nodeName}
                  </span>
                  <span class="request-time">{timeAgo(new Date(req.submittedAt * 1000).toISOString())}</span>
                </div>
                <div class="request-actions">
                  <button class="ui mini green button" disabled={approvingId === req.id}
                    onclick={() => handleApprove(req.id)}>
                    {approvingId === req.id ? "Approving..." : "Approve"}
                  </button>
                  <button class="ui mini red basic button" onclick={() => handleDeny(req.id)}>
                    Deny
                  </button>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    {/if}

    <!-- Joiner waiting state -->
    {#if joiningPeerId}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="spinner loading icon"></i>
          Waiting for Approval
        </h4>
        <p style="font-size: 13px; color: #555;">
          Your join request has been sent. Waiting for the key holder to approve...
        </p>
        <button class="ui mini basic button" onclick={cancelJoinRequest}>
          <i class="times icon"></i> Cancel
        </button>
      </div>
    {/if}

    <!-- Key Management (key_holder only) -->
    {#if hasHive && isKeyHolder}
      <div class="ui segment">
        <div class="section-toggle" onclick={() => (showKeySection = !showKeySection)}
          role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showKeySection = !showKeySection; }}>
          <i class="icon {showKeySection ? 'angle down' : 'angle right'}"></i>
          <h4 class="ui header" style="margin: 0; display: inline;">
            <i class="lock icon"></i>
            Key Management
          </h4>
        </div>
        {#if showKeySection}
          <div class="key-section">
            <div class="action-group">
              <label class="action-label">Export Key</label>
              <div class="inline-form">
                <div class="ui mini input">
                  <input type="password" placeholder="Passphrase" bind:value={exportPassphrase} />
                </div>
                <button class="ui mini button" disabled={!exportPassphrase.trim()} onclick={handleExportKey}>
                  <i class="download icon"></i> Export
                </button>
              </div>
            </div>
            <div class="action-group">
              <label class="action-label">Import Key</label>
              <div class="inline-form" style="flex-direction: column; align-items: stretch;">
                <input type="file" accept=".enc,.txt" onchange={handleImportFile} style="font-size: 11px; margin-bottom: 4px;" />
                {#if importData}
                  <div class="ui mini input" style="margin-bottom: 4px;">
                    <input type="password" placeholder="Passphrase" bind:value={importPassphrase} />
                  </div>
                  <button class="ui mini button" disabled={!importPassphrase.trim()} onclick={handleImportKey}>
                    <i class="upload icon"></i> Import
                  </button>
                {/if}
              </div>
            </div>
          </div>
        {/if}
      </div>
    {/if}

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
            {@const canJoin = !joiningPeerId && peer.hiveId && !peer.isSameHive && getPeerIp(peer)}
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
                  {#if peer.hiveId && !peer.isSameHive}
                    <span class="ui mini label" style="background: #7b1fa2; color: #fff;">Has Hive</span>
                  {/if}
                  <span class="ui mini label">{peer.transport || '?'}</span>
                </div>
              </div>
              <div class="peer-details">
                <span class="peer-detail" title="Node ID">{peer.nodeId?.slice(0, 8)}...</span>
                {#if getPeerIp(peer)}
                  <span class="peer-detail mono" title="Address">{getPeerIp(peer)}</span>
                {/if}
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
              <!-- Request to Join button -->
              {#if canJoin}
                <div class="join-action">
                  <button class="ui mini primary button" onclick={() => handleRequestToJoin(peer)}>
                    <i class="sign-in icon"></i> Request to Join Hive
                  </button>
                </div>
              {/if}
              {#if joiningPeerId === peer.nodeId}
                <div class="join-action">
                  <span class="join-waiting">
                    <i class="spinner loading icon"></i> Waiting for approval...
                  </span>
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
  .build-time {
    color: #999;
    font-size: 11px;
  }
  .hive-actions {
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid #eee;
  }
  .action-group {
    margin-bottom: 10px;
  }
  .action-label {
    display: block;
    font-size: 11px;
    font-weight: 600;
    color: #666;
    margin-bottom: 4px;
  }
  .inline-form {
    display: flex;
    gap: 6px;
    align-items: center;
  }
  .section-toggle {
    cursor: pointer;
    padding: 4px 0;
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .section-toggle:hover {
    opacity: 0.8;
  }
  .key-section {
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid #eee;
  }
  .request-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .request-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 10px 12px;
    border-left: 4px solid #ff9800;
  }
  .request-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 8px;
  }
  .request-name {
    font-weight: 600;
    font-size: 13px;
  }
  .request-time {
    font-size: 11px;
    color: #999;
  }
  .request-actions {
    display: flex;
    gap: 6px;
  }
  .join-action {
    margin-top: 8px;
    padding-top: 8px;
    border-top: 1px solid #eee;
  }
  .join-waiting {
    font-size: 12px;
    color: #1976d2;
    font-weight: 600;
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
