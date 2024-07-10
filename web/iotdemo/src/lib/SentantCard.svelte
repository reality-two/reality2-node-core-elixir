<!------------------------------------------------------------------------------------------------------
  A Sentant Card

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

    let counter = 0;
    let sensor_out = 0;
    let input_text: input_text_type = {};

    let height = 0;

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
        setTimeout(function() {
            dispatch('sentantSend', {id: sentant.id, event: "update", params: {}});
        }, 1000);
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
        <Content extra>
            <p>{sentant.name}</p>
            <p><Text ui small blue>{sentant.id}</Text></p>
            <Link ui href={"/iotdemo?id=" + sentant.id}>
                <QRCode data={"https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?id=" + sentant.id} shape="circle" isResponsive/>
            </Link>
        </Content>
    </Card>
{/if}