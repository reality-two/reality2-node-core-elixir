<!------------------------------------------------------------------------------------------------------
  A Sentant Card

  Author: Dr. Roy C. Davies
  Created: July 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { onMount } from 'svelte';
    import { Card, Content, Buttons, Button, Icon, Text, Label } from "svelte-fomantic-ui";

    import type { Sentant } from './reality2.js';
    import R2 from "./reality2";

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};
    export let r2_node: R2;

    let set_sensor = 0;
    let connected = false;

    $: sensor = set_sensor;

    onMount(() => {
        if (sentant.name == "monitor" || sentant.name == ".deleted" || sentant.name == "view") return;

        r2_node.awaitSignal(sentant.id, "update", (data: any) => {
            if(R2.JSONPath(data, "status") == "connected")
            {
                r2_node.sentantSend(sentant.id, "update", {});
                connected = true;
            }
            else
            {
                set_sensor = Math.floor(data.parameters.sensor);
            }
        });
    });

    // Convert rotation number to a colour
    function convert_colour(colour: number): string {
        if (colour < 72) { return "red"; }
        if (colour < 144) { return "yellow"; }
        if (colour < 216) { return "green"; }
        if (colour < 288) { return "blue"; }
        return "purple";
    }
</script>
<!----------------------------------------------------------------------------------------------------->

{#if ((sentant.name !== "monitor") && (sentant.name !== ".deleted") && (sentant.name !== "view"))}
    <Card>
        <Content>
            <Buttons ui vertical fluid>
                <Button ui _={convert_colour(sensor)} massive>
                    {sensor}
                </Button>              
            </Buttons>
        </Content>
        <Content extra>
            <p><Label ui huge basic _={connected ? "blue" : "grey"} fluid>{sentant.name}</Label></p>
            <p><Text ui small blue>{sentant.id}</Text></p>
        </Content>
    </Card>
{/if}