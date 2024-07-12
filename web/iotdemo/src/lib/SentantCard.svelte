<!------------------------------------------------------------------------------------------------------
  A Sentant Card

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { onMount } from 'svelte';
    import { Card, Content, Image, Text } from "svelte-fomantic-ui";

    import type { Sentant } from './reality2.js';
    import R2 from "./reality2";

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};
    export let r2_node: R2;

    let set_counter = 0;
    let set_sensor = 0;

    $: counter = set_counter;
    $: sensor = set_sensor;

    onMount(() => {
        if ((sentant.name == "monitor" || sentant.name == ".deleted")) return;

        r2_node.awaitSignal(sentant.id, "update", (data: any) => {
            if(R2.JSONPath(data, "status") == "connected")
            {
                r2_node.sentantSend(sentant.id, "update", {});
            }
            else
            {
                set_counter = Math.floor(data.parameters.counter);
                set_sensor = Math.floor(data.parameters.sensor);
            }
        });
    });
</script>
<!----------------------------------------------------------------------------------------------------->

{#if ((sentant.name !== "monitor") && (sentant.name !== ".deleted"))}
    <Card>
        <Content>
            {#if counter >= 20 && sensor == 90}
                <Image ui large src="/images/smiley.png"/>
            {:else}
                <Text ui massive _='{counter >= 20?"green":"red"}'>{counter}<br/></Text><br/>
                <Text ui massive _='{sensor == 90?"green":"blue"}'>{sensor}</Text>
            {/if}
        </Content>
        <Content extra>
            <p><Text ui large green>{sentant.name}</Text></p>
            <p><Text ui small blue>{sentant.id}</Text></p>
        </Content>
    </Card>
{/if}