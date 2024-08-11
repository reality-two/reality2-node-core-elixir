<!------------------------------------------------------------------------------------------------------
  Simple WebApp for a Reality Node

  Author: Dr. Roy C. Davies
  Created: April 2024
  Contact: roy.c.davies@ieee.org
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { behavior, Cards, Menu, Icon, Segment, Button, Buttons, Item, Message, Header, Text, Input, Dropdown } from "svelte-fomantic-ui";

    import R2 from "./lib/reality2";
    import type Sentant from './lib/reality2';
    import SentantCard from './lib/SentantCard.svelte';
    import SentantCards from './lib/SentantCards.svelte';
    import Login from './lib/Login.svelte';
    import Map from './lib/Map.svelte';
   
    import { getQueryStringVal } from './lib/Querystring.svelte';

    import { onMount } from 'svelte';

    // Set up the sentant loading
    var loadedData: any[] = [];
    $: sentantData = loadedData;


    // Set up the state
    var set_state = "loading";
    $: state = set_state;


    let load_sentant = {
        title: 'Load a Sentant',
        class: 'mini',
        closeIcon: true,
        content: 'Choose a Sentant to load...',
        actions: [{
            text: 'OK',
            class: 'green'
        }]
    }

    let load_swarm = {
        title: 'Load a Swarm',
        class: 'mini',
        closeIcon: true,
        content: 'Choose a Swarm to load...',
        actions: [{
            text: 'OK',
            class: 'green'
        }]
    }


    // -------------------------------------------------------------------------------------------------
    // Query Strings
    // -------------------------------------------------------------------------------------------------
    $: name_query = getQueryStringVal("name");
    $: id_query = getQueryStringVal("id");
    $: map_query = getQueryStringVal("map");
    $: view_query = getQueryStringVal("view");
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Window width
    // -------------------------------------------------------------------------------------------------
    let windowWidth: number = 0;

    const setDimensions = () => { 
        windowWidth = window.innerWidth;
    };

    onMount(() => {

        // Set the state depending on the query string
        if (id_query != null) set_state == "id"
        else if (name_query != null) set_state == "name"
        else {
            set_state = "start";
            view_query = "";
        }

        setDimensions();
        window.addEventListener('resize', setDimensions);
        return () => { window.removeEventListener('resize', setDimensions); }
    });
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // The Path of this page
    // -------------------------------------------------------------------------------------------------
    $: path = window.location.hostname + (name_query ? "|" + name_query : "") + (id_query ? "|" + id_query : "");
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Main functionality
    // -------------------------------------------------------------------------------------------------
    // GraphQL client setup 
    let r2_node = new R2(window.location.hostname, Number(window.location.port));

    // Set up the monitoring of the Reality2 Node
    if (id_query == null && name_query == null) {
        setTimeout(() => {
            // Set up monitoring callback
            r2_node.monitor((data: any) => { updateSentants(data); });

            // Load the Sentants
            loadSentants()
            .then((result) => {
                set_state = result.state;
                loadedData = result.data;
            })
        }, 100);
    }
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Load the Sentant(s) the first time.
    // -------------------------------------------------------------------------------------------------
    function loadSentants() : Promise<{"state": string, "data": [any]|any|[]}> {
        return new Promise((resolve, reject) => {
            if (id_query != null) {
                set_state = "loading";
                r2_node.sentantGet(id_query, {}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantGet")
                    if (result == null) {
                        resolve({"state": "id", "data": []})
                    }
                    else {
                        resolve({"state": "id", "data": [result]})
                    }
                })
                .catch((_error) => {
                    resolve({"state": "error", "data": []})
                })
            }
            else if (name_query != null) {
                set_state = "loading";
                r2_node.sentantGetByName(name_query, {}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantGet")
                    if (result == null) {
                        resolve({"state": "name", "data": []})
                    }
                    else {
                        resolve({"state": "name", "data": [result]})
                    }
                })
                .catch((_error) => {
                    resolve({"state": "error", "data": []})
                })
            }
            else if ((map_query != null) || (view_query != null)){
                set_state = "loading";
                r2_node.sentantAll({}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantAll")
                    if (result == null) {
                        resolve({"state": ((map_query != null)?"map":"view"), "data": []})
                    }
                    else {
                        resolve({"state": ((map_query != null)?"map":"view"), "data": result})
                    }
                })
                .catch((_error) => {
                    resolve({"state": "error", "data": []})
                })
            }
        })
    }
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Update the list of sentants when something changes (can either be create or delete)
    // -------------------------------------------------------------------------------------------------
    function updateSentants(updates: any) {
        if ((name_query == null) && (id_query == null)){
            var sentant_id = R2.JSONPath(updates, "parameters.id");
            var sentant_name = R2.JSONPath(updates, "parameters.name");
            if ((sentant_id !== null) && (sentant_name !== "view"))
            {
                switch (R2.JSONPath(updates, "parameters.activity")) {
                    case "created":
                        r2_node.sentantGet(sentant_id, {}, "name id description events { event parameters } signals")
                        .then((data) => {
                            // Go through the loaded data and add the new Sentant.
                            loadedData = sentantData.concat(R2.JSONPath(data, "data.sentantGet"));
                        })
                        break;
                    case "deleted":
                        // Go through the loaded data, find the deleted sentant and remove it.
                        loadedData = sentantData.map((data) => {
                            if (sentant_id == R2.JSONPath(data, "id"))
                            {
                                data.name = ".deleted"
                            }
                            return(data);
                        })
                        break;
                    default:
                        break;
                }
            }
        }
    }
    // -------------------------------------------------------------------------------------------------




    // -------------------------------------------------------------------------------------------------
    // Functions used in the Layout
    // -------------------------------------------------------------------------------------------------

    function change_state(e: any) {
        window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/?" + e.detail.value;
    }

    // return true if there are no Sentants, or only the one called "monitor"
    function none_or_monitor_only(sentants: any[]|[]) : boolean {
        let response = true;
        // let sentants: Sentant[] = R2.JSONPath(data, "sentantAll");
        // if (sentants == null) {
        //     let name = R2.JSONPath(data, "sentantGet.name");
        //     if (name !== "monitor")
        //         response = false;
        // } else {
        //     for (let i = 0; i < sentants.length; i++) {
        //         if (R2.JSONPath(sentants[i], "name") !== "monitor") {
        //             response = false;
        //             break;
        //         }
        //     }
        // }
        for (let i = 0; i < sentants.length; i++) {
            if (R2.JSONPath(sentants[i], "name") !== "monitor") {
                response = false;
                break;
            }
        }
        return response;
    }

    // Reload the page
    function reload_page() { 
        loadSentants()
        .then((result) => {
            set_state = result.state;
            loadedData = result.data;
        })
    }

    function on_key_down(event:any) {
        if (event.key === "Enter" && event.target.id === "path")
        {
            let elements = path.split("|");
            if (elements.length > 1) {
                window.location.href = "https://"+ elements[0] + ":" + window.location.port + "/?name=" + elements[1];
            }
            else {
                window.location.href = "https://"+ elements[0] + ":" + window.location.port;
            }
        }
    }
    // -------------------------------------------------------------------------------------------------
