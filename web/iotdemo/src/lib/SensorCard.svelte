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

    let set_sensor = 0;
    let sensor_in = 0;
    let input_text: input_text_type = {};
    let lastExecutionTime = 0;
    let connected = false;
    let sensor_active = true;

    $: sensor = set_sensor;

    // Set up the device sensor reading
    const handleOrientation = (event:any) => {
        if (sensor_active) {
            let new_sensor_in = Math.floor(event.alpha);
            const now = Date.now();
            if ((new_sensor_in !== sensor_in) && (now - lastExecutionTime >= 200))
            {
                sensor_in = new_sensor_in;
                r2_node.sentantSend(sentant.id, "set_sensor", {sensor: sensor_in});
                r2_node.sentantSend(sentant.id, "update", {});
                lastExecutionTime = now;
            }
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
        set_sensor = colour;
        r2_node.sentantSend(id, "set_sensor", {sensor: colour});
        r2_node.sentantSend(id, "update", {});
    };

    function convert_colour(colour: number): string {
        if (colour < 72) { return "red"; }
        if (colour < 144) { return "yellow"; }
        if (colour < 216) { return "green"; }
        if (colour < 288) { return "blue"; }
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
                <Button ui _={convert_colour(sensor)} massive>
                    {#if sensor_active}
                        <Text ui large>{sensor}</Text>
                    {:else}
                        <Text ui large _={convert_colour(sensor)}>&nbsp;</Text>
                    {/if}
                </Button>             
            </Buttons>
        </Content>
        <Content>
            {#if sensor_active}
                <Button ui grey large fluid on:click={(_e) => { sensor_active = false; }}>Press if no sensor</Button>
            {:else}
                <Button ui grey large fluid on:click={(_e) => { sensor_active = true; }}>Press to use sensor</Button>
            {/if}
        </Content>
            <Content>
                {#if sensor_active}
                    <Text ui large  grey>
                        Rotate for colour
                    </Text>
                {:else}
                    <Text ui large  grey>
                        Choose a colour
                    </Text>
                    <Buttons ui fluid>
                        <Button ui red on:click={(_e) => colour_button_pressed(sentant.id, 10)}>
                            <Text ui large>&nbsp;</Text>
                        </Button>
                        <Button ui yellow on:click={(_e) => colour_button_pressed(sentant.id, 80)}>
                            <Text ui large>&nbsp;</Text>
                        </Button>
                        <Button ui green on:click={(_e) => colour_button_pressed(sentant.id, 150)}>
                            <Text ui large>&nbsp;</Text>
                        </Button>
                        <Button ui blue on:click={(_e) => colour_button_pressed(sentant.id, 230)}>
                            <Text ui large>&nbsp;</Text>
                        </Button>
                        <Button ui purple on:click={(_e) => colour_button_pressed(sentant.id, 290)}>
                            <Text ui large>&nbsp;</Text>
                        </Button>
                    </Buttons>
                {/if}
            </Content>
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