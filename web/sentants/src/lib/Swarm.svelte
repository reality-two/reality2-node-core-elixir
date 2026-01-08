<!------------------------------------------------------------------------------------------------------
  Swarm Visualization

  TODO: Complete swarm management implementation
  - Connect nodes to actual sentants
  - Display sentant relationships
  - Add ability to create/edit swarm configurations
  - Integrate with Reality2 swarm API
  - Add real-time updates when swarm topology changes
  - Implement node interactions (drag, click, edit)

  Status: Work In Progress
  Framework: SvelteFlow (@xyflow/svelte)
------------------------------------------------------------------------------------------------------->
<script>
    import { SvelteFlow } from "@xyflow/svelte";
    import "@xyflow/svelte/dist/style.css";

    // TODO: Replace placeholder data with actual swarm data from Reality2
    let nodes = $state.raw([
        { id: "1", position: { x: 0, y: 0 }, data: { label: "Sentant 1" } },
        { id: "2", position: { x: 0, y: 100 }, data: { label: "Sentant 2" } },
    ]);

    let edges = $state.raw([{ id: "e1-2", source: "1", target: "2" }]);

    // TODO: Add props for r2_node, sentantData, etc.
    // TODO: Load actual swarm topology
    // TODO: Handle node/edge interactions
</script>

<div style:width="100vw" style:height="100vh">
    <SvelteFlow bind:nodes bind:edges />
</div>
