<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import type R2 from '../reality2';

  interface Props {
    r2: R2;
    pollInterval?: number;
  }

  let { r2, pollInterval = 5000 }: Props = $props();

  type HealthState = 'connecting' | 'healthy' | 'degraded' | 'critical';

  let health = $state<HealthState>('connecting');
  let peerCount = $state(0);
  let sentantCount = $state(0);
  let pollTimer: ReturnType<typeof setInterval>;

  // Health state calculation based on mesh connectivity
  function calculateHealth(peers: any[], sentants: any[]): HealthState {
    // If we have sentants running, the node itself is healthy
    const hasLocalActivity = sentants && sentants.length > 0;

    if (!peers || peers.length === 0) {
      // No peers but local activity = standalone mode (yellow)
      // No peers and no activity = possible issue (yellow)
      return hasLocalActivity ? 'healthy' : 'degraded';
    }

    const now = Date.now();
    const recentPeers = peers.filter(p => {
      if (!p.lastSeen) return true; // Assume recent if no timestamp
      const lastSeen = new Date(p.lastSeen).getTime();
      return (now - lastSeen) < 60000; // Active in last 60s
    });

    if (recentPeers.length === 0) {
      return 'critical'; // All peers stale
    }

    // Calculate average signal strength for peers with RSSI
    const peersWithRssi = recentPeers.filter(p => p.rssi != null);
    if (peersWithRssi.length > 0) {
      const avgRssi = peersWithRssi.reduce((sum, p) => sum + p.rssi, 0) / peersWithRssi.length;
      if (avgRssi < -90) return 'degraded'; // Weak signals
    }

    return 'healthy';
  }

  async function checkHealth() {
    try {
      // Fetch peers and sentants in parallel
      const [peersResult, sentantsResult]: any[] = await Promise.all([
        r2.peers(),
        r2.sentantAll({}, "id")
      ]);

      const peers = peersResult?.data?.peers ?? [];
      const sentants = sentantsResult?.data?.sentantAll ?? [];

      peerCount = peers.length;
      sentantCount = sentants.length;
      health = calculateHealth(peers, sentants);
    } catch {
      health = 'critical';
    }
  }

  onMount(() => {
    checkHealth();
    pollTimer = setInterval(checkHealth, pollInterval);
  });

  onDestroy(() => {
    if (pollTimer) clearInterval(pollTimer);
  });

  // Tooltip text
  let tooltip = $derived(
    health === 'connecting' ? 'Connecting...' :
    health === 'critical' ? 'Connection issues' :
    `${peerCount} peer${peerCount !== 1 ? 's' : ''}, ${sentantCount} sentant${sentantCount !== 1 ? 's' : ''}`
  );
</script>

<div
  class="mesh-health {health}"
  title={tooltip}
  role="status"
  aria-label="Mesh health: {health}"
>
  <div class="core"></div>
  <div class="pulse"></div>
</div>

<style>
  .mesh-health {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    position: relative;
    cursor: default;
    flex-shrink: 0;
  }

  .core {
    position: absolute;
    inset: 2px;
    border-radius: 50%;
    z-index: 1;
  }

  .pulse {
    position: absolute;
    inset: 0;
    border-radius: 50%;
    opacity: 0.6;
  }

  /* Healthy - green with gentle breathing */
  .healthy {
    background: rgba(34, 197, 94, 0.3);
  }
  .healthy .core {
    background: #22c55e;
  }
  .healthy .pulse {
    background: #22c55e;
    animation: breathe 3s ease-in-out infinite;
  }

  /* Degraded - yellow with slower pulse */
  .degraded {
    background: rgba(234, 179, 8, 0.3);
  }
  .degraded .core {
    background: #eab308;
  }
  .degraded .pulse {
    background: #eab308;
    animation: breathe 4s ease-in-out infinite;
  }

  /* Critical - red, no animation (demands attention) */
  .critical {
    background: rgba(239, 68, 68, 0.3);
  }
  .critical .core {
    background: #ef4444;
  }
  .critical .pulse {
    background: #ef4444;
    animation: none;
  }

  /* Connecting - blue with faster pulse */
  .connecting {
    background: rgba(59, 130, 246, 0.3);
  }
  .connecting .core {
    background: #3b82f6;
  }
  .connecting .pulse {
    background: #3b82f6;
    animation: breathe 1.5s ease-in-out infinite;
  }

  @keyframes breathe {
    0%, 100% {
      opacity: 0.6;
      transform: scale(1);
    }
    50% {
      opacity: 0.2;
      transform: scale(1.4);
    }
  }
</style>
