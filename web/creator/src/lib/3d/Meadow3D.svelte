<script lang="ts">
  import { Canvas } from '@threlte/core';
  import { getAdvancedMode } from '../stores/preferences-store.svelte';
  import Scene from './Scene.svelte';

  import type { LiveSentant, NodeInfo, Peer } from '../types';

  interface Props {
    nodeInfo?: NodeInfo;
    sentants?: LiveSentant[];
    peers?: Peer[];
    onSentantClick?: (sentant: LiveSentant) => void;
    onPeerClick?: (peer: Peer) => void;
    onHiveClick?: () => void;
  }

  let {
    nodeInfo,
    sentants = [],
    peers = [],
    onSentantClick,
    onPeerClick,
    onHiveClick
  }: Props = $props();

  // Debug: log when Meadow3D mounts
  import { onMount } from 'svelte';
  onMount(() => {
    console.log('Meadow3D mounted, rendering Canvas with', sentants.length, 'sentants and', peers.length, 'peers');
  });
</script>

<div class="meadow-container">
  <Canvas>
    <Scene
      {nodeInfo}
      {sentants}
      {peers}
      {onSentantClick}
      {onPeerClick}
      {onHiveClick}
    />
  </Canvas>

  <div class="mode-indicator">
    {getAdvancedMode() ? 'Advanced' : 'Standard'} View
  </div>
</div>

<style>
  .meadow-container {
    width: 100%;
    height: 100%;
    position: relative;
    background: linear-gradient(to bottom, #87CEEB 0%, #E0F7FA 50%, #81C784 100%);
  }

  .mode-indicator {
    position: absolute;
    top: 10px;
    right: 10px;
    background: rgba(0, 0, 0, 0.5);
    color: white;
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 11px;
  }
</style>
