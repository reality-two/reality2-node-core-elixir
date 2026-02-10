<script lang="ts">
  import { T, useTask } from '@threlte/core';
  import { Text } from '@threlte/extras';

  interface Props {
    position?: [number, number, number];
    name?: string;
    transport?: string;
    rssi?: number;
    sameTrustGroup?: boolean;
    onClick?: () => void;
  }

  let {
    position = [0, 0, 0],
    name = 'Peer',
    transport = 'unknown',
    rssi = -70,
    sameTrustGroup = false,
    onClick
  }: Props = $props();

  // Transport colors (matching Godot implementation)
  const transportColors: Record<string, string> = {
    ble: '#2196F3',       // Blue
    bluetooth: '#2196F3',
    wifi: '#4CAF50',      // Green
    hotspot: '#4CAF50',
    lora: '#FF9800',      // Orange
    internet: '#9C27B0',  // Purple
    tcp: '#9C27B0',
    cloud: '#9C27B0',
    unknown: '#9E9E9E',   // Gray
  };

  const color = transportColors[transport.toLowerCase()] ?? transportColors.unknown;

  // Size based on signal strength
  // -40 dBm (strong) -> 0.5, -90 dBm (weak) -> 0.2
  const size = 0.2 + ((rssi + 90) / 50) * 0.3;

  let hovered = $state(false);
  let pulseScale = $state(1);

  // Accumulated animation time (delta-based, not Date.now())
  let animTime = 0;

  // Pulse animation for same trust group
  useTask((delta) => {
    if (sameTrustGroup) {
      animTime += delta;
      pulseScale = 1 + Math.sin(animTime * 0.3) * 0.1;  // ~0.3 rad/s pulse
    }
  });

  // Signal strength description
  const signalStrength = rssi >= -50 ? 'Excellent' :
                         rssi >= -65 ? 'Good' :
                         rssi >= -75 ? 'Fair' : 'Weak';
</script>

<T.Group
  position.x={position[0]}
  position.y={position[1]}
  position.z={position[2]}
  scale={hovered ? 1.2 : pulseScale}
>
  <!-- Main sphere -->
  <T.Mesh
    castShadow
    on:click={() => onClick?.()}
    on:pointerenter={() => hovered = true}
    on:pointerleave={() => hovered = false}
  >
    <T.SphereGeometry args={[size, 16, 12]} />
    <T.MeshStandardMaterial
      color={color}
      roughness={0.3}
      metalness={0.5}
      emissive={sameTrustGroup ? color : '#000000'}
      emissiveIntensity={sameTrustGroup ? 0.4 : 0}
    />
  </T.Mesh>

  <!-- Trust group ring -->
  {#if sameTrustGroup}
    <T.Mesh rotation.x={Math.PI / 2}>
      <T.TorusGeometry args={[size + 0.1, 0.02, 8, 32]} />
      <T.MeshStandardMaterial
        color="#FFD700"
        emissive="#FFD700"
        emissiveIntensity={0.5}
      />
    </T.Mesh>
  {/if}

  <!-- Transport indicator icon (small shape on top) -->
  <T.Mesh position.y={size + 0.15}>
    {#if transport.toLowerCase() === 'ble' || transport.toLowerCase() === 'bluetooth'}
      <!-- Bluetooth-ish shape -->
      <T.OctahedronGeometry args={[0.08]} />
    {:else if transport.toLowerCase() === 'wifi' || transport.toLowerCase() === 'hotspot'}
      <!-- WiFi-ish shape -->
      <T.TorusGeometry args={[0.06, 0.02, 4, 16]} />
    {:else if transport.toLowerCase() === 'lora'}
      <!-- LoRa wave shape -->
      <T.ConeGeometry args={[0.06, 0.12, 3]} />
    {:else}
      <!-- Default: small sphere -->
      <T.SphereGeometry args={[0.05]} />
    {/if}
    <T.MeshStandardMaterial color={color} />
  </T.Mesh>

  <!-- Name and info label (hover only for performance) -->
  {#if hovered}
    <Text
      text={`${name}\n${signalStrength} (${rssi} dBm)`}
      position={[0, size + 0.5, 0]}
      fontSize={0.12}
      color="#333"
      anchorX="center"
      anchorY="bottom"
      outlineWidth={0.015}
      outlineColor="#ffffff"
      textAlign="center"
    />
  {/if}

  <!-- Glow for same trust group -->
  {#if sameTrustGroup}
    <T.PointLight
      color={color}
      intensity={0.4}
      distance={3}
    />
  {/if}
</T.Group>
