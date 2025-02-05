<!------------------------------------------------------------------------------------------------------
  Simple WebApp for a Reality Node

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roy.c.davies@ieee.org
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { Divider, Table, Table_Head, Table_Row, Table_Col, Table_Body, Message, Content, Cards, Menu, Label, Icon, Segment, Button, Buttons, Item, Link, Header, Text, Input, Dropdown } from "svelte-fomantic-ui";

    import R2 from "./lib/reality2";
    import type Sentant from './lib/reality2';
    import SentantCard from './lib/SentantCard.svelte';
    import SentantCards from './lib/SentantCards.svelte';
    import Login from './lib/Login.svelte';
    import Construct from './lib/Construct.svelte';
    import Map from './lib/Map.svelte';
   
    import { getQueryStringVal } from './lib/Querystring.svelte';

    import { onMount, onDestroy } from 'svelte';

    let default_port = 4005;
    let use_default_url = false;
    let watchId: any;

    // Set up the sentant loading
    var loadedData: any[] = [];
    $: sentantData = loadedData;

    // Set up the state
    var set_state = "loading";
    $: state = set_state;

    // Set up the geolocation
    var set_location = {};
    $: location = set_location;

    // Saved state for constructor
    let savedState = {};


    // -------------------------------------------------------------------------------------------------
    // Query Strings
    // -------------------------------------------------------------------------------------------------
    $: name_query = getQueryStringVal("name");
    $: id_query = getQueryStringVal("id");
    $: map_query = getQueryStringVal("map");
    $: view_query = getQueryStringVal("view");
    $: mr_query = getQueryStringVal("mr");
    $: variables_query = getQueryStringVal("variables");
    $: construct_query = getQueryStringVal("construct");
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Window width
    // -------------------------------------------------------------------------------------------------
    let windowWidth: number = 0;
    let fullHeight: String = "400px";
    let variables_loader: any;
    $: variables = variables_query ? JSON.parse(decodeURIComponent(variables_query)) : {};

    const setDimensions = () => { 
        windowWidth = window.innerWidth;
        fullHeight = `${(window.innerHeight - 64)}px`;
    };
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // GraphQL client setup 
    // -------------------------------------------------------------------------------------------------
    let r2_node = new R2(use_default_url ? "localhost" : window.location.hostname, Number(use_default_url ? "4005" : window.location.port));
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // On page load
    // -------------------------------------------------------------------------------------------------
    onMount(() => {
        // Set the state depending on the query string
        if (id_query != null) set_state == "id"
        else if (name_query != null) set_state == "name"
        else {
            set_state = "start";
            view_query = "";
        }

        // Set up the variables loader
        variables_loader = document.createElement('input');
        variables_loader.type = 'file';

        variables_loader.onchange = (e:any) => { 
            // getting a hold of the file reference
            var file = e.target.files[0]; 

            // setting up the reader
            var reader = new FileReader();
            reader.readAsText(file,'UTF-8');

            // here we tell the reader what to do when it's done reading...
            reader.onload = (readerEvent: any) => {
                if (readerEvent !== null) {
                    variables = JSON.parse(readerEvent["target"]["result"]);  
                }
            }
        }

        // Geolocation
        watchId = navigator.geolocation.watchPosition (
            (position) => {
                console.log(position.coords);
                set_location = {
                    latitude: position.coords.latitude,
                    longitude: position.coords.longitude,
                    altitude: position.coords.altitude,
                    accuracy: position.coords.accuracy,
                    altitudeAccuracy: position.coords.altitudeAccuracy,
                    heading: position.coords.heading,
                    speed: position.coords.speed
                }
            },
            (error) => {
                console.error("Error getting location:", error.message);
            }
        );

        setDimensions();
        window.addEventListener('resize', setDimensions);
        return () => { window.removeEventListener('resize', setDimensions); }
    });
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Unload page
    // -------------------------------------------------------------------------------------------------
    onDestroy(() => {
        if (watchId) navigator.geolocation.clearWatch(watchId);
    })
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // The Path of this page
    // -------------------------------------------------------------------------------------------------
    $: path = window.location.hostname + (name_query ? "|" + name_query : "") + (id_query ? "|" + id_query : "");
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Main functionality
    // -------------------------------------------------------------------------------------------------
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
            else if ((map_query != null) || (view_query != null) || (mr_query != null) || (construct_query != null)) {
                set_state = "loading";
                r2_node.sentantAll({}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantAll")
                    if (result == null) {
                        resolve({"state": ((construct_query != null)?"construct":(map_query != null)?"map":(mr_query != null)?"mr":"view"), "data": []})
                    }
                    else {
                        resolve({"state": ((construct_query != null)?"construct":(map_query != null)?"map":(mr_query != null)?"mr":"view"), "data": result})
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
        let newstate = e.detail.value;
        if ((newstate == "view") || (newstate == "map")) {
            loadSentants()
            .then((result) => {
                if (result.state !== "error") {
                    set_state = newstate;
                    loadedData = result.data;
                }
                else {
                    set_state = result.state;
                }
            })
        }
        else {
            set_state = newstate;
        }
        // let hostname = use_default_url ? "localhost" : window.location.hostname;
        
        // window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/?" + e.detail.value;
        // window.location.href = "https://"+ use_default_url ? "localhost" : window.location.hostname + ":" + use_default_url ? "4005" : window.location.port + "/?" + e.detail.value + "&variables=" + encodeURIComponent(JSON.stringify(variables))
    }

    // return true if there are no Sentants, or only the one called "monitor"
    function none_or_monitor_only(sentants: any[]|[]) : boolean {
        let response = true;

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
                window.location.href = "https://"+ use_default_url ? "localhost" : window.location.hostname + ":" + use_default_url ? "4005" : window.location.port + "/?name=" + elements[1]  + "&variables=" + encodeURIComponent(JSON.stringify(variables));
            }
            else {
                window.location.href = "https://"+ use_default_url ? "localhost" : window.location.hostname + ":" + use_default_url ? "4005" : window.location.port + "/?variables=" + encodeURIComponent(JSON.stringify(variables));
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
<main style={"padding: 0px;"}>
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
                    <Menu vertical ui style="width: 350px;">
                        <Header ui>
                            View
                        </Header>
                        <Item icon value="view" on:click={change_state}>
                            <Icon ui th/>
                            Grid
                        </Item>
                        <Item icon value="map" on:click={change_state}>
                            <Icon ui map outline/>
                            Map
                        </Item>
                        <Item icon value="construct" on:click={change_state}>
                            <Icon ui hammer/>
                            Construct
                        </Item>
                    </Menu>
                </Dropdown>
            </Menu>
        </Menu>
        <Segment ui bottom attached grey compact style="height: {fullHeight}; width: 100%; padding: 0px;">
            <!--------------------------------------------------------------------------------------------->
            {#if state == "start"}
            <!--------------------------------------------------------------------------------------------->
                <Message ui centered blue massive>
                    <Content ui>
                        Loading ...
                    </Content>
                </Message>            
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "error"}
            <!--------------------------------------------------------------------------------------------->
                <Message ui centered red massive>
                    <Content ui>
                        Something bad happened
                    </Content>
                </Message>      
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "loading"}
            <!--------------------------------------------------------------------------------------------->
                <Message ui centered blue massive>
                    <Content ui>
                        Loading ...
                    </Content>
                </Message>      
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "construct"}
            <!--------------------------------------------------------------------------------------------->
                <Construct {r2_node} {sentantData} {location} bind:savedState bind:variables/>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "id"}
            <!--------------------------------------------------------------------------------------------->
                <Cards ui centered>
                    <SentantCard sentant={sentantData[0]} {r2_node} {variables}/>
                </Cards>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "name"}
            <!--------------------------------------------------------------------------------------------->
                <Cards ui centered>
                    <SentantCard sentant={sentantData[0]} {r2_node} {variables}/>
                </Cards>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "map"}
            <!--------------------------------------------------------------------------------------------->
                <Map {r2_node} {sentantData} {location}/>
            <!--------------------------------------------------------------------------------------------->
            {:else if none_or_monitor_only(sentantData)}
            <!--------------------------------------------------------------------------------------------->
                <Message ui centered green massive>
                    <Content ui>
                        No Sentants
                    </Content>
                </Message>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "view"}
            <!--------------------------------------------------------------------------------------------->
                <SentantCards {r2_node} {sentantData} {variables}/>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "mr"}
            <!--------------------------------------------------------------------------------------------->
                <Message ui centered blue massive>
                    <Content ui>
                        Coming soon ...
                    </Content>
                </Message>      
            <!--------------------------------------------------------------------------------------------->
            {/if}
        </Segment>
    {/if}
</main>
<!----------------------------------------------------------------------------------------------------->