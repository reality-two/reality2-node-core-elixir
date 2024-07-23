<!------------------------------------------------------------------------------------------------------
  A Sensor Card

  Author: Dr. Roy C. Davies
  Created: July 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { onMount } from 'svelte';
    import { Card, Content, Header, Button, Text, Icon, Message, Label, Buttons } from "svelte-fomantic-ui";

    import type { Sentant } from './reality2.js';
    import R2 from "./reality2";

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};
    export let r2_node: R2;

    type input_text_type = {[key:string]: any}
    type params_type = {[key:string]: string}

    let set_colour = 0;
    let set_sensor = 0;
    let sensor_in = 0;
    let input_text: input_text_type = {};
    let lastExecutionTime = 0;
    let connected = false;
    let colour_chosen = false;

    $: colour = set_colour;
    $: sensor = set_sensor;

    // Set up the device sensor reading
    const handleOrientation = (event:any) => {
        const absolute = event.absolute;
        const alpha = event.alpha;
        const beta = event.beta;
        const gamma = event.gamma;
        let new_sensor_in = Math.floor(event.alpha);
        const now = Date.now();
        if ((new_sensor_in !== sensor_in) && (now - lastExecutionTime >= 200))
        {
            sensor_in = new_sensor_in;
            r2_node.sentantSend(sentant.id, "set_sensor", {sensor: sensor_in});
            r2_node.sentantSend(sentant.id, "update", {});
            lastExecutionTime = now;
        }
    };
    window.addEventListener("deviceorientation", handleOrientation, true);

    // Convert a string safely into another format
    function try_convert(value: string): any {
        if ((value === "") || (value === null)) { return ""; }

        const numberValue = parseFloat(value);
        if (!isNaN(numberValue)) { return numberValue; }

        switch (value.toLowerCase()) {
            case 'true': return true;
            case 'false': return false;
        }

        try { return JSON.parse(value); } catch (e) { return value; }
    }

    // What to do when a button is pressed
    function event_button_pressed (id: string, event: string) {
        let params: params_type = {};
        for (let i = 0; i < sentant.events.length; i++)
        {
            if (sentant.events[i].event == event)
            {
                for (let key in sentant.events[i].parameters)
                {
                    params[key] = try_convert(input_text[event+key]);
                }
            }
        }
        r2_node.sentantSend(sentant.id, event, params);
        r2_node.sentantSend(id, "update", {});
    };

    function colour_button_pressed (id: string, colour: number) {
        set_colour = colour;
        r2_node.sentantSend(id, "set_colour", {colour: colour});
        r2_node.sentantSend(id, "update", {});
        colour_chosen = true;
    };

    function convert_colour(colour: number): string {
        if (colour < 60) { return "red"; }
        if (colour < 130) { return "yellow"; }
        if (colour < 230) { return "green"; }
        if (colour < 280) { return "blue"; }
        return "purple";
    }

    // When the page is loaded ...
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
        {#if colour_chosen}
            <Content>
                <Text ui large  grey>
                    Rotate to match
                </Text>
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
        {:else}
            <Content>
                <Text ui large  grey>
                    Choose a colour
                </Text>
                <Buttons ui>
                    <Button ui red on:click={(_e) => colour_button_pressed(sentant.id, 0)}>
                        &nbsp;
                    </Button>
                    <Button ui yellow on:click={(_e) => colour_button_pressed(sentant.id, 60)}>
                        &nbsp;
                    </Button>
                    <Button ui green on:click={(_e) => colour_button_pressed(sentant.id, 130)}>
                        &nbsp;
                    </Button>
                    <Button ui blue on:click={(_e) => colour_button_pressed(sentant.id, 230)}>
                        &nbsp;
                    </Button>
                    <Button ui purple on:click={(_e) => colour_button_pressed(sentant.id, 280)}>
                        &nbsp;
                    </Button>
                </Buttons>
            </Content>
        {/if}
        <Content extra>
            <p><Label ui huge basic _={connected ? "blue" : "grey"} fluid>{sentant.name}</Label></p>
            <p><Text ui small blue>{sentant.id}</Text></p>
        </Content>
    </Card>
{:else}
    <Message ui teal large>
        <Header>
            Device connection invalid
        </Header>
    </Message>
{/if}