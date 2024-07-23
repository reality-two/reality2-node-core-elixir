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

    let set_colour = 0;
    let set_sensor = 0;
    let connected = false;

    $: colour = set_colour;
    $: sensor = set_sensor;

    function convert_colour(colour: number): string {
        if (colour < 60) { return "red"; }
        if (colour < 130) { return "yellow"; }
        if (colour < 230) { return "green"; }
        if (colour < 280) { return "blue"; }
        return "purple";
    }

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
                set_colour = Math.floor(data.parameters.colour);
                set_sensor = Math.floor(data.parameters.sensor);
            }
        });
    });
</script>
<!----------------------------------------------------------------------------------------------------->

{#if ((sentant.name !== "monitor") && (sentant.name !== ".deleted") && (sentant.name !== "view"))}
    <Card>
        <Content>
            <Buttons ui vertical fluid>
                <Button ui _={convert_colour(colour)} massive>
                    {#if convert_colour(colour) == convert_colour(sensor)}
                        <Icon ui thumbs up></Icon>
                    {:else}
                        &nbsp;
                    {/if}
                </Button>
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