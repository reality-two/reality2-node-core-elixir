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

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};

    const dispatch = createEventDispatcher();

    type input_text_type = {[key:string]: any}
    type params_type = {[key:string]: string}

    let messages = ["|", "|", "|", "|"];
    let input_text: input_text_type = {};
    let max_messages = Object.keys(sentant.events).length > 0 ? 4 : 8;

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
        for (let i = 0; i < sentant.signals.length; i++)
        {
            dispatch('awaitSignal', {id: sentant.id, signal: sentant.signals[i], callback: (data: any) => {
                let date = new Date();
                messages = [...messages, date.toLocaleString('en-NZ') + " : " + data.event + "|" + JSON.stringify(data.parameters)];
                if (messages.length > max_messages) {
                    messages.splice(0, messages.length - max_messages);
                }
            }});
        }
    });
</script>
<!----------------------------------------------------------------------------------------------------->

{#if sentant.name != "monitor"}
    <Card>
        <Link ui image href={"/?name=" + sentant.name}>
            <Image ui large src="/images/sentant.png"/>
        </Link>
        <Content>
            <Header>{sentant.name}</Header>
            <p><Text ui small blue>{sentant.id}</Text></p>
            <p>{sentant.description}</p>
        </Content>
        <Content extra>
            {#each messages as message, i}
                <Text tooltip ui small _={(i == messages.length-1 ? "teal" : "grey")} popup data-tooltip={message.split('|')[1]}>{message.split('|')[0]}</Text><br/>
            {/each}
        </Content>
        {#if sentant.events.length > 0}
            <Content extra>
                {#each sentant.events as event}
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