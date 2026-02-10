<script lang="ts">
  import { T } from '@threlte/core';
  import { MeshStandardMaterial, CircleGeometry, DoubleSide } from 'three';
</script>

<!-- Meadow ground - a soft green circle -->
<T.Mesh
  rotation.x={-Math.PI / 2}
  position.y={0}
  receiveShadow
>
  <T.CircleGeometry args={[20, 64]} />
  <T.MeshStandardMaterial
    color="#4a7c4e"
    roughness={0.9}
    metalness={0.0}
  />
</T.Mesh>

<!-- Subtle grid for orientation -->
<T.GridHelper
  args={[40, 20, '#3d6b40', '#3d6b40']}
  position.y={0.01}
/>

<!-- Outer ring to fade to sky -->
<T.Mesh
  rotation.x={-Math.PI / 2}
  position.y={-0.01}
>
  <T.RingGeometry args={[20, 30, 64]} />
  <T.MeshBasicMaterial
    color="#81C784"
    transparent
    opacity={0.3}
  />
</T.Mesh>
