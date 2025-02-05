<!------------------------------------------------------------------------------------------------------
  A Sentant Card

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { onMount } from 'svelte';
    //@ts-ignore
    import {Card, Content, Header, Image, Button, Text, Input, Link, Icon} from "svelte-fomantic-ui";

    import type { Sentant } from './reality2.js';
    import R2 from "./reality2";

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};
    export let r2_node: R2;
    export let mini:boolean = false;
    export let height: string = "1000px";
    export let variables = {};

    type input_text_type = {[key:string]: any}
    type params_type = {[key:string]: string}

    let messages = ["|", "|", "|", "|", "|", "|", "|", "|"];
    let input_text: input_text_type = {};
    let max_messages = 8; //Object.keys(sentant.events).length > 0 ? 4 : 8;

    async function copyCode(data: string) {
        try {
        await navigator.clipboard.writeText(data);
            console.log("Copied!");
        } catch (err) {
            console.error("Failed to copy:", err);
        }
    }

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
        r2_node.sentantSend(id, event, params);
    };

    function unload_sentant() {
        r2_node.sentantUnload(sentant.id)
    }

    onMount(() => {
        if (sentant.name == "monitor") return;
        for (let i = 0; i < sentant.signals.length; i++)
        {
            r2_node.awaitSignal(sentant.id, sentant.signals[i], (data: any) => {
                if (data.hasOwnProperty("event"))
                {
                    let date = new Date();
                    messages = [...messages, date.toLocaleString('en-NZ') + " : " + data.event + "|" + JSON.stringify(data.parameters)];
                    if (messages.length > max_messages) {
                        messages.splice(0, messages.length - max_messages);
                    }
                }

            });
        }
    });
</script>
<!----------------------------------------------------------------------------------------------------->

{#if sentant.name != "monitor"}
    <Card style="height: {height};">
        <Link ui image href={"/?name=" + sentant.name + "&variables=" + encodeURIComponent(JSON.stringify(variables))}>
            <Image ui large src="/images/bee_blue.png" />
        </Link>
        <Content style={mini?"text-align: center;":"height:150px; text-align: center;"}>
            <Header>{sentant.name}</Header>
            <p><Text ui small blue>{sentant.id}</Text></p>
            <p>{sentant.description}</p>
        </Content>
        <Content extra style={mini?"text-align: center;":"height:200px; text-align: center;"}>
            {#each messages as message, i}
                {#if message.split('|')[0] != ""}
                    <Text ui popup small data-variation="multiline very wide" _={(i == messages.length-1 ? "teal" : "grey")} data-tooltip={JSON.stringify(try_convert(message.split('|')[1]), null, 4)}>{message.split('|')[0]}</Text>
                    <Button ui icon small basic popup style="box-shadow: 0 0 0 0;" data-tooltip={"copy to clipboard"} on:click={() => copyCode(JSON.stringify(try_convert(message.split('|')[1]), null, 4))}><Icon ui clipboard/></Button>
                    <br/>
                {/if}
            {/each}
        </Content>
        {#if !mini}
            {#if sentant.events.length > 0}
                <Content extra style="overflow-y:scroll; overflow-x: hidden; height:250px; text-align: center;">
                    {#each sentant.events as event}
                        {#each Object.keys(event.parameters) as key}
                            <Input ui labeled fluid style={"margin-bottom:5px;"}>    
                                <Input text large placeholder={key} bind:value={input_text[event.event+key]}/>
                            </Input>
                        {/each}
                        <Button ui teal fluid on:click={() => event_button_pressed(sentant.id, event.event)} style={"margin-bottom:20px;"}>
                            {event.event}
                        </Button>
                    {/each}
                </Content>
            {/if}
            <Content extra>
                <Button ui orange fluid basic on:click={unload_sentant}>
                    Unload
                </Button>
            </Content>
        {/if}
    </Card>
{/if}