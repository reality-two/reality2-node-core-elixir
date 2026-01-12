<!------------------------------------------------------------------------------------------------------
  Sentant Cards - Displays sentants for the selected node

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    // @ts-ignore - svelte-fomantic-ui@0.3.9 doesn't provide TypeScript type definitions
    import { Cards, Header, Icon } from "svelte-fomantic-ui";
    import SentantCard from "./SentantCard.svelte";

    import { onMount } from "svelte";
    import { onDestroy } from "svelte";

    import type { Sentant } from "./types";
    import { CARDS_HEADER_HEIGHT_PX, RESERVED_SENTANT_NAMES } from "./constants";
    import R2 from "./reality2";

    export let r2_node: R2;
    export let sentantData: Sentant[] = [];
    export let variables: Record<string, unknown> = {};
    export let localNodeId: string = "";

    let height = "400px";

    // Filter out reserved sentants
    $: filteredSentants = sentantData.filter(s =>
        s.name !== RESERVED_SENTANT_NAMES.MONITOR &&
        s.name !== RESERVED_SENTANT_NAMES.DELETED &&
        s.name !== RESERVED_SENTANT_NAMES.VIEW
    );

    // Check if these sentants are from the local node
    $: isLocal = !localNodeId || filteredSentants.some(s => s.nodeId === localNodeId);

    onMount(() => {
        updateHeight();
        window.addEventListener("resize", updateHeight);
    });

    onDestroy(() => {
        window.removeEventListener("resize", updateHeight);
    });

    function updateHeight() {
        height = `${window.innerHeight - CARDS_HEADER_HEIGHT_PX}px`;
    }
</script>

<div style="width: 100%; height: {height}; overflow-y:scroll; margin-top: 10px;">
    {#if filteredSentants.length > 0}
        <Cards ui centered style="margin: 0 14px 10px 14px; padding-top: 10px; {isLocal ? '' : 'opacity: 0.7;'}">
            {#each filteredSentants as sentant}
                <SentantCard {sentant} {r2_node} {variables} {isLocal} />
            {/each}
        </Cards>
    {:else}
        <Header ui centered grey style="margin-top: 50px;">
            <Icon inbox />
            No Sentants
        </Header>
    {/if}
</div>
