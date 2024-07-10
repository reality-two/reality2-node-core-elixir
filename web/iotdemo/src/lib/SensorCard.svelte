<!------------------------------------------------------------------------------------------------------
  A Sensor Card

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { createEventDispatcher, onMount } from 'svelte';
    import {Card, Content, Header, Image, Button, Text, Input, Link} from "svelte-fomantic-ui";

    import type { Sentant, Event } from './reality2.js';
    import { readable } from 'svelte/store';
    import QRCode from '@castlenine/svelte-qrcode';

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};

    const dispatch = createEventDispatcher();

    type input_text_type = {[key:string]: any}
    type params_type = {[key:string]: string}

    let messages = ["|", "|", "|", "|"];
    let counter = 0;
    let sensor_out = 0;
    let sensor_in = 0;
    let input_text: input_text_type = {};
    let max_messages = Object.keys(sentant.events).length > 0 ? 4 : 8;
    let lastExecutionTime = 0;

    let height = 0;

    const handleOrientation = (event:any) => {
        const absolute = event.absolute;
        const alpha = event.alpha;
        const beta = event.beta;
        const gamma = event.gamma;
        let new_sensor_in = Math.floor(event.alpha);
        const now = Date.now();
        if ((new_sensor_in !== sensor_in) && (now - lastExecutionTime >= 500))
        {
            dispatch('sentantSend', {id: sentant.id, event: "setsensor", params: {sensor: sensor_in}});
            sensor_in = new_sensor_in;
            lastExecutionTime = now;
        }
        //...
    };

    window.addEventListener("deviceorientation", handleOrientation, true);

    function try_convert(value: string): any {
        if ((value === "") || (value === null)) {
            return ""; // Return empty string as is
        }

        const numberValue = parseFloat(value);
        if (!isNaN(numberValue)) {
            return numberValue;
        }

        switch (value.toLowerCase()) {
            case 'true':
                return true;
            case 'false':
                return false;
        }

        try {
            return JSON.parse(value);
        } catch (e) {
            return value;
        }
    }

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
        dispatch('sentantSend', {id: id, event: event, params: params});
    };

    onMount(() => {
        if (sentant.name == "monitor") return;
        // for (let i = 0; i < sentant.signals.length; i++)
        // {
        //     dispatch('awaitSignal', {id: sentant.id, signal: sentant.signals[i], callback: (data: any) => {
        //         let date = new Date();
        //         messages = [...messages, date.toLocaleString('en-NZ') + " : " + data.event + "|" + JSON.stringify(data.parameters)];
        //         if (messages.length > max_messages) {
        //             messages.splice(0, messages.length - max_messages);
        //         }
        //     }});
        // }
        dispatch('awaitSignal', {id: sentant.id, signal: "update", callback: (data: any) => {
            counter = Math.floor(data.parameters.counter);
        }});
        dispatch('awaitSignal', {id: sentant.id, signal: "count_update", callback: (data: any) => {
            counter = Math.floor(data.parameters.counter);
        }});
        dispatch('awaitSignal', {id: sentant.id, signal: "sensor_update", callback: (data: any) => {
            sensor_out = Math.floor(data.parameters.sensor);
        }});
        // setTimeout(function() {
        //     dispatch('sentantSend', {id: sentant.id, event: "update", params: {}});
        //     console.log('Waited for 1 second');
        //     // Place code to execute after waiting here
        // }, 1000);
    });
</script>
<!----------------------------------------------------------------------------------------------------->

{#if sentant.name != "monitor"}
    <Card>
        <Content>
            {#if counter >= 20 && sensor_out == 90}
                <Image ui large src="/images/smiley.png"/>
            {:else}
                <Text ui massive _='{counter >= 20?"green":"red"}'>{counter}</Text><br/>
                <Text ui massive _='{sensor_out == 90?"green":"blue"}'>{sensor_out}</Text>
            {/if}
        </Content>

        <!-- </Link> -->
        <Content extra>
            <p>{sentant.name}</p>
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
{/if}