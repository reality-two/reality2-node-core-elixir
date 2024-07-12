<!------------------------------------------------------------------------------------------------------
  A Sensor Card

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { onMount } from 'svelte';
    import { Card, Content, Header, Image, Button, Text, Input, Message, Icon } from "svelte-fomantic-ui";

    import type { Sentant } from './reality2.js';
    import R2 from "./reality2";

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};
    export let r2_node: R2;

    type input_text_type = {[key:string]: any}
    type params_type = {[key:string]: string}

    let set_counter = 0;
    let set_sensor = 0;
    let sensor_in = 0;
    let input_text: input_text_type = {};
    let lastExecutionTime = 0;

    $: counter = set_counter;
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
            r2_node.sentantSend(sentant.id, "setsensor", {sensor: sensor_in});
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

    // When the page is loaded ...
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
                <Image ui src="/images/smiley.png"/>
            {:else}
                <Text ui massive _='{counter >= 20?"green":"red"}'>{counter}<br/></Text>
                <Text ui massive _='{sensor == 90?"green":"blue"}'>{sensor}</Text>
            {/if}
        </Content>

        <Content extra>
            <p><Text ui big green>{sentant.name}</Text></p>
            <p><Text ui small blue>{sentant.id}</Text></p>
        </Content>
        {#if sentant.events.length > 0}
            <Content extra>
                {#each [{event: "count", parameters: {}}] as event}
                    {#each Object.keys(event.parameters) as key}
                        <Input ui labeled fluid>
                            <Input text large placeholder={key} bind:value={input_text[event.event+key]}/>
                        </Input>
                        <br/>
                    {/each}
                    <Button ui teal fluid on:click={(_e) => event_button_pressed(sentant.id, event.event)}>
                        {event.event}
                    </Button>
                    <br/>
                {/each}
            </Content>
        {/if}
    </Card>
{:else}
    <Message ui teal large>
        <Header>
            <Icon warning/>
            Device connection invalid
        </Header>
    </Message>
{/if}