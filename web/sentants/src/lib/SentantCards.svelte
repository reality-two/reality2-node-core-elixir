<!------------------------------------------------------------------------------------------------------
  A Map

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    //@ts-ignore
    import { Cards } from "svelte-fomantic-ui";
    import SentantCard from './SentantCard.svelte';

    import { onMount } from 'svelte';
    import { onDestroy } from 'svelte';

    import R2 from "./reality2";

    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};

    let height = "400px";

    onMount(() => {
        updateHeight();

        // Add resize event listener
        window.addEventListener('resize', updateHeight);
    });

    onDestroy(() => { 
        window.removeEventListener('resize', updateHeight); 
    });

    function updateHeight() {
        height = `${window.innerHeight - 80}px`;
    }
</script>

<Cards ui centered style="width: 100%; height: {height}; overflow-y:scroll;">
    {#each sentantData as sentant}
        {#if ((sentant.name !== "monitor") && (sentant.name !== ".deleted") && (sentant.name !== "view"))}
            <SentantCard {sentant} {r2_node} {variables}/>
        {/if}
    {/each}
</Cards>