<script lang="ts">
  import { T, useTask } from '@threlte/core';
  import { OrbitControls, Grid, Float } from '@threlte/extras';
  import { Vector3 } from 'three';

  import Hive from './Hive.svelte';
  import Bee from './Bee.svelte';
  import PeerNode from './PeerNode.svelte';
  import Ground from './Ground.svelte';
  import { FloatySpringSystem, FloatySprings } from './floaty-springs';

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

  // Spring physics system for bees
  const beeSpringSystem = new FloatySpringSystem();

  // Spring physics system for peers
  const peerSpringSystem = new FloatySpringSystem();

  // Helper to create typed position maps
  type PositionMap = Map<string, Vector3>;
  function createPositionMap(): PositionMap {
    return new Map();
  }

  // Track bee positions reactively
  let beePositions: PositionMap = $state(createPositionMap());
  let peerPositions: PositionMap = $state(createPositionMap());

  // Initialize springs when sentants change
  $effect(() => {
    // Clear and rebuild bee springs
    beeSpringSystem.clear();
    const newPositions = createPositionMap();

    for (const sentant of sentants) {
      const existing = beePositions.get(sentant.id);
      const spring = new FloatySprings(existing, {
        closestDistance: 1.5,
        springStiffness: 0.15,
        centreSpringStiffness: 0.8,
        centreDistance: 3 + Math.random() * 2, // Varied orbit distances
        damping: 0.15,
        friction: 0.3,
        groupAffinity: 0.05, // Slight attraction to same swarm
      });
      spring.groupId = sentant.swarm;
      beeSpringSystem.add(sentant.id, spring);
      newPositions.set(sentant.id, spring.position);
    }

    beePositions = newPositions;
  });

  // Initialize springs when peers change
  $effect(() => {
    peerSpringSystem.clear();
    const newPositions = createPositionMap();

    for (const peer of peers) {
      const existing = peerPositions.get(peer.nodeId);
      // RSSI to distance: stronger signal = closer
      // -40 dBm (strong) -> 6 units, -90 dBm (weak) -> 15 units
      const rssi = peer.rssi ?? -70;
      const distance = 6 + ((rssi + 40) / -50) * 9;

      const spring = new FloatySprings(existing, {
        closestDistance: 3,
        springStiffness: 0.08,
        centreSpringStiffness: 0.5,
        centreDistance: Math.max(6, Math.min(15, distance)),
        damping: 0.2,
        friction: 0.4,
      });
      peerSpringSystem.add(peer.nodeId, spring);
      newPositions.set(peer.nodeId, spring.position);
    }

    peerPositions = newPositions;
  });

  // Frame throttling to reduce reactivity overhead
  let frameCount = 0;
  const UPDATE_INTERVAL = 3; // Sync positions every 3rd frame (20fps visual update)

  // Animation loop for physics
  useTask((delta) => {
    try {
      frameCount++;

      // Always update physics (smooth simulation)
      beeSpringSystem.update(delta, new Vector3(0, 2, 0)); // Center above ground
      peerSpringSystem.update(delta, new Vector3(0, 1, 0));

      // Only sync positions to Svelte state every N frames
      if (frameCount % UPDATE_INTERVAL !== 0) return;

      // Mutate existing Vector3 objects in place (avoids GC pressure from clone())
      for (const sentant of sentants) {
        const spring = beeSpringSystem.get(sentant.id);
        if (spring) {
          const existing = beePositions.get(sentant.id);
          if (existing) {
            existing.copy(spring.position);
          } else {
            beePositions.set(sentant.id, spring.position.clone());
          }
        }
      }
      // Trigger Svelte reactivity so template re-reads positions
      beePositions = beePositions;

      for (const peer of peers) {
        const spring = peerSpringSystem.get(peer.nodeId);
        if (spring) {
          const existing = peerPositions.get(peer.nodeId);
          if (existing) {
            existing.copy(spring.position);
          } else {
            peerPositions.set(peer.nodeId, spring.position.clone());
          }
        }
      }
      peerPositions = peerPositions;
    } catch (err) {
      console.error('Scene animation error:', err);
    }
  });

  // Camera settings
  const cameraPosition: [number, number, number] = [8, 6, 8];
</script>

<!-- Lighting -->
<T.AmbientLight intensity={0.6} />
<T.DirectionalLight
  position={[10, 20, 10]}
  intensity={1.2}
  castShadow
/>

<!-- Sky color (hemisphere light for ambient) -->
<T.HemisphereLight
  args={['#87CEEB', '#81C784', 0.4]}
/>

<!-- Camera with orbit controls -->
<T.PerspectiveCamera
  makeDefault
  position={cameraPosition}
  fov={50}
>
  <OrbitControls
    enableDamping
    dampingFactor={0.1}
    minDistance={3}
    maxDistance={30}
    maxPolarAngle={Math.PI / 2.1}
  />
</T.PerspectiveCamera>

<!-- Ground plane -->
<Ground />

<!-- Central Hive (your node) - TEMPORARILY SIMPLIFIED -->
<T.Mesh position={[0, 0.5, 0]}>
  <T.BoxGeometry args={[1, 1, 1]} />
  <T.MeshStandardMaterial color="#D4A84B" />
</T.Mesh>

<!-- TEMPORARILY DISABLED FOR DEBUGGING
<Hive
  position={[0, 0, 0]}
  name={nodeInfo?.name ?? 'My Hive'}
  isLocal={true}
  onClick={onHiveClick}
/>

{#each sentants as sentant (sentant.id)}
  {@const pos = beePositions.get(sentant.id)}
  {#if pos}
    <Bee
      position={[pos.x, pos.y, pos.z]}
      name={sentant.name}
      swarm={sentant.swarm}
      isActive={true}
      onClick={() => onSentantClick?.(sentant)}
    />
  {/if}
{/each}

{#each peers as peer (peer.nodeId)}
  {@const pos = peerPositions.get(peer.nodeId)}
  {#if pos}
    <PeerNode
      position={[pos.x, pos.y, pos.z]}
      name={peer.name ?? peer.nodeId.slice(0, 8)}
      transport={peer.transport}
      rssi={peer.rssi}
      sameTrustGroup={peer.sameTrustGroup}
      onClick={() => onPeerClick?.(peer)}
    />
  {/if}
{/each}
-->
