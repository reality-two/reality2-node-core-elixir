<!------------------------------------------------------------------------------------------------------
  Simple WebApp for a Reality Node

  Author: Dr. Roy C. Davies
  Created: April 2024
  Contact: roy.c.davies@ieee.org
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { reload, Cards, Menu, Link, Icon, Segment, Button, Item, Message, Header, Text, Input, Dropdown } from "svelte-fomantic-ui";

    import R2 from "./lib/reality2";
    import type Sentant from './lib/reality2';
    import SentantCard from './lib/SentantCard.svelte';
    import Login from './lib/Login.svelte';
    import Map from './lib/Map.svelte';
   
    import { getQueryStringVal } from './lib/Querystring.svelte';

    import { onMount } from 'svelte';


    let mode = "cards"; // login, cards, map


    // -------------------------------------------------------------------------------------------------
    // Window width
    // -------------------------------------------------------------------------------------------------
    let windowWidth: number = 0;
    let windowHeight: number = 0;

    const setDimensions = () => { windowWidth = window.innerWidth; windowHeight = window.innerHeight;};

    onMount(() => {
        setDimensions();
        window.addEventListener('resize', setDimensions);
        return () => { window.removeEventListener('resize', setDimensions); }
    });
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Query Strings
    // -------------------------------------------------------------------------------------------------
    $: name_query = getQueryStringVal("name");
    $: id_query = getQueryStringVal("id");
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // The Path of this page
    // -------------------------------------------------------------------------------------------------
    $: path = window.location.hostname + (name_query ? "." + name_query : "") + (id_query ? "." + id_query : "");
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Main functionality
    // -------------------------------------------------------------------------------------------------
    // GraphQL client setup 
    let r2_node = new R2(window.location.hostname, Number(window.location.port));

    // Set up the monitoring of the Reality2 Node
    setTimeout(() => { r2_node.monitor((_data: any) => { sentantData = loadSentants(); }); }, 1000);

    // Get all the sentants, or a single Sentant if there is a name or id in the query string
    $: sentantData = loadSentants();

    function loadSentants() : Promise<object> {
        if (id_query != null) {
            reload();
            return r2_node.sentantGet(id_query, {}, "name id description events { event parameters } signals")
        }
        else if (name_query != null) {
            reload();
            return r2_node.sentantGetByName(name_query, {}, "name id description events { event parameters } signals");
        }
        else {
            reload();
            return r2_node.sentantAll({}, "name id description events { event parameters } signals");
        }
    }
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Functions used in the Layout
    // -------------------------------------------------------------------------------------------------

    function change_mode(e: any) {
        mode = e.detail.value;
        console.log(mode);
    }

    // Send an event to a Sentant
    function sentantSend(e: CustomEvent) { r2_node.sentantSend(e.detail.id, e.detail.event, e.detail.params); }

    // Await a signal from a Sentant
    function awaitSignal(e: CustomEvent) { r2_node.awaitSignal(e.detail.id, e.detail.signal, e.detail.callback); }

    // return true if there are no Sentants, or only the one called "monitor"
    function none_or_monitor_only(data: {}) : boolean {
        let response = true;
        let sentants: Sentant[] = R2.JSONPath(data, "sentantAll");
        if (sentants == null) {
            let name = R2.JSONPath(data, "sentantGet.name");
            if (name !== "monitor")
                response = false;
        } else {
            for (let i = 0; i < sentants.length; i++) {
                if (R2.JSONPath(sentants[i], "name") !== "monitor") {
                    response = false;
                    break;
                }
            }
        }
        return response;
    }

    // Reload the page
    function reload_page() { sentantData = loadSentants(); }
    // -------------------------------------------------------------------------------------------------
</script>
<!----------------------------------------------------------------------------------------------------->



<!------------------------------------------------------------------------------------------------------
Layout
------------------------------------------------------------------------------------------------------->
<main>
    {#if mode == "login"}
        <Login></Login>
    {:else}
        <Menu ui top attached grey inverted borderless>
            <Item>
                <Button ui icon grey on:click={reload_page}>
                    <Icon redo/>
                </Button>
            </Item>
            <Item style={"margin: auto; width:"+(windowWidth-220)+"px;"}>
                <Input ui big disabled style={"width:100%;"}>
                    <Input text placeholder="Enter Path..." bind:value={path}/>
                </Input>
            </Item>
            <Menu right>
                <Item>
                    <Dropdown ui style="position: relative; z-index:1000">
                        <Icon sidebar/>
                        <Menu ui vertical>
                            <Item value="cards" on:click={change_mode}>
                                <Icon ui th/>
                                Grid
                            </Item>
                            <Item value="map" on:click={change_mode}>
                                <Icon ui map outline/>
                                Map
                            </Item>
                        </Menu>
                    </Dropdown>
                </Item>
            </Menu>
        </Menu>
        {#await sentantData}
            <p>Loading...</p>
        {:then response}
            <Segment ui bottom attached grey>
                {#if response.hasOwnProperty('errors')}
                    <Message ui negative large>
                        <Header>
                            <Icon warning/>
                            Error
                        </Header>
                        <Text ui large>Incorrect {R2.JSONPath(response, "errors.0.message")}</Text>
                    </Message>
                {:else if none_or_monitor_only(R2.JSONPath(response, "data"))}
                    <Message ui teal large>
                        <Header>
                            <Icon warning/>
                            No Sentants Found
                        </Header>
                    </Message>
                {:else}
                    {#if mode == "map"}
                        <Map sentants={R2.JSONPath(response, "data.sentantAll")} {windowHeight} {windowWidth}></Map>
                    {:else}
                        <Cards ui centered>
                            {#if (id_query !== null)}
                                <SentantCard sentant={R2.JSONPath(response, "data.sentantGet")} on:sentantSend={sentantSend} on:awaitSignal={awaitSignal}/>
                            {:else if (name_query !== null)}
                                <SentantCard sentant={R2.JSONPath(response, "data.sentantGet")} on:sentantSend={sentantSend} on:awaitSignal={awaitSignal}/>
                            {:else}
                                {#each R2.JSONPath(response, "data.sentantAll") as sentant}
                                    <SentantCard {sentant} on:sentantSend={sentantSend} on:awaitSignal={awaitSignal}/>
                                {/each}
                            {/if}
                        </Cards>
                    {/if}
                {/if}
            </Segment>
        {:catch error}
            <p>Error: {error.message}</p>
        {/await}
    {/if}
</main>
<!----------------------------------------------------------------------------------------------------->