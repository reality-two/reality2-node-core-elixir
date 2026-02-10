<script lang="ts">
  import Meadow3D from './Meadow3D.svelte';
  import type { NodeInfo, Peer, LiveSentant } from '../types';

  interface Props {
    // Real data (optional - falls back to demo if not provided)
    nodeInfo?: NodeInfo | null;
    sentants?: LiveSentant[];
    peers?: Peer[];

    // Data mode control: 'auto' uses real if available, else demo
    mode?: 'auto' | 'demo' | 'live';

    // Callbacks
    onClose?: () => void;
    onSentantClick?: (sentant: LiveSentant) => void;
    onPeerClick?: (peer: Peer) => void;
    onHiveClick?: () => void;
    onRefresh?: () => void;
  }

  let {
    nodeInfo = null,
    sentants = [],
    peers = [],
    mode = 'auto',
    onClose,
    onSentantClick,
    onPeerClick,
    onHiveClick,
    onRefresh,
  }: Props = $props();

  // Demo data - fallback when no real data available
  const demoNodeInfo: NodeInfo = {
    id: 'demo-node-001',
    name: 'My Hive',
    trustGroupId: 'meadow-001',
    trustGroupName: 'Home Meadow',
    isKeyHolder: true,
  };

  const demoSentants: LiveSentant[] = [
    {
      id: 'bee-001',
      name: 'Weather Bot',
      description: 'Fetches weather data',
      events: [{ event: 'get_weather', parameters: {} }],
      signals: ['weather_updated'],
      swarm: 'sensors',
    },
    {
      id: 'bee-002',
      name: 'Temperature Monitor',
      description: 'Monitors room temperature',
      events: [{ event: 'read_temp', parameters: {} }],
      signals: ['temp_reading'],
      swarm: 'sensors',
    },
    {
      id: 'bee-003',
      name: 'Light Controller',
      description: 'Controls smart lights',
      events: [{ event: 'set_brightness', parameters: { level: 'number' } }],
      signals: ['light_changed'],
      swarm: 'actuators',
    },
    {
      id: 'bee-004',
      name: 'Notification Hub',
      description: 'Sends notifications',
      events: [{ event: 'notify', parameters: { message: 'string' } }],
      signals: ['notification_sent'],
    },
    {
      id: 'bee-005',
      name: 'Data Logger',
      description: 'Logs sensor data',
      events: [{ event: 'log', parameters: { data: 'any' } }],
      signals: ['logged'],
      swarm: 'processors',
    },
  ];

  const demoPeers: Peer[] = [
    {
      nodeId: 'peer-001',
      name: 'Kitchen Hub',
      transport: 'ble',
      rssi: -45,
      sameTrustGroup: true,
    },
    {
      nodeId: 'peer-002',
      name: 'Garden Sensor',
      transport: 'lora',
      rssi: -78,
      sameTrustGroup: true,
    },
    {
      nodeId: 'peer-003',
      name: 'Living Room',
      transport: 'wifi',
      rssi: -52,
      sameTrustGroup: true,
    },
    {
      nodeId: 'peer-004',
      name: 'Unknown Device',
      transport: 'ble',
      rssi: -85,
      sameTrustGroup: false,
    },
    {
      nodeId: 'peer-005',
      name: 'Cloud Gateway',
      transport: 'internet',
      rssi: -60,
      sameTrustGroup: false,
    },
  ];

  // Determine if we have real data
  const hasRealData = $derived(
    nodeInfo != null ||
    (sentants && sentants.length > 0) ||
    (peers && peers.length > 0)
  );

  // Compute effective mode
  const effectiveMode = $derived(
    mode === 'demo' ? 'demo' :
    mode === 'live' ? 'live' :
    hasRealData ? 'live' : 'demo'
  );

  // Select data based on mode
  const activeNodeInfo = $derived(
    effectiveMode === 'live' && nodeInfo ? nodeInfo : demoNodeInfo
  );

  const activeSentants = $derived(
    effectiveMode === 'live' && sentants && sentants.length > 0
      ? sentants
      : demoSentants
  );

  const activePeers = $derived(
    effectiveMode === 'live' && peers && peers.length > 0
      ? peers
      : demoPeers
  );

  // Empty state detection (live mode but no real data)
  const isEmpty = $derived(
    effectiveMode === 'live' &&
    (!sentants || sentants.length === 0) &&
    (!peers || peers.length === 0) &&
    !nodeInfo
  );

  // For switching to demo mode from empty state
  let forceDemo = $state(false);

  const showDemoMode = $derived(forceDemo || effectiveMode === 'demo');

  // Click handlers with fallback for demo mode
  function handleSentantClick(sentant: LiveSentant) {
    if (onSentantClick) {
      onSentantClick(sentant);
    } else {
      // Default behavior for demo mode
      console.log('Clicked sentant:', sentant.name);
      alert(`Bee: ${sentant.name}\n${sentant.description || 'No description'}`);
    }
  }

  function handlePeerClick(peer: Peer) {
    if (onPeerClick) {
      onPeerClick(peer);
    } else {
      console.log('Clicked peer:', peer.name);
      const signal = peer.rssi ? `${peer.rssi} dBm` : 'Unknown';
      alert(`Peer: ${peer.name || peer.nodeId}\nTransport: ${peer.transport}\nSignal: ${signal}`);
    }
  }

  function handleHiveClick() {
    if (onHiveClick) {
      onHiveClick();
    } else {
      alert(`Hive: ${activeNodeInfo.name}\nTrust Group: ${activeNodeInfo.trustGroupName || 'None'}`);
    }
  }

  // Debug: log when component mounts
  $effect(() => {
    console.log('Demo3D mounted', { nodeInfo: activeNodeInfo, sentants: activeSentants.length, peers: activePeers.length });
  });

  // Get unique transport types present in peers for dynamic legend
  function getTransportTypes(): Set<string> {
    const types: Set<string> = new Set();
    for (const p of activePeers) {
      types.add(p.transport?.toLowerCase() ?? 'unknown');
    }
    return types;
  }