</script>
<!----------------------------------------------------------------------------------------------------->



<!----------------------------------------------------------------------------------------------------->
<!----------------------------------------------------------------------------------------------------->
<svelte:window
    on:keydown={on_key_down}
/>
<!----------------------------------------------------------------------------------------------------->



<!------------------------------------------------------------------------------------------------------
Layout
------------------------------------------------------------------------------------------------------->
<main>
    {#if state == "login"}
        <Login></Login>
    {:else}
        <Menu ui top attached grey inverted borderless>
            <Item>
                <Buttons ui icon>
                    <Button ui grey on:click={() => history.back()}>
                        <Icon arrow left/>
                    </Button>
                    <Button ui grey on:click={() => history.forward()}>
                        <Icon arrow right/>
                    </Button>
                    <Button ui grey on:click={reload_page}>
                        <Icon redo/>
                    </Button>
                </Buttons>
            </Item>
            <Item style={"margin: auto; width:"+(windowWidth-260)+"px;"}>
                <Input ui big style={"width:100%;"}>
                    <Input id="path" text placeholder="Enter Path..." bind:value={path}/>
                </Input>
            </Item>
            <Menu right>
                <Dropdown ui item style="position: relative; z-index:1000">
                    <Icon sidebar/>
                    <Menu vertical ui>
                        <Header ui>
                            View
                        </Header>
                        <Item value="view" on:click={change_state}>
                            &nbsp;&nbsp;
                            <Icon ui th/>
                            Grid
                        </Item>
                        <Item value="map" on:click={change_state}>
                            &nbsp;&nbsp;
                            <Icon ui map outline/>
                            Map
                        </Item>
                        <Item value="mr" on:click={change_state}>
                            &nbsp;&nbsp;
                            <Icon ui box/>
                            Mixed Reality
                        </Item>

                        <Header ui>
                        Load
                        </Header>
                        <Item value="load_sentant" on:click={()=>{behavior({type: 'modal', commands: ['show'], settings: load_sentant})}}>
                            &nbsp;&nbsp;
                            <Icon user/>
                            Sentant
                        </Item>
                        <Item value="load_swarn" on:click={()=>{behavior({type: 'modal', commands: ['show'], settings: load_swarm})}}>
                            &nbsp;&nbsp;
                            <Icon users/>
                            Swarm
                        </Item>
                    </Menu>
                </Dropdown>
            </Menu>
        </Menu>
        <Segment ui bottom attached grey>
            <!--------------------------------------------------------------------------------------------->
            {#if state == "start"}
            <!--------------------------------------------------------------------------------------------->
                <Text ui large>Loading...</Text>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "error"}
            <!--------------------------------------------------------------------------------------------->
                <Text ui large>Something bad happened</Text>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "loading"}
            <!--------------------------------------------------------------------------------------------->
                <Text ui large>Loading...</Text>
            <!--------------------------------------------------------------------------------------------->
            {:else if none_or_monitor_only(sentantData)}
            <!--------------------------------------------------------------------------------------------->
                <Text ui large>No Sentants</Text>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "view"}
            <!--------------------------------------------------------------------------------------------->
                <SentantCards {r2_node} {sentantData} />
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "map"}
            <!--------------------------------------------------------------------------------------------->
                <Map {r2_node} {sentantData} />
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "mr"}
            <!--------------------------------------------------------------------------------------------->
                <Text ui large>Coming Soon...</Text>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "id"}
            <!--------------------------------------------------------------------------------------------->
                <Cards ui centered>
                    <SentantCard sentant={sentantData[0]} {r2_node}/>
                </Cards>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "name"}
            <!--------------------------------------------------------------------------------------------->
                <Cards ui centered>
                    <SentantCard sentant={sentantData[0]} {r2_node}/>
                </Cards>
            {/if}
        </Segment>
    {/if}
</main>
<!----------------------------------------------------------------------------------------------------->