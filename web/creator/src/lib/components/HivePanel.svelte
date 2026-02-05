<script lang="ts">
  declare const __APP_VERSION__: string;
  declare const __GIT_COMMIT__: string;

  import R2 from "../reality2";
  import { DEFAULT_PORT } from "../constants";
  import { getAdvancedMode } from "../stores/preferences-store.svelte";
  import { t } from "../i18n/terminology";

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

  // --- Trust group creation ---
  let newTrustGroupName = $state("");
  let creating = $state(false);

  // --- Key management ---
  let exportPassphrase = $state("");
  let importPassphrase = $state("");
  let importData = $state("");
  let showKeySection = $state(false);

  // --- Approval-based joining (joiner side, BLE GATT) ---
  let joiningPeerId = $state<string | null>(null);       // peer nodeId we're requesting to join
  let joinPollingTimer: ReturnType<typeof setInterval> | null = null;
  let joinMethod = $state<"ble" | "ip" | null>(null);    // which method is active

  // --- IP-based joining state ---
  let ipJoinRequestId: string | null = null;
  let ipJoinRemoteR2: R2 | null = null;

  // --- Approval-based joining (key holder side) ---
  let pendingRequests = $state<any[]>([]);
  let requestsPollingTimer: ReturnType<typeof setInterval> | null = null;
  let approvingId = $state<string | null>(null);

  // --- Trust group members (all approved nodes and viewers) ---
  let trustGroupMembers = $state<any[]>([]);

  function status(msg: string) {
    onStatus?.(msg);
  }

  async function handleCreateTrustGroup() {
    const name = newTrustGroupName.trim();
    if (!name) return;
    creating = true;
    try {
      const result: any = await r2.trustGroupCreate(name);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        newTrustGroupName = "";
        status("Group created: " + name);
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
      const result: any = await r2.trustGroupMarkEstablished();
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        status("Group confirmed");
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
      const result: any = await r2.trustGroupExportKey(pass);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
        return;
      }
      const data = result?.data?.trustGroupExportKey;
      if (data?.encryptedData) {
        const blob = new Blob([data.encryptedData], { type: "text/plain" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `trust-group-key-${nodeInfo?.trustGroupName || "export"}.enc`;
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
      const result: any = await r2.trustGroupImportKey(data, pass);
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

  // Determine the best join method for a peer
  function getJoinMethod(peer: any): "ble" | "ip" | null {
    // Prefer BLE if the peer has any BLE reachability (works on local networks with self-signed certs)
    if (peer.reachability?.ble?.confidence > 0) return "ble";
    // If the peer was discovered locally via WiFi, it's on the same local network.
    // The browser can't make direct HTTPS requests to other local nodes (self-signed certs),
    // so use BLE GATT which routes through the local server. The peer's BLE GATT should still
    // be reachable even if BLE beacon confidence has dropped.
    if (peer.reachability?.wifi?.confidence > 0) return "ble";
    // Only offer direct IP join for cloud/internet nodes (not locally discovered) that have
    // valid TLS certificates the browser will accept.
    const ip = getPeerIp(peer);
    if (ip) return "ip";
    return null;
  }

  async function handleRequestToJoin(peer: any) {
    const method = getJoinMethod(peer);
    if (!method) return;

    if (method === "ip") {
      await handleRequestToJoinIP(peer);
    } else {
      await handleRequestToJoinBLE(peer);
    }
  }

  // --- BLE-based join ---

  async function handleRequestToJoinBLE(peer: any) {
    joiningPeerId = peer.nodeId;
    joinMethod = "ble";
    try {
      const submitResult: any = await r2.trustGroupBleSubmitJoinRequest(peer.nodeId, nodeInfo?.nodeName || "unknown");

      if (submitResult?.errors) {
        status("Join request failed: " + submitResult.errors[0]?.message);
        resetJoinState();
        return;
      }

      const data = submitResult?.data?.trustGroupBleSubmitJoinRequest;
      if (data?.status === "approved") {
        status("Joined group successfully!");
        resetJoinState();
        onRefresh?.();
        return;
      }

      status("Join request sent via BLE — waiting for approval...");
      startJoinPolling();
    } catch (err) {
      status("Join request error: " + (err as Error).message);
      resetJoinState();
    }
  }

  // --- IP-based join ---

  async function handleRequestToJoinIP(peer: any) {
    const ip = getPeerIp(peer);
    if (!ip) return;

    joiningPeerId = peer.nodeId;
    joinMethod = "ip";
    try {
      // Get our public key from local server
      const pubKeyResult: any = await r2.trustGroupGetPublicKey();
      const publicKey = pubKeyResult?.data?.trustGroupGetPublicKey;
      if (!publicKey) {
        status("Failed to get public key");
        resetJoinState();
        return;
      }

      // Create R2 client pointing to remote node
      ipJoinRemoteR2 = new R2(ip, DEFAULT_PORT, true);

      // Submit join request to remote server
      const submitResult: any = await ipJoinRemoteR2.trustGroupSubmitJoinRequest(
        nodeInfo?.nodeName || "unknown",
        publicKey
      );

      if (submitResult?.errors) {
        status("IP join failed: " + submitResult.errors[0]?.message);
        resetJoinState();
        return;
      }

      const data = submitResult?.data?.trustGroupSubmitJoinRequest;
      ipJoinRequestId = data?.id;

      if (!ipJoinRequestId) {
        status("Failed to get request ID from remote");
        resetJoinState();
        return;
      }

      status("Join request sent via IP — waiting for approval...");
      startJoinPolling();
    } catch (err) {
      status("IP join error: " + (err as Error).message);
      resetJoinState();
    }
  }

  // --- Shared polling ---

  function startJoinPolling() {
    if (joinPollingTimer) clearInterval(joinPollingTimer);
    joinPollingTimer = setInterval(pollJoinStatus, 3000);
  }

  async function pollJoinStatus() {
    if (!joiningPeerId) return;

    if (joinMethod === "ip") {
      await pollIpJoinStatus();
    } else {
      await pollBleJoinStatus();
    }
  }

  async function pollBleJoinStatus() {
    if (!joiningPeerId) return;
    try {
      const result: any = await r2.trustGroupBleJoinRequestStatus(joiningPeerId);
      if (result?.errors) return;

      const data = result?.data?.trustGroupBleJoinRequestStatus;
      if (!data) return;

      if (data.status === "approved") {
        stopJoinPolling();
        status("Joined group successfully!");
        resetJoinState();
        onRefresh?.();
      } else if (data.status === "denied") {
        stopJoinPolling();
        status("Join request was denied");
        resetJoinState();
      }
    } catch {
      // GATT read error, keep polling
    }
  }

  async function pollIpJoinStatus() {
    if (!ipJoinRequestId || !ipJoinRemoteR2) return;
    try {
      const result: any = await ipJoinRemoteR2.trustGroupJoinRequestStatus(ipJoinRequestId);
      if (result?.errors) return;

      const data = result?.data?.trustGroupJoinRequestStatus;
      if (!data) return;

      if (data.status === "approved" && data.certificate && data.trustGroupPublicInfo) {
        stopJoinPolling();

        // Parse cert and trust group info if they're JSON strings
        const cert = typeof data.certificate === "string" ? JSON.parse(data.certificate) : data.certificate;
        const trustGroupInfo = typeof data.trustGroupPublicInfo === "string" ? JSON.parse(data.trustGroupPublicInfo) : data.trustGroupPublicInfo;

        // Install certificate on local server
        const joinResult: any = await r2.trustGroupJoinAsMember(trustGroupInfo, cert);
        if (joinResult?.errors) {
          status("Failed to install certificate: " + joinResult.errors[0]?.message);
        } else {
          status("Joined group successfully via IP!");
          onRefresh?.();
        }
        resetJoinState();
      } else if (data.status === "denied") {
        stopJoinPolling();
        status("Join request was denied");
        resetJoinState();
      }
    } catch {
      // keep polling
    }
  }

  function stopJoinPolling() {
    if (joinPollingTimer) { clearInterval(joinPollingTimer); joinPollingTimer = null; }
  }

  function resetJoinState() {
    stopJoinPolling();
    joiningPeerId = null;
    joinMethod = null;
    ipJoinRequestId = null;
    ipJoinRemoteR2 = null;
  }

  function cancelJoinRequest() {
    resetJoinState();
  }

  // --- Key holder: Manage incoming join requests ---

  // Visual notification state
  let showNotification = $state(false);
  let notificationMessage = $state("");
  let notificationTimeout: ReturnType<typeof setTimeout> | null = null;

  // Proximity prompt state
  let proximityDevice = $state<{nodeId: string; nodeName: string; rssi: number} | null>(null);
  let proximityTimeout: ReturnType<typeof setTimeout> | null = null;

  // Backup prompt state
  let showBackupPrompt = $state(false);
  let backupPromptDevice = $state("");
  let backupPromptTimeout: ReturnType<typeof setTimeout> | null = null;

  // Key holder state
  let showKeyHoldersSection = $state(false);
  let keyHolders = $state<any[]>([]);

  // Trusted groups state
  let showTrustSection = $state(false);
  let trustedGroups = $state<any[]>([]);
  let generatingTrustToken = $state(false);
  let currentTrustToken = $state<{token: string; expiresIn: number} | null>(null);

  function showJoinNotification(nodeName: string) {
    notificationMessage = `New join request from ${nodeName}`;
    showNotification = true;
    if (notificationTimeout) clearTimeout(notificationTimeout);
    notificationTimeout = setTimeout(() => {
      showNotification = false;
    }, 5000);
  }

  function showProximityPrompt(nodeId: string, nodeName: string, rssi: number) {
    // Clear any existing timeout
    if (proximityTimeout) clearTimeout(proximityTimeout);

    proximityDevice = { nodeId, nodeName: nodeName || "Unknown Device", rssi };

    // Auto-dismiss after 15 seconds
    proximityTimeout = setTimeout(() => {
      proximityDevice = null;
    }, 15000);
  }

  function dismissProximityPrompt() {
    if (proximityTimeout) clearTimeout(proximityTimeout);
    proximityDevice = null;
  }

  async function quickApproveProximityDevice() {
    if (!proximityDevice) return;

    // The device needs to submit a join request first - prompt user
    status(`Device "${proximityDevice.nodeName}" is nearby. Ask them to tap "Request to Join" on their device.`);
    dismissProximityPrompt();
  }

  function startRequestsPolling() {
    if (requestsPollingTimer) return;
    pollPendingRequests();
    // Still poll but less frequently since we have real-time notifications
    requestsPollingTimer = setInterval(pollPendingRequests, 10000);
  }

  function stopRequestsPolling() {
    if (requestsPollingTimer) { clearInterval(requestsPollingTimer); requestsPollingTimer = null; }
  }

  function setupJoinRequestSubscription() {
    r2.onJoinRequestReceived((data: any) => {
      if (data.status === "connected") {
        console.log("Join request subscription active");
        return;
      }
      // New join request received - refresh the list and show notification
      console.log("Join request received:", data);
      showJoinNotification(data.nodeName || "Unknown device");
      pollPendingRequests();
    });
  }

  function cleanupJoinRequestSubscription() {
    r2.unsubscribeJoinRequests();
  }

  function setupProximitySubscription() {
    r2.onProximityDeviceDetected((data: any) => {
      if (data.status === "connected") {
        console.log("Proximity subscription active");
        return;
      }
      // Very close device detected - show proximity prompt
      console.log("Proximity device detected:", data);
      showProximityPrompt(data.nodeId, data.nodeName, data.rssi);
    });
  }

  function cleanupProximitySubscription() {
    r2.unsubscribeProximity();
    if (proximityTimeout) clearTimeout(proximityTimeout);
  }

  function showBackupPromptBanner(deviceName: string) {
    backupPromptDevice = deviceName;
    showBackupPrompt = true;
    // Auto-dismiss after 30 seconds
    if (backupPromptTimeout) clearTimeout(backupPromptTimeout);
    backupPromptTimeout = setTimeout(() => {
      showBackupPrompt = false;
    }, 30000);
  }

  function dismissBackupPrompt() {
    if (backupPromptTimeout) clearTimeout(backupPromptTimeout);
    showBackupPrompt = false;
  }

  function handleBackupNow() {
    dismissBackupPrompt();
    // Open the backup section
    showKeySection = true;
  }

  function setupBackupPromptSubscription() {
    r2.onBackupPromptReceived((data: any) => {
      if (data.status === "connected") {
        console.log("Backup prompt subscription active");
        return;
      }
      // First device approved - show backup prompt
      console.log("Backup prompt received:", data);
      showBackupPromptBanner(data.deviceName || "a device");
    });
  }

  function cleanupBackupPromptSubscription() {
    r2.unsubscribeBackupPrompt();
    if (backupPromptTimeout) clearTimeout(backupPromptTimeout);
  }

  function formatDuration(seconds: number): string {
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
    return `${Math.floor(seconds / 86400)}d`;
  }

  // --- Key holder management ---

  async function fetchKeyHolders() {
    try {
      const result: any = await r2.keyHolders();
      if (result?.errors) return;
      const data = result?.data?.keyHolders;
      if (Array.isArray(data)) {
        keyHolders = data;
      }
    } catch {
      // ignore
    }
  }

  // --- Trust management ---

  async function fetchTrustedGroups() {
    try {
      const result: any = await r2.trustedGroups();
      if (result?.errors) return;
      const data = result?.data?.trustedGroups;
      if (Array.isArray(data)) {
        trustedGroups = data;
      }
    } catch {
      // ignore
    }
  }

  async function handleGenerateTrustToken() {
    generatingTrustToken = true;
    try {
      const result: any = await r2.trustGenerateToken(["read_only"]);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        const data = result?.data?.trustGenerateToken;
        if (data) {
          currentTrustToken = { token: data.token, expiresIn: data.expiresIn };
          status("Trust code generated - share with other group");
        }
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    } finally {
      generatingTrustToken = false;
    }
  }

  async function handleRevokeTrust(trustGroupId: string, name: string) {
    if (!confirm(`Revoke trust with "${name}"? They will no longer be able to see your apps.`)) {
      return;
    }
    try {
      const result: any = await r2.trustRevoke(trustGroupId);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        status("Trust revoked");
        fetchTrustedGroups();
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    }
  }

  async function pollPendingRequests() {
    try {
      const result: any = await r2.trustGroupPendingJoinRequests();
      if (result?.errors) return;
      const data = result?.data?.trustGroupPendingJoinRequests;
      if (Array.isArray(data)) {
        pendingRequests = data;
      }
    } catch {
      // ignore
    }
  }

  async function fetchTrustGroupMembers() {
    try {
      const result: any = await r2.trustGroupMembers();
      if (result?.errors) return;
      const data = result?.data?.trustGroupMembers;
      if (Array.isArray(data)) {
        trustGroupMembers = data;
      }
    } catch {
      // ignore
    }
  }

  async function handleClearStaleDirectory() {
    try {
      const result: any = await r2.trustGroupDirectoryClearStale();
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        const removed = result?.data?.trustGroupDirectoryClearStale ?? 0;
        status(`Cleared ${removed} stale entries`);
        onRefresh?.();
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    }
  }

  let removingMemberId = $state<string | null>(null);

  async function handleRemoveMember(nodeId: string, nodeName: string) {
    if (!confirm(`Remove "${nodeName}" from the group? This will revoke their access.`)) {
      return;
    }
    removingMemberId = nodeId;
    try {
      const result: any = await r2.trustGroupRemoveMember(nodeId);
      if (result?.errors) {
        status("Error: " + result.errors[0]?.message);
      } else {
        status(`Removed ${nodeName} from group`);
        fetchTrustGroupMembers();
      }
    } catch (err) {
      status("Error: " + (err as Error).message);
    } finally {
      removingMemberId = null;
    }
  }

  async function handleApprove(requestId: string) {
    approvingId = requestId;
    try {
      const result: any = await r2.trustGroupApproveJoinRequest(requestId);
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
      const result: any = await r2.trustGroupDenyJoinRequest(requestId);
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

  // --- Start/stop key holder polling and subscription based on state ---
  $effect(() => {
    if (hasTrustGroup && isKeyHolder) {
      startRequestsPolling();
      setupJoinRequestSubscription();
      setupProximitySubscription();
      setupBackupPromptSubscription();
    } else {
      stopRequestsPolling();
      cleanupJoinRequestSubscription();
      cleanupProximitySubscription();
      cleanupBackupPromptSubscription();
    }
    // Always fetch trust group members if we have a trust group
    if (hasTrustGroup) {
      fetchTrustGroupMembers();
    } else {
      trustGroupMembers = [];
    }
    return () => {
      stopRequestsPolling();
      stopJoinPolling();
      cleanupJoinRequestSubscription();
      cleanupProximitySubscription();
      cleanupBackupPromptSubscription();
      if (notificationTimeout) clearTimeout(notificationTimeout);
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

  let isKeyHolder = $derived(nodeInfo?.trustGroupMode === "key_holder");
  let hasTrustGroup = $derived(!!nodeInfo?.trustGroupName);

  function getPeerIp(peer: any): string | null {
    const ip = peer.reachability?.wifi?.ip;
    if (ip) return ip;
    // peer.address may be a MAC address (contains colons but no dots) — skip those
    if (peer.address && /^\d+\.\d+\.\d+\.\d+$/.test(peer.address)) return peer.address;
    return null;
  }

</script>

<div class="hive-panel">
  <!-- Join Request Notification Banner -->
  {#if showNotification}
    <div class="notification-banner" role="alert">
      <i class="bell icon"></i>
      <span>{notificationMessage}</span>
      <button class="dismiss-btn" onclick={() => showNotification = false}>
        <i class="times icon"></i>
      </button>
    </div>
  {/if}

  <!-- Proximity Device Prompt -->
  {#if proximityDevice}
    <div class="proximity-banner" role="alert">
      <div class="proximity-content">
        <i class="bluetooth icon"></i>
        <div class="proximity-info">
          <strong>{proximityDevice.nodeName}</strong>
          <span class="proximity-rssi">Very close ({proximityDevice.rssi} dBm)</span>
        </div>
      </div>
      <div class="proximity-actions">
        <button class="ui mini green button" onclick={quickApproveProximityDevice}>
          <i class="handshake icon"></i> Pair
        </button>
        <button class="ui mini basic button" onclick={dismissProximityPrompt}>
          Dismiss
        </button>
      </div>
    </div>
  {/if}

  <!-- Backup Prompt Banner -->
  {#if showBackupPrompt}
    <div class="backup-banner" role="alert">
      <div class="backup-content">
        <i class="shield alternate icon"></i>
        <div class="backup-info">
          <strong>Back up your group key</strong>
          <span class="backup-detail">You added "{backupPromptDevice}" to your group. Back up your key to avoid losing access if this device is lost.</span>
        </div>
      </div>
      <div class="backup-actions">
        <button class="ui mini green button" onclick={handleBackupNow}>
          <i class="download icon"></i> Back Up Now
        </button>
        <button class="ui mini basic button" onclick={dismissBackupPrompt}>
          Later
        </button>
      </div>
    </div>
  {/if}

  <div class="panel-body">
    <!-- This Hive/Device -->
    <div class="ui segment">
      <h4 class="ui header">
        <i class="server icon"></i>
        This {t("Hive")}
      </h4>
      {#if nodeInfo}
        <table class="ui very basic compact small table">
          <tbody>
            <tr><td class="label-cell">{t("Hive")} Name</td><td><strong>{nodeInfo.nodeName}</strong></td></tr>
            {#if getAdvancedMode()}
              <tr><td class="label-cell">{t("Hive")} ID</td><td class="mono">{nodeInfo.nodeId}</td></tr>
            {/if}
            {#if nodeInfo.trustGroupName}
              <tr><td class="label-cell">{t("Meadow")}</td><td><strong>{nodeInfo.trustGroupName}</strong></td></tr>
              {#if getAdvancedMode()}
                <tr><td class="label-cell">{t("Meadow")} ID</td><td class="mono">{nodeInfo.trustGroupId}</td></tr>
              {/if}
              <tr><td class="label-cell">Role</td><td>
                <span class="ui mini label" class:blue={isKeyHolder} class:grey={!isKeyHolder}>
                  {isKeyHolder ? t('Keeper') : t('Member')}
                </span>
              </td></tr>
              {#if getAdvancedMode() && nodeInfo.trustGroupCompressedId}
                <tr><td class="label-cell">Short ID</td><td class="mono">{nodeInfo.trustGroupCompressedId}</td></tr>
              {/if}
            {:else}
              <tr><td class="label-cell">{t("Meadow")}</td><td style="color: #999;">Not configured</td></tr>
            {/if}
            {#if getAdvancedMode()}
              <tr><td class="label-cell">Server</td><td class="mono">{nodeInfo.version || '?'} <span class="build-id">({nodeInfo.buildId || '?'})</span></td></tr>
              <tr><td class="label-cell">Creator</td><td class="mono">{__APP_VERSION__} <span class="build-id">({__GIT_COMMIT__})</span></td></tr>
            {/if}
          </tbody>
        </table>

        <!-- Meadow actions -->
        <div class="hive-actions">
          {#if !hasTrustGroup}
            <div class="action-group">
              <label class="action-label">Create a new {t("Meadow").toLowerCase()}</label>
              <div class="inline-form">
                <div class="ui mini input">
                  <input type="text" placeholder="{t('Meadow')} name" bind:value={newTrustGroupName}
                    onkeydown={(e) => { if (e.key === "Enter") handleCreateTrustGroup(); }} />
                </div>
                <button class="ui mini primary button" disabled={creating || !newTrustGroupName.trim()} onclick={handleCreateTrustGroup}>
                  {creating ? "Creating..." : "Create"}
                </button>
              </div>
            </div>
          {:else}
            {#if nodeInfo.isProvisional}
              <button class="ui mini button" style="background: #43a047; color: #fff;" onclick={handleMarkEstablished}>
                <i class="check icon"></i> Confirm {t("Meadow")}
              </button>
            {/if}
            {#if isKeyHolder}
              <div class="action-group">
                <label class="action-label">Rename {t("Meadow").toLowerCase()}</label>
                <div class="inline-form">
                  <div class="ui mini input">
                    <input type="text" placeholder="New name" bind:value={newTrustGroupName}
                      onkeydown={(e) => { if (e.key === "Enter") handleCreateTrustGroup(); }} />
                  </div>
                  <button class="ui mini button" disabled={creating || !newTrustGroupName.trim()} onclick={handleCreateTrustGroup}>
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

    <!-- Join Requests (owner only) -->
    {#if hasTrustGroup && isKeyHolder}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="user plus icon"></i>
          Pending {t("Hives")}
          {#if pendingRequests.length > 0}
            <span class="ui mini circular red label" style="margin-left: 6px;">{pendingRequests.length}</span>
          {/if}
        </h4>
        {#if pendingRequests.length === 0}
          <p style="color: #999; font-size: 13px;">No {t("hives")} waiting to join.</p>
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
          Your join request has been sent{#if getAdvancedMode()} via {joinMethod === "ble" ? "BLE" : "IP"}{/if}. Waiting for the {t("Keeper").toLowerCase()} to approve...
        </p>
        <button class="ui mini basic button" onclick={cancelJoinRequest}>
          <i class="times icon"></i> Cancel
        </button>
      </div>
    {/if}

    <!-- Backup & Recovery (owner only) -->
    {#if hasTrustGroup && isKeyHolder}
      <div class="ui segment">
        <div class="section-toggle" onclick={() => (showKeySection = !showKeySection)}
          role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') showKeySection = !showKeySection; }}>
          <i class="icon {showKeySection ? 'angle down' : 'angle right'}"></i>
          <h4 class="ui header" style="margin: 0; display: inline;">
            <i class="lock icon"></i>
            Backup & Recovery
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

      <!-- Keepers -->
      <div class="ui segment">
        <div class="section-toggle" onclick={() => { showKeyHoldersSection = !showKeyHoldersSection; if (showKeyHoldersSection) fetchKeyHolders(); }}
          role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') { showKeyHoldersSection = !showKeyHoldersSection; if (showKeyHoldersSection) fetchKeyHolders(); }}}>
          <i class="icon {showKeyHoldersSection ? 'angle down' : 'angle right'}"></i>
          <h4 class="ui header" style="margin: 0; display: inline;">
            <i class="key icon"></i>
            {t("Keeper")}s
          </h4>
          {#if keyHolders.length > 0}
            <span class="ui mini circular purple label" style="margin-left: 6px;">{keyHolders.length}</span>
          {/if}
        </div>
        {#if showKeyHoldersSection}
          <div class="key-holders-section">
            <p style="font-size: 12px; color: #666; margin-bottom: 12px;">
              {t("Hives")} that can manage your {t("Meadow").toLowerCase()}. Share your key using Backup & Recovery to add more {t("Keeper").toLowerCase()}s.
            </p>

            {#if keyHolders.length > 0}
              <div class="key-holder-list">
                {#each keyHolders as kh}
                  {@const isMe = kh.isLocal}
                  <div class="key-holder-card" class:is-local={isMe}>
                    <div class="key-holder-header">
                      <span class="key-holder-name">
                        <i class="key icon"></i>
                        {kh.nodeName || 'Unknown'}
                        {#if isMe}
                          <span style="font-weight: 400; opacity: 0.7;"> (this device)</span>
                        {/if}
                      </span>
                    </div>
                    <div class="key-holder-details">
                      {#if getAdvancedMode()}
                        <span class="key-holder-detail" title="Node ID">{kh.nodeId?.slice(0, 8)}...</span>
                      {/if}
                      {#if kh.lastSeen}
                        <span class="key-holder-detail" title={kh.lastSeen}>seen {timeAgo(kh.lastSeen)}</span>
                      {/if}
                    </div>
                  </div>
                {/each}
              </div>
            {:else}
              <p style="font-size: 12px; color: #999; margin-top: 12px;">No {t("Keeper").toLowerCase()} information available.</p>
            {/if}

            {#if keyHolders.length === 1}
              <div style="margin-top: 12px; padding: 10px; background: #fff3e0; border-radius: 6px; border: 1px solid #ffcc80;">
                <p style="font-size: 12px; color: #e65100; margin: 0;">
                  <i class="exclamation triangle icon"></i>
                  <strong>Single {t("Keeper").toLowerCase()}:</strong> If this {t("hive")} is lost, you'll lose access to your {t("meadow")}. Consider backing up your key to another {t("hive")}.
                </p>
              </div>
            {/if}
          </div>
        {/if}
      </div>

      <!-- Trusted Meadows -->
      <div class="ui segment">
        <div class="section-toggle" onclick={() => { showTrustSection = !showTrustSection; if (showTrustSection) fetchTrustedGroups(); }}
          role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') { showTrustSection = !showTrustSection; if (showTrustSection) fetchTrustedGroups(); }}}>
          <i class="icon {showTrustSection ? 'angle down' : 'angle right'}"></i>
          <h4 class="ui header" style="margin: 0; display: inline;">
            <i class="handshake icon"></i>
            Trusted {t("Meadow")}s
          </h4>
          {#if trustedGroups.length > 0}
            <span class="ui mini circular orange label" style="margin-left: 6px;">{trustedGroups.length}</span>
          {/if}
        </div>
        {#if showTrustSection}
          <div class="trust-section">
            <p style="font-size: 12px; color: #666; margin-bottom: 12px;">
              Share access to your {t("bees")} with other {t("meadow").toLowerCase()}s. Generate a trust code and share it with another {t("keeper").toLowerCase()}.
            </p>

            <div class="action-group">
              <label class="action-label">Generate Trust Code</label>
              <div class="inline-form">
                <button class="ui mini orange button" disabled={generatingTrustToken} onclick={handleGenerateTrustToken}>
                  {generatingTrustToken ? "Generating..." : "Generate Code"}
                </button>
              </div>
            </div>

            {#if currentTrustToken}
              <div class="trust-token-display">
                <div class="trust-token-code">{currentTrustToken.token}</div>
                <div class="trust-token-info">
                  <span>Expires in {formatDuration(currentTrustToken.expiresIn)}</span>
                  <button class="ui mini icon button" title="Copy code" onclick={() => { navigator.clipboard.writeText(currentTrustToken!.token); status("Code copied"); }}>
                    <i class="copy icon"></i>
                  </button>
                </div>
              </div>
            {/if}

            {#if trustedGroups.length > 0}
              <div class="trusted-hive-list">
                <label class="action-label" style="margin-top: 16px;">Trusted {t("Meadow")}s</label>
                {#each trustedGroups as th}
                  <div class="trusted-hive-card">
                    <div class="trusted-hive-header">
                      <span class="trusted-hive-name">
                        <i class="users icon"></i>
                        {th.name || 'Unknown ' + t('Meadow')}
                      </span>
                      <div class="trusted-hive-badges">
                        <span class="ui mini label" class:green={th.status === 'active'} class:red={th.status === 'revoked'}>
                          {th.status}
                        </span>
                      </div>
                    </div>
                    <div class="trusted-hive-details">
                      {#if getAdvancedMode()}
                        <span class="trusted-hive-detail" title="Trust Group ID">{th.trustGroupId?.slice(0, 8)}...</span>
                      {/if}
                      {#if th.establishedAt}
                        <span class="trusted-hive-detail">trusted {timeAgo(th.establishedAt)}</span>
                      {/if}
                      <span class="trusted-hive-detail">{th.permissions?.join(', ') || 'read_only'}</span>
                    </div>
                    <div class="trusted-hive-actions">
                      <button class="ui mini red basic button" onclick={() => handleRevokeTrust(th.trustGroupId, th.name)}>
                        <i class="times icon"></i> Revoke
                      </button>
                    </div>
                  </div>
                {/each}
              </div>
            {:else}
              <p style="font-size: 12px; color: #999; margin-top: 12px;">No trusted {t("meadow")}s yet.</p>
            {/if}
          </div>
        {/if}
      </div>
    {/if}

    <!-- Meadow Hives (when part of a meadow) -->
    {#if hasTrustGroup && trustGroupMembers.length > 0}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="users icon"></i>
          {t("Meadow")} {t("Hives")}
          <span class="ui mini circular label" style="margin-left: 6px;">{trustGroupMembers.length}</span>
        </h4>
        <div class="member-list">
          {#each trustGroupMembers as member}
            {@const isViewer = member.memberType === "viewer"}
            {@const isMe = member.nodeId === nodeInfo?.nodeId}
            <div class="member-card" class:is-viewer={isViewer}>
              <div class="member-header">
                <span class="member-name">
                  <i class="{isViewer ? 'mobile alternate' : 'server'} icon"></i>
                  {member.nodeName || 'Unknown'}
                  {#if isMe}
                    <span style="font-weight: 400; opacity: 0.7;"> (this device)</span>
                  {/if}
                </span>
                <div class="member-badges">
                  <span class="ui mini label" class:teal={isViewer} class:blue={!isViewer}>
                    {isViewer ? 'Viewer' : 'Device'}
                  </span>
                </div>
              </div>
              <div class="member-details">
                {#if getAdvancedMode()}
                  <span class="member-detail" title="Node ID">{member.nodeId?.slice(0, 8)}...</span>
                {/if}
                {#if member.approvedAt}
                  <span class="member-detail" title={member.approvedAt}>joined {timeAgo(member.approvedAt)}</span>
                {/if}
              </div>
              {#if isKeyHolder && !isMe}
                <div class="member-actions">
                  <button class="ui mini red basic button" disabled={removingMemberId === member.nodeId}
                    onclick={() => handleRemoveMember(member.nodeId, member.nodeName)}>
                    <i class="user times icon"></i>
                    {removingMemberId === member.nodeId ? "Removing..." : "Remove"}
                  </button>
                </div>
              {/if}
            </div>
          {/each}
        </div>
        <div style="margin-top: 8px; font-size: 11px; color: #888;">
          <i class="info circle icon"></i>
          {t("Visitor")}s are devices (phones, tablets) that can interact with the {t("meadow").toLowerCase()} but don't host {t("bees")}.
        </div>
      </div>
    {/if}

    <!-- Nearby Hives -->
    <div class="ui segment">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
        <h4 class="ui header" style="margin: 0;">
          <i class="wifi icon"></i>
          {t("Neighbour")}s
          {#if peers.length > 0}
            <span class="ui mini circular label" style="margin-left: 6px;">{peers.length}</span>
          {/if}
        </h4>
        <button class="ui mini basic icon button" onclick={onRefresh} title="Refresh">
          <i class="sync icon"></i>
        </button>
      </div>

      {#if peers.length === 0}
        <p style="color: #999; font-size: 13px;">No {t("neighbour")}s discovered yet.</p>
      {:else}
        <div class="peer-list">
          {#each peers as peer}
            {@const peerJoinMethod = getJoinMethod(peer)}
            {@const canJoin = !joiningPeerId && peer.trustGroupId && !peer.isSameTrustGroup && peerJoinMethod !== null}
            <div class="peer-card" class:same-hive={peer.isSameTrustGroup}>
              <div class="peer-header">
                <span class="peer-name">{peer.nodeName || 'Unknown'}</span>
                <div class="peer-badges">
                  {#if peer.isSameTrustGroup}
                    <span class="ui mini label" style="background: #43a047; color: #fff;">Same {t("Meadow")}</span>
                  {/if}
                  {#if peer.trustGroupVerified}
                    <span class="ui mini label" style="background: #1976d2; color: #fff;">Verified</span>
                  {/if}
                  {#if peer.trustGroupId && !peer.isSameTrustGroup}
                    <span class="ui mini label" style="background: #7b1fa2; color: #fff;">Has {t("Meadow")}</span>
                  {/if}
                  <span class="ui mini label">{peer.transport || '?'}</span>
                </div>
              </div>
              <div class="peer-details">
                {#if getAdvancedMode()}
                  <span class="peer-detail" title="Node ID">{peer.nodeId?.slice(0, 8)}...</span>
                  {#if getPeerIp(peer)}
                    <span class="peer-detail mono" title="Address">{getPeerIp(peer)}</span>
                  {/if}
                {/if}
                {#if peer.rssi != null}
                  {#if getAdvancedMode()}
                    <span class="peer-detail" title="Signal strength">{peer.rssi} dBm</span>
                  {:else}
                    <span class="peer-detail" title="Signal strength">{peer.rssi >= -50 ? 'Excellent' : peer.rssi >= -65 ? 'Good' : peer.rssi >= -75 ? 'Fair' : 'Weak'} signal</span>
                  {/if}
                {/if}
                {#if peer.sentantCount > 0}
                  <span class="peer-detail">{peer.sentantCount} app{peer.sentantCount !== 1 ? 's' : ''}</span>
                {/if}
                {#if getAdvancedMode()}
                  <span class="peer-detail">{peer.connectionState}</span>
                {/if}
              </div>
              {#if getAdvancedMode() && peer.reachability}
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
                    <i class="sign-in icon"></i> Request to Join {t("Meadow")}
                    {#if getAdvancedMode()}
                      <span style="opacity: 0.7; font-size: 11px;">({peerJoinMethod === "ble" ? "BLE" : "IP"})</span>
                    {/if}
                  </button>
                </div>
              {/if}
              {#if joiningPeerId === peer.nodeId}
                <div class="join-action">
                  <span class="join-waiting">
                    <i class="spinner loading icon"></i> Waiting for approval{#if getAdvancedMode()} via {joinMethod === "ble" ? "BLE" : "IP"}{/if}...
                  </span>
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <!-- Meadow Map -->
    {#if directory}
      <div class="ui segment">
        <h4 class="ui header">
          <i class="sitemap icon"></i>
          {t("Meadow")} {t("Map")}
          {#if directory.trustGroupName}
            <span style="font-weight: 400; font-size: 13px; color: #666;"> — {directory.trustGroupName}</span>
          {/if}
        </h4>
        {#if directory.nodes && directory.nodes.length > 0}
          <div class="peer-list">
            {#each [...directory.nodes].sort((a, b) => new Date(b.updatedAt || 0).getTime() - new Date(a.updatedAt || 0).getTime()) as node}
              {@const stale = node.nodeId !== directory.myNodeId && isStale(node.updatedAt)}
              <div class="peer-card" class:is-me={node.nodeId === directory.myNodeId} class:stale-node={stale}>
                <div class="peer-header">
                  <span class="peer-name">
                    {node.name || 'Unknown'}
                    {#if node.nodeId === directory.myNodeId}
                      <span style="font-weight: 400; opacity: 0.7;"> (this device)</span>
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
                  {#if getAdvancedMode()}
                    <span class="peer-detail" title="Node ID">{node.nodeId?.slice(0, 8)}...</span>
                  {/if}
                  {#if node.sentants && node.sentants.length > 0}
                    <span class="peer-detail">{node.sentants.length} app{node.sentants.length !== 1 ? 's' : ''}</span>
                  {/if}
                  {#if node.updatedAt}
                    <span class="peer-detail" title={node.updatedAt}>updated {timeAgo(node.updatedAt)}</span>
                  {/if}
                </div>
              </div>
            {/each}
          </div>
        {:else}
          <p style="color: #999; font-size: 13px;">No {t("hives")} in {t("map").toLowerCase()} yet.</p>
        {/if}
        {#if getAdvancedMode()}
          <div style="margin-top: 10px; display: flex; align-items: center; justify-content: space-between;">
            <span style="font-size: 11px; color: #aaa;">
              Directory version: {directory.directoryVersion ?? 0}
            </span>
            <button class="ui mini basic button" onclick={handleClearStaleDirectory} title="Remove entries not updated in over 1 hour">
              <i class="trash icon"></i> Clear Stale
            </button>
          </div>
        {/if}
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
  .notification-banner {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 16px;
    background: linear-gradient(135deg, #ff9800, #f57c00);
    color: white;
    font-weight: 600;
    font-size: 13px;
    animation: slideDown 0.3s ease-out;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
  }
  .notification-banner .bell.icon {
    font-size: 16px;
    animation: ring 0.5s ease-in-out;
  }
  .notification-banner .dismiss-btn {
    margin-left: auto;
    background: transparent;
    border: none;
    color: white;
    cursor: pointer;
    padding: 4px;
    opacity: 0.8;
  }
  .notification-banner .dismiss-btn:hover {
    opacity: 1;
  }
  @keyframes slideDown {
    from {
      transform: translateY(-100%);
      opacity: 0;
    }
    to {
      transform: translateY(0);
      opacity: 1;
    }
  }
  @keyframes ring {
    0%, 100% { transform: rotate(0); }
    25% { transform: rotate(15deg); }
    75% { transform: rotate(-15deg); }
  }
  .proximity-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    background: linear-gradient(135deg, #2196f3, #1565c0);
    color: white;
    animation: slideDown 0.3s ease-out;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
  }
  .proximity-content {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .proximity-content .bluetooth.icon {
    font-size: 24px;
    animation: pulse 1s infinite;
  }
  .proximity-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .proximity-info strong {
    font-size: 14px;
  }
  .proximity-rssi {
    font-size: 11px;
    opacity: 0.9;
  }
  .proximity-actions {
    display: flex;
    gap: 8px;
  }
  .proximity-actions .button {
    margin: 0 !important;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.6; }
  }
  .backup-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    background: linear-gradient(135deg, #43a047, #2e7d32);
    color: white;
    animation: slideDown 0.3s ease-out;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
  }
  .backup-content {
    display: flex;
    align-items: center;
    gap: 12px;
    flex: 1;
  }
  .backup-content .shield.icon {
    font-size: 24px;
  }
  .backup-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .backup-info strong {
    font-size: 14px;
  }
  .backup-detail {
    font-size: 12px;
    opacity: 0.9;
  }
  .backup-actions {
    display: flex;
    gap: 8px;
    flex-shrink: 0;
  }
  .backup-actions .button {
    margin: 0 !important;
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
  .build-id {
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
  .member-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .member-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 10px 12px;
    border-left: 4px solid #1976d2;
  }
  .member-card.is-viewer {
    border-left-color: #00897b;
    background: #f0fdfb;
  }
  .member-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .member-name {
    font-weight: 600;
    font-size: 13px;
  }
  .member-badges {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }
  .member-details {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 4px;
  }
  .member-detail {
    font-size: 11px;
    color: #777;
  }
  .member-actions {
    margin-top: 8px;
    padding-top: 8px;
    border-top: 1px solid #eee;
  }
  .key-holders-section {
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid #eee;
  }
  .key-holder-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .key-holder-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 10px 12px;
    border-left: 4px solid #9c27b0;
  }
  .key-holder-card.is-local {
    border-left-color: #1976d2;
    background: #f0f7ff;
  }
  .key-holder-header {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .key-holder-name {
    font-weight: 600;
    font-size: 13px;
  }
  .key-holder-details {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 4px;
  }
  .key-holder-detail {
    font-size: 11px;
    color: #777;
  }
  .trust-section {
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid #eee;
  }
  .trust-token-display {
    background: #fff3e0;
    border: 1px solid #ffcc80;
    border-radius: 8px;
    padding: 16px;
    margin-top: 12px;
    text-align: center;
  }
  .trust-token-code {
    font-family: monospace;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: 4px;
    color: #e65100;
    margin-bottom: 8px;
  }
  .trust-token-info {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    font-size: 12px;
    color: #bf360c;
  }
  .trusted-hive-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .trusted-hive-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 10px 12px;
    border-left: 4px solid #ff9800;
  }
  .trusted-hive-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .trusted-hive-name {
    font-weight: 600;
    font-size: 13px;
  }
  .trusted-hive-badges {
    display: flex;
    gap: 4px;
  }
  .trusted-hive-details {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 4px;
  }
  .trusted-hive-detail {
    font-size: 11px;
    color: #777;
  }
  .trusted-hive-actions {
    margin-top: 8px;
    padding-top: 8px;
    border-top: 1px solid #eee;
  }
</style>
