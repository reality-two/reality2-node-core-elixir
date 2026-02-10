<script lang="ts">
  import { T, useTask } from '@threlte/core';
  import { Text } from '@threlte/extras';

  interface Props {
    position?: [number, number, number];
    name?: string;
    swarm?: string;
    isActive?: boolean;
    onClick?: () => void;
  }

  let {
    position = [0, 0, 0],
    name = 'Bee',
    swarm,
    isActive = false,
    onClick
  }: Props = $props();

  // Swarm colors - bees in same swarm share color
  const swarmColors: Record<string, string> = {
    default: '#F5C842',
    sensors: '#4FC3F7',
    actuators: '#FF8A65',
    processors: '#AED581',
  };

  const bodyColor = swarm ? (swarmColors[swarm] ?? swarmColors.default) : swarmColors.default;

  let hovered = $state(false);
  let wingAngle = $state(0);
  let bobOffset = $state(0);

  // Accumulated animation time (delta-based, not Date.now())
  let animTime = 0;

  // Wing animation using accumulated delta time
  useTask((delta) => {
    try {
      animTime += delta;
      wingAngle = Math.sin(animTime * 3) * 0.5;    // ~3 rad/s wing frequency
      bobOffset = Math.sin(animTime * 0.2) * 0.1;  // ~0.2 rad/s bob frequency
    } catch (err) {
      console.error('Bee animation error:', err);
    }
  });
</script>

<T.Group
  position.x={position[0]}
  position.y={position[1] + bobOffset}
  position.z={position[2]}
  scale={hovered ? 1.2 : 1}
>
  <!-- Body (ellipsoid) -->
  <T.Mesh
    castShadow
    on:click={() => onClick?.()}
    on:pointerenter={() => hovered = true}
    on:pointerleave={() => hovered = false}
  >
    <T.SphereGeometry args={[0.25, 16, 12]} />
    <T.MeshStandardMaterial
      color={bodyColor}
      roughness={0.4}
      metalness={0.2}
      emissive={isActive ? bodyColor : '#000000'}
      emissiveIntensity={isActive ? 0.3 : 0}
    />
  </T.Mesh>

  <!-- Stripes -->
  {#each [-0.08, 0.08] as z}
    <T.Mesh position.z={z}>
      <T.TorusGeometry args={[0.25, 0.03, 8, 16]} />
      <T.MeshStandardMaterial color="#1a1a1a" />
    </T.Mesh>
  {/each}

  <!-- Head -->
  <T.Mesh position={[0.28, 0.05, 0]} castShadow>
    <T.SphereGeometry args={[0.12, 12, 8]} />
    <T.MeshStandardMaterial color="#1a1a1a" />
  </T.Mesh>

  <!-- Eyes -->
  {#each [-0.06, 0.06] as z}
    <T.Mesh position={[0.35, 0.08, z]}>
      <T.SphereGeometry args={[0.04, 8, 8]} />
      <T.MeshStandardMaterial
        color="#ffffff"
        emissive="#ffffff"
        emissiveIntensity={0.3}
      />
    </T.Mesh>
  {/each}

  <!-- Wings (animated) -->
  {#each [-1, 1] as side}
    <T.Mesh
      position={[0, 0.15, side * 0.15]}
      rotation.x={side * wingAngle}
      rotation.z={0.3}
    >
      <T.PlaneGeometry args={[0.3, 0.15]} />
      <T.MeshStandardMaterial
        color="#E8F4F8"
        transparent
        opacity={0.6}
        side={2}
      />
    </T.Mesh>
  {/each}

  <!-- Stinger -->
  <T.Mesh position={[-0.35, 0, 0]} rotation.z={Math.PI / 2}>
    <T.ConeGeometry args={[0.04, 0.15, 8]} />
    <T.MeshStandardMaterial color="#1a1a1a" />
  </T.Mesh>

  <!-- Name label (appears on hover) -->
  {#if hovered}
    <Text
      text={name}
      position={[0, 0.5, 0]}
      fontSize={0.15}
      color="#333"
      anchorX="center"
      anchorY="bottom"
      outlineWidth={0.02}
      outlineColor="#ffffff"
    />
  {/if}

  <!-- Activity indicator -->
  {#if isActive}
    <T.PointLight
      color={bodyColor}
      intensity={0.3}
      distance={2}
    />
  {/if}
</T.Group>
