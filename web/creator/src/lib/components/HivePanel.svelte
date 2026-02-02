<script lang="ts">
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

  // --- Join code ---
  let joinCode = $state<string | null>(null);
  let joinCountdown = $state(0);
  let joinTimer: ReturnType<typeof setInterval> | null = null;

  // --- Key management ---
  let exportPassphrase = $state("");
  let importPassphrase = $state("");
  let importData = $state("");
  let showKeySection = $state(false);

  // --- Join hive ---
  let joinAddress = $state("");
  let joinInputCode = $state("");
  let joining = $state(false);

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

  async function handleGenerateJoinCode() {
    try {
      const result: any = await r2.hiveGenerateJoinCode();
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
        return;
      }
      const data = result?.data?.hiveGenerateJoinCode;
      if (data?.code) {
        joinCode = data.code;
        joinCountdown = data.expiresIn || 300;
        if (joinTimer) clearInterval(joinTimer);
        joinTimer = setInterval(() => {
          joinCountdown--;
          if (joinCountdown <= 0) {
            joinCode = null;
            joinCountdown = 0;
            if (joinTimer) { clearInterval(joinTimer); joinTimer = null; }
          }
        }, 1000);
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
        // Download as file
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

  async function handleJoinHive() {
    const addr = joinAddress.trim();
    const code = joinInputCode.trim().toUpperCase();
    if (!addr || !code) return;
    joining = true;
    try {
      // 1. Get our public key
      const keyResult: any = await r2.hiveGetPublicKey();
      if (keyResult?.errors) {
        status("Error getting public key: " + keyResult.errors[0]?.message);
        return;
      }
      const publicKey = keyResult?.data?.hiveGetPublicKey;
      if (!publicKey) {
        status("Error: no public key returned");
        return;
      }

      // 2. Get our node name
      const nodeName = nodeInfo?.nodeName || "unknown";

      // 3. Connect to key holder and send join request
      const port = parseInt(DEFAULT_PORT);
      const r2Remote = new R2(addr, port, true);
      let joinResult: any;
      try {
        joinResult = await r2Remote.hiveProcessJoinRequest(code, nodeName, publicKey);
      } catch {
        // Retry without SSL
        const r2RemoteInsecure = new R2(addr, port, false);
        joinResult = await r2RemoteInsecure.hiveProcessJoinRequest(code, nodeName, publicKey);
      }

      if (joinResult?.errors) {
        status("Join error: " + joinResult.errors[0]?.message);
        return;
      }

      const data = joinResult?.data?.hiveProcessJoinRequest;
      if (!data?.certificate || !data?.hivePublicInfo) {
        status("Error: incomplete join response");
        return;
      }

      // 4. Finalize locally
      const memberResult: any = await r2.hiveJoinAsMember(data.hivePublicInfo, data.certificate);
      if (memberResult?.errors) {
        status("Error finalizing join: " + memberResult.errors[0]?.message);
        return;
      }

      joinAddress = "";
      joinInputCode = "";
      status("Joined hive successfully!");
      onRefresh?.();
    } catch (err) {
      status("Join error: " + (err as Error).message);
    } finally {
      joining = false;
    }
  }

  function formatCountdown(secs: number): string {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

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

  // Peers with a reachable IP (candidates for join target)
  let reachablePeers = $derived(
    peers.filter((p: any) => getPeerIp(p)).map((p: any) => ({
      nodeId: p.nodeId,
      nodeName: p.nodeName || p.nodeId?.slice(0, 8),
      ip: getPeerIp(p)!,
    }))
  );

  function getPeerIp(peer: any): string | null {
    return peer.reachability?.wifi?.ip || peer.address || null;
  }
  let joinManual = $state(false);
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

    <!-- Join Hive (when no hive or provisional) -->
    {#if !hasHive || nodeInfo?.isProvisional}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="sign-in icon"></i>
          Join Existing Hive
        </h4>
        <div class="action-group">
          <label class="action-label">Key holder node</label>
          {#if reachablePeers.length > 0 && !joinManual}
            <div class="peer-picker">
              {#each reachablePeers as peer}
                <button class="peer-pick-btn" class:selected={joinAddress === peer.ip}
                  onclick={() => { joinAddress = peer.ip; }}>
                  <i class="wifi icon" style="color: #43a047;"></i>
                  <span class="peer-pick-name">{peer.nodeName}</span>
                  <span class="peer-pick-ip">{peer.ip}</span>
                </button>
              {/each}
            </div>
            <button class="manual-link" onclick={() => { joinManual = true; }}>
              Enter address manually
            </button>
          {:else}
            <div class="ui mini input fluid">
              <input type="text" placeholder="hostname or IP" bind:value={joinAddress} />
            </div>
            {#if reachablePeers.length > 0}
              <button class="manual-link" onclick={() => { joinManual = false; joinAddress = ""; }}>
                Pick from nearby peers
              </button>
            {:else}
              <p style="font-size: 11px; color: #999; margin-top: 4px;">No nearby peers with WiFi found. Enter address manually.</p>
            {/if}
          {/if}
        </div>
        <div class="action-group">
          <label class="action-label">Join code</label>
          <div class="inline-form">
            <div class="ui mini input">
              <input type="text" placeholder="XXXX" maxlength="4"
                style="font-family: monospace; font-size: 16px; letter-spacing: 4px; width: 100px; text-transform: uppercase;"
                bind:value={joinInputCode}
                onkeydown={(e) => { if (e.key === "Enter") handleJoinHive(); }} />
            </div>
            <button class="ui mini primary button" disabled={joining || !joinAddress.trim() || joinInputCode.trim().length < 4} onclick={handleJoinHive}>
              {joining ? "Joining..." : "Join"}
            </button>
          </div>
        </div>
      </div>
    {/if}

    <!-- Join Codes (key_holder only) -->
    {#if hasHive && isKeyHolder}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="key icon"></i>
          Join Codes
        </h4>
        {#if joinCode}
          <div class="join-code-display">
            <span class="join-code">{joinCode}</span>
            <span class="join-countdown">{formatCountdown(joinCountdown)}</span>
          </div>
          <p class="join-hint">Share this code with nodes that want to join the hive.</p>
        {/if}
        <button class="ui mini basic button" onclick={handleGenerateJoinCode}>
          <i class="plus icon"></i> Generate Code
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
  .join-code-display {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 8px;
  }
  .join-code {
    font-family: monospace;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: 6px;
    color: #1976d2;
    background: #e3f2fd;
    padding: 8px 16px;
    border-radius: 6px;
    border: 2px solid #90caf9;
  }
  .join-countdown {
    font-size: 14px;
    font-weight: 600;
    color: #888;
  }
  .join-hint {
    font-size: 11px;
    color: #999;
    margin: 4px 0 8px;
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
  .peer-picker {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin-bottom: 4px;
  }
  .peer-pick-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 10px;
    border: 2px solid #ddd;
    border-radius: 6px;
    background: #fff;
    cursor: pointer;
    text-align: left;
    transition: border-color 0.15s, background 0.15s;
  }
  .peer-pick-btn:hover {
    border-color: #90caf9;
    background: #f0f7ff;
  }
  .peer-pick-btn.selected {
    border-color: #1976d2;
    background: #e3f2fd;
  }
  .peer-pick-name {
    font-weight: 600;
    font-size: 13px;
    flex: 1;
  }
  .peer-pick-ip {
    font-family: monospace;
    font-size: 11px;
    color: #888;
  }
  .manual-link {
    background: none;
    border: none;
    color: #1976d2;
    font-size: 11px;
    cursor: pointer;
    padding: 2px 0;
    text-decoration: underline;
  }
  .manual-link:hover {
    color: #0d47a1;
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