</script>

<div class="demo-container">
  <div class="demo-header">
    <h3>3D Meadow View</h3>
    <div class="demo-info">
      <span class="mode-badge" class:live={!showDemoMode}>
        {showDemoMode ? 'Demo' : 'Live'}
      </span>
      <span title="Number of sentants">Bees: {activeSentants.length}</span>
      <span title="Number of connected peers">Peers: {activePeers.length}</span>
      {#if !showDemoMode && onRefresh}
        <button class="refresh-btn" onclick={onRefresh} title="Refresh data from node">
          <i class="sync icon"></i>
        </button>
      {/if}
    </div>
    <button class="close-btn" onclick={() => onClose?.()} title="Close 3D view">
      <i class="times icon"></i> Close
    </button>
  </div>

  <div class="meadow-wrapper">
    {#if isEmpty && !forceDemo}
      <div class="empty-state">
        <div class="empty-icon">
          <i class="hive icon"></i>
        </div>
        <h3>No Data Available</h3>
        <p>Browse a node to populate the 3D view with real bees and peers.</p>
        <div class="empty-actions">
          <button class="demo-btn" onclick={() => forceDemo = true}>
            Show Demo
          </button>
          {#if onRefresh}
            <button class="refresh-btn-large" onclick={onRefresh}>
              <i class="sync icon"></i> Refresh
            </button>
          {/if}
        </div>
      </div>
    {:else}
      <Meadow3D
        nodeInfo={activeNodeInfo}
        sentants={activeSentants}
        peers={activePeers}
        onSentantClick={handleSentantClick}
        onPeerClick={handlePeerClick}
        onHiveClick={handleHiveClick}
      />
    {/if}
  </div>

  <div class="demo-legend">
    <div class="legend-item">
      <span class="legend-color" style="background: #D4A84B"></span>
      <span>Your Hive</span>
    </div>
    <div class="legend-item">
      <span class="legend-color" style="background: #F5C842"></span>
      <span>Bees ({activeSentants.length})</span>
    </div>
    {#if getTransportTypes().has('ble') || getTransportTypes().has('bluetooth')}
      <div class="legend-item">
        <span class="legend-color" style="background: #2196F3"></span>
        <span>BLE Peer</span>
      </div>
    {/if}
    {#if getTransportTypes().has('wifi') || getTransportTypes().has('hotspot')}
      <div class="legend-item">
        <span class="legend-color" style="background: #4CAF50"></span>
        <span>WiFi Peer</span>
      </div>
    {/if}
    {#if getTransportTypes().has('lora')}
      <div class="legend-item">
        <span class="legend-color" style="background: #FF9800"></span>
        <span>LoRa Peer</span>
      </div>
    {/if}
    {#if getTransportTypes().has('internet') || getTransportTypes().has('tcp') || getTransportTypes().has('cloud')}
      <div class="legend-item">
        <span class="legend-color" style="background: #9C27B0"></span>
        <span>Internet Peer</span>
      </div>
    {/if}
    {#if activePeers.length === 0}
      <div class="legend-item muted">
        <span>No peers connected</span>
      </div>
    {/if}
  </div>

  <div class="demo-instructions">
    <p><strong>Controls:</strong> Drag to orbit | Scroll to zoom | Click for details</p>
    {#if showDemoMode}
      <p class="demo-notice">Showing demo data. Browse a node to see real data.</p>
    {:else}
      <p>Bees in the same swarm cluster together. Peers positioned by signal strength.</p>
    {/if}
  </div>
</div>

<style>
  .demo-container {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: #1a1a2e;
    z-index: 1000;
    display: flex;
    flex-direction: column;
  }

  .demo-header {
    display: flex;
    align-items: center;
    padding: 12px 20px;
    background: rgba(0, 0, 0, 0.3);
    border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  }

  .demo-header h3 {
    margin: 0;
    color: #fff;
    font-size: 16px;
  }

  .demo-info {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: 16px;
    color: rgba(255, 255, 255, 0.7);
    font-size: 13px;
  }

  .mode-badge {
    padding: 2px 10px;
    border-radius: 10px;
    font-size: 11px;
    font-weight: 600;
    background: rgba(255, 255, 255, 0.15);
    color: rgba(255, 255, 255, 0.7);
  }

  .mode-badge.live {
    background: rgba(76, 175, 80, 0.3);
    color: #81C784;
  }

  .refresh-btn {
    background: transparent;
    border: none;
    color: rgba(255, 255, 255, 0.7);
    cursor: pointer;
    padding: 4px 8px;
    border-radius: 4px;
    transition: all 0.2s;
  }

  .refresh-btn:hover {
    color: #fff;
    background: rgba(255, 255, 255, 0.1);
  }

  .close-btn {
    margin-left: 20px;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    color: #fff;
    padding: 6px 12px;
    border-radius: 4px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .close-btn:hover {
    background: rgba(255, 255, 255, 0.2);
  }

  .meadow-wrapper {
    flex: 1;
    overflow: hidden;
    position: relative;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: rgba(255, 255, 255, 0.8);
    text-align: center;
    padding: 40px;
  }

  .empty-icon {
    font-size: 64px;
    opacity: 0.4;
    margin-bottom: 20px;
    color: #F5C842;
  }

  .empty-state h3 {
    margin: 0 0 12px 0;
    font-size: 20px;
    font-weight: 500;
  }

  .empty-state p {
    margin: 0 0 24px 0;
    color: rgba(255, 255, 255, 0.6);
    max-width: 300px;
    line-height: 1.5;
  }

  .empty-actions {
    display: flex;
    gap: 12px;
  }

  .demo-btn {
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.3);
    color: #fff;
    padding: 10px 24px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 14px;
    transition: all 0.2s;
  }

  .demo-btn:hover {
    background: rgba(255, 255, 255, 0.2);
  }

  .refresh-btn-large {
    background: rgba(76, 175, 80, 0.2);
    border: 1px solid rgba(76, 175, 80, 0.4);
    color: #81C784;
    padding: 10px 24px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 14px;
    display: flex;
    align-items: center;
    gap: 8px;
    transition: all 0.2s;
  }

  .refresh-btn-large:hover {
    background: rgba(76, 175, 80, 0.3);
  }

  .demo-legend {
    display: flex;
    justify-content: center;
    gap: 20px;
    padding: 10px;
    background: rgba(0, 0, 0, 0.3);
    flex-wrap: wrap;
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 6px;
    color: rgba(255, 255, 255, 0.8);
    font-size: 12px;
  }

  .legend-item.muted {
    color: rgba(255, 255, 255, 0.4);
    font-style: italic;
  }

  .legend-color {
    width: 12px;
    height: 12px;
    border-radius: 50%;
  }

  .demo-instructions {
    padding: 8px 20px;
    background: rgba(0, 0, 0, 0.2);
    color: rgba(255, 255, 255, 0.6);
    font-size: 12px;
    text-align: center;
  }

  .demo-instructions p {
    margin: 4px 0;
  }

  .demo-notice {
    color: #FFD54F;
    font-style: italic;
  }
</style>
