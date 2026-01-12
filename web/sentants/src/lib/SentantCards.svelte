<!------------------------------------------------------------------------------------------------------
  Sentant Cards - Displays sentants grouped by their origin node

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    // @ts-ignore - svelte-fomantic-ui@0.3.9 doesn't provide TypeScript type definitions
    import { Cards, Header, Segment, Icon, Divider } from "svelte-fomantic-ui";
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

    // Group sentants by nodeName
    $: groupedSentants = groupByNode(sentantData);

    interface NodeGroup {
        nodeName: string;
        sentants: Sentant[];
    }

    function groupByNode(sentants: Sentant[]): NodeGroup[] {
        const groupMap: Record<string, Sentant[]> = {};

        // Filter out reserved sentants and group by node
        const filtered = sentants.filter(s =>
            s.name !== RESERVED_SENTANT_NAMES.MONITOR &&
            s.name !== RESERVED_SENTANT_NAMES.DELETED &&
            s.name !== RESERVED_SENTANT_NAMES.VIEW
        );

        for (const sentant of filtered) {
            const nodeName = sentant.nodeName || "Local";
            if (!groupMap[nodeName]) {
                groupMap[nodeName] = [];
            }
            groupMap[nodeName].push(sentant);
        }

        // Convert to array of groups
        return Object.keys(groupMap).map(nodeName => ({
            nodeName,
            sentants: groupMap[nodeName]
        }));
    }

    // Check if this group contains local sentants by comparing nodeId
    function isLocalGroup(group: NodeGroup): boolean {
        if (!localNodeId) return true; // Default to local if we don't know yet
        return group.sentants.some(s => s.nodeId === localNodeId);
    }

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

<div style="width: 100%; height: {height}; overflow-y:scroll; margin-top: 10px;">
    {#each groupedSentants as group, i}
        {#if i > 0}
            <Divider ui horizontal>
                <Icon server />
            </Divider>
        {/if}
        <Header ui small grey attached top style="margin: 10px 14px 0 14px;">
            {#if isLocalGroup(group)}
                <Icon home />
                {group.nodeName}
                <span style="color: #888; font-size: 0.8em;">(this device)</span>
            {:else}
                <Icon server />
                {group.nodeName}
                <span style="color: #999; font-size: 0.8em;">(snapshot - not live)</span>
            {/if}
        </Header>
        <Cards ui centered attached style="margin: 0 14px 10px 14px; padding-top: 10px; {isLocalGroup(group) ? '' : 'opacity: 0.7;'}">
            {#each group.sentants as sentant}
                <SentantCard {sentant} {r2_node} {variables} isLocal={isLocalGroup(group)} />
            {/each}
        </Cards>
    {/each}

    {#if groupedSentants.length === 0}
        <Header ui centered grey style="margin-top: 50px;">
            <Icon inbox />
            No Sentants
        </Header>
    {/if}
</div>
