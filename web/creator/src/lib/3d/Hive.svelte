<script lang="ts">
  import { T } from '@threlte/core';
  import { Text } from '@threlte/extras';
  import { DoubleSide } from 'three';

  interface Props {
    position?: [number, number, number];
    name?: string;
    isLocal?: boolean;
    onClick?: () => void;
  }

  let {
    position = [0, 0, 0],
    name = 'Hive',
    isLocal = false,
    onClick
  }: Props = $props();

  // Colors
  const hiveColor = isLocal ? '#D4A84B' : '#8B7355'; // Golden for local, brown for remote
  const roofColor = '#5D4E37';

  let hovered = $state(false);
</script>

<!-- Hive structure -->
<T.Group
  position.x={position[0]}
  position.y={position[1]}
  position.z={position[2]}
>
  <!-- Base/body of hive (stack of cylinders for traditional beehive look) -->
  {#each [0, 0.4, 0.8, 1.2] as y, i}
    {@const radius = 0.8 - i * 0.08}
    <T.Mesh
      position.y={y + 0.2}
      castShadow
      receiveShadow
      on:click={() => onClick?.()}
      on:pointerenter={() => hovered = true}
      on:pointerleave={() => hovered = false}
    >
      <T.CylinderGeometry args={[radius, radius + 0.05, 0.4, 16]} />
      <T.MeshStandardMaterial
        color={hovered ? '#E8C068' : hiveColor}
        roughness={0.7}
        metalness={0.1}
      />
    </T.Mesh>
  {/each}

  <!-- Roof (cone) -->
  <T.Mesh position.y={1.9} castShadow>
    <T.ConeGeometry args={[0.6, 0.5, 16]} />
    <T.MeshStandardMaterial
      color={roofColor}
      roughness={0.8}
    />
  </T.Mesh>

  <!-- Entrance hole -->
  <T.Mesh position={[0, 0.3, 0.75]} rotation.x={Math.PI / 2}>
    <T.CircleGeometry args={[0.15, 16]} />
    <T.MeshBasicMaterial color="#1a1a1a" />
  </T.Mesh>

  <!-- Landing board -->
  <T.Mesh position={[0, 0.15, 0.9]}>
    <T.BoxGeometry args={[0.3, 0.05, 0.3]} />
    <T.MeshStandardMaterial color={roofColor} />
  </T.Mesh>

  <!-- Name label -->
  <Text
    text={name}
    position={[0, 2.5, 0]}
    fontSize={0.3}
    color={isLocal ? '#D4A84B' : '#666'}
    anchorX="center"
    anchorY="bottom"
  />

  <!-- Glow effect for local hive -->
  {#if isLocal}
    <T.PointLight
      position={[0, 1, 0]}
      color="#FFD700"
      intensity={0.5}
      distance={5}
    />
  {/if}
</T.Group>
