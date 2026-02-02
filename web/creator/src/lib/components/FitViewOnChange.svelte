<script lang="ts">
  import { useSvelteFlow } from "@xyflow/svelte";

  let { nodeCount = 0 }: { nodeCount?: number } = $props();

  const { fitView } = useSvelteFlow();

  let prevCount = $state(nodeCount);

  $effect(() => {
    if (nodeCount !== prevCount) {
      prevCount = nodeCount;
      // Small delay so SvelteFlow has processed the new nodes
      setTimeout(() => fitView({ padding: 0.15, duration: 300 }), 50);
    }
  });
</script>
