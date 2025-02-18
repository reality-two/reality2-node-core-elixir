<!------------------------------------------------------------------------------------------------------
  A Sentant Card

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Updated: Feb 2025
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { onMount, tick } from 'svelte';
    //@ts-ignore
    import {Card, Div, Header, Image, Button, Text, Input, Link, Icon, Popup, Divider, reload, Checkbox} from "svelte-fomantic-ui";

    import type { Sentant } from './reality2.js';
    import R2 from "./reality2";
    import { div } from 'three/tsl';

    export let sentant: Sentant = {name: "", id: "", description: "", events: [], signals: []};
    export let r2_node: R2;
    export let mini:boolean = false;
    export let height: string = "1000px";
    export let variables = {};

    type input_text_type = {[key:string]: any}
    type params_type = {[key:string]: string}

    let messages = ["|", "|", "|", "|", "|"];
    let input_text: input_text_type = {};
    let max_messages = 5;
    let wide_message = false;

    let show_message = false;
    let current_message = "";

    async function copyMessage(data: string) {
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

    async function updatePopup(id: string) {
        await tick();
        reload(id);
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

                    // Reload svelte elements on the sentant so that the newly created popups are activated
                    updatePopup(sentant.id);
                }
            });
        }
    });
</script>
<!----------------------------------------------------------------------------------------------------->

{#if sentant.name != "monitor"}
    {#if show_message}
        <Card style="height: {height};" id={sentant.id}>
            <Div style={mini?"text-align: center;":"height:150px; text-align: center; padding-top: 10px; padding-left: 10px; padding-right:10px;"}>
                <Header ui>{sentant.name}</Header>
                <p><Text ui small blue>{sentant.id}</Text></p>
                <p><Text ui>{current_message.split('|')[0].split(", ")[1]}</Text></p>
            </Div>
            <Divider ui small horizontal center aligned header blue>message</Divider>
            <Div style="text-align: center;">
                <Text ui >narrow&nbsp;&nbsp;</Text><Checkbox ui toggle bind:checked={wide_message} label=" " grey/><Text ui>wide</Text>
            </Div>
            <Divider ui small horizontal center aligned header blue>message</Divider>
            <Div style="overflow:auto; height: 620px; padding-left: 10px; padding-right:10px;">
                <Text ui>
                    <pre style="text-align: left; white-space: pre-wrap; word-wrap: break-word; overflow-wrap: break-word; width: {wide_message ? "100ch" : "30ch"};">{JSON.stringify(try_convert(current_message.split('|')[1]), null, 4)}</pre>
                </Text>
            </Div>
            <Div style="height:80px; position: absolute; bottom: 0px; left: 0px; right: 0px;">
                <Divider ui small horizontal center aligned header blue>actions</Divider>
                <Div style="padding-left: 10px; padding-right:10px;">
                    <Button ui teal fluid on:click={() => show_message = false}>done</Button>
                </Div>
            </Div>
        </Card>
    {:else}
        <Card style="height: {height};" id={sentant.id}>
            <Link ui image href={"/?name=" + sentant.name + "&variables=" + encodeURIComponent(JSON.stringify(variables))}>
                <Image ui large src="/images/bee_blue.png" />
            </Link>
            <Div style={mini?"text-align: center;":"height:130px; text-align: center; padding-top:10px; padding-left: 10px; padding-right:10px;"}>
                <Header ui>{sentant.name}</Header>
                <p><Text ui small blue>{sentant.id}</Text></p>
                <p>{sentant.description}</p>
            </Div>
            <Divider ui small horizontal center aligned header blue>messages</Divider>
            <Div style={mini?"text-align: center;":"height:150px; text-align: center; padding-left: 10px; padding-right:10px;"}>
                {#each messages as message, i}
                    {#if message.split('|')[0] != ""}
                        <Button ui icon small basic popup style="box-shadow: 0 0 0 0;" data-tooltip={"click to see message"} on:click={() => {
                                current_message = message;
                                show_message = true;
                            }}>
                            <Text ui _={(i == messages.length-1 ? "teal" : "grey")}>      
                                {message.split('|')[0].split(", ")[1]}
                            </Text>                        
                        </Button>
                        <Button ui icon small basic popup style="box-shadow: 0 0 0 0;" data-tooltip={"copy to clipboard"} on:click={() => copyMessage(JSON.stringify(try_convert(message.split('|')[1]), null, 4))}><Icon ui clipboard/></Button>
                        <br/>
                    {/if}
                {/each}
            </Div>
            {#if !mini}
                <Divider ui small horizontal center aligned header blue>actions</Divider>
                {#if sentant.events.length > 0}
                    <Div style="overflow-y:auto; overflow-x: hidden; height:230px; text-align: center; padding-left: 10px; padding-right:10px;">
                        {#each sentant.events as event, i}
                            {#each Object.keys(event.parameters) as key}
                                <Input ui labeled fluid style={"margin-bottom:5px;"}>    
                                    <Input text large placeholder={key} bind:value={input_text[event.event+key]}/>
                                </Input>
                            {/each}
                            <Button ui teal fluid on:click={() => event_button_pressed(sentant.id, event.event)} style={"margin-bottom:20px;"}>
                                {event.event}
                            </Button>
                            {#if i < (sentant.events.length - 1)}
                                <Divider ui teal></Divider>
                            {/if}
                        {/each}
                    </Div>
                {/if}
                <Div style="height:80px; position: absolute; bottom: 0px; left: 0px; right: 0px;">
                    <Divider ui small horizontal center aligned header orange>danger zone</Divider>
                    <Div style="padding-left: 10px; padding-right:10px;">
                        <Button ui orange fluid basic on:click={unload_sentant}>
                            Unload
                        </Button>
                    </Div>
                </Div>
            {/if}
        </Card>
    {/if}
{/if}