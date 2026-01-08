<!------------------------------------------------------------------------------------------------------
  A Map

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    // @ts-ignore - svelte-fomantic-ui@0.3.9 doesn't provide TypeScript type definitions
    import { Cards } from "svelte-fomantic-ui";
    import SentantCard from "./SentantCard.svelte";

    import { onMount } from "svelte";
    import { onDestroy } from "svelte";

    import type { Sentant } from "./types";
    import { CARDS_HEADER_HEIGHT_PX, RESERVED_SENTANT_NAMES } from "./constants";
    import R2 from "./reality2";

    export let r2_node: R2;
    export let sentantData: Sentant[] = [];
    export let variables: Record<string, unknown> = {};

    let height = "400px";

    onMount(() => {
        updateHeight();

        // Add resize event listener
        window.addEventListener("resize", updateHeight);
    });

    onDestroy(() => {
        window.removeEventListener("resize", updateHeight);
    });

    function updateHeight() {
        height = `${window.innerHeight - CARDS_HEADER_HEIGHT_PX}px`;
    }
</script>

<Cards
    ui
    centered
    style="width: 100%; height: {height}; overflow-y:scroll; margin-top: 10px;"
>
    {#each sentantData as sentant}
        {#if sentant.name !== RESERVED_SENTANT_NAMES.MONITOR && sentant.name !== RESERVED_SENTANT_NAMES.DELETED && sentant.name !== RESERVED_SENTANT_NAMES.VIEW}
            <SentantCard {sentant} {r2_node} {variables} />
        {/if}
    {/each}
</Cards>
