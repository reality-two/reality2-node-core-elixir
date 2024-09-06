<!------------------------------------------------------------------------------------------------------
  Simple WebApp for a Reality Node

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roy.c.davies@ieee.org
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { Divider, Table, Table_Head, Table_Row, Table_Col, Table_Body, Cards, Menu, Label, Icon, Segment, Button, Buttons, Item, Message, Header, Text, Input, Dropdown } from "svelte-fomantic-ui";

    import R2 from "./lib/reality2";
    import type Sentant from './lib/reality2';
    import SentantCard from './lib/SentantCard.svelte';
    import SentantCards from './lib/SentantCards.svelte';
    import Login from './lib/Login.svelte';
    import Construct from './lib/Construct.svelte';
    import Map from './lib/Map.svelte';
   
    import { getQueryStringVal } from './lib/Querystring.svelte';

    import { onMount } from 'svelte';

    let default_port = 4005;
    let use_default_url = false;

    // Set up the sentant loading
    var loadedData: any[] = [];
    $: sentantData = loadedData;


    // Set up the state
    var set_state = "loading";
    $: state = set_state;

    // Saved state for constructor
    let savedState = {};


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
    $: mr_query = getQueryStringVal("mr");
    $: variables_query = getQueryStringVal("variables");
    $: construct_query = getQueryStringVal("construct");
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Window width
    // -------------------------------------------------------------------------------------------------
    let windowWidth: number = 0;
    let fullHeight: String = "400px";
    let sentant_loader: any;
    let swarm_loader: any;
    let variables_loader: any;
    $: variables = variables_query ? JSON.parse(decodeURIComponent(variables_query)) : {};

    const setDimensions = () => { 
        windowWidth = window.innerWidth;
        fullHeight = `${(window.innerHeight - 90)}px`;
    };

    // GraphQL client setup 
    let r2_node = new R2(use_default_url ? "localhost" : window.location.hostname, Number(use_default_url ? "4005" : window.location.port));

    onMount(() => {

        // Set the state depending on the query string
        if (id_query != null) set_state == "id"
        else if (name_query != null) set_state == "name"
        else {
            set_state = "start";
            view_query = "";
        }

        console.log(variables_query);
        console.log(JSON.parse(variables_query));

        // Set up the sentant loader
        sentant_loader = document.createElement('input');
        sentant_loader.type = 'file';

        sentant_loader.onchange = (e:any) => { 
            // getting a hold of the file reference
            var file = e.target.files[0]; 

            // setting up the reader
            var reader = new FileReader();
            reader.readAsText(file,'UTF-8');

            // here we tell the reader what to do when it's done reading...
            reader.onload = (readerEvent: any) => {
                if (readerEvent !== null) {
                    var definition: any = readerEvent["target"]["result"];

                    definition = replaceVariables(definition, variables);
                    console.log(definition);

                    r2_node.sentantLoad(definition)
                    .then((result) =>{
                        console.log("LOADED", result)
                    })
                    .catch(() => {
                        console.log("ERROR LOADING")
                    });
                }
            }
        }

        // Set up the swarm loader
        swarm_loader = document.createElement('input');
        swarm_loader.type = 'file';

        swarm_loader.onchange = (e:any) => { 
            // getting a hold of the file reference
            var file = e.target.files[0]; 

            // setting up the reader
            var reader = new FileReader();
            reader.readAsText(file,'UTF-8');

            // here we tell the reader what to do when it's done reading...
            reader.onload = (readerEvent: any) => {
                if (readerEvent !== null) {
                    var definition: any = readerEvent["target"]["result"];

                    definition = replaceVariables(definition, variables);
                    console.log(definition);

                    r2_node.swarmLoad(definition)
                    .then((result) =>{
                        console.log("LOADED", result)
                    })
                    .catch(() => {
                        console.log("ERROR LOADING")
                    });
                }
            }
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
                    console.log(variables);                
                }
            }
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

    function replaceVariables(str: string, variables: {}) {
        // Iterate over each key in the variables object
        for (const [key, value] of Object.entries(variables)) {
            // Create a regular expression to match the key in the string
            // The 'g' flag ensures that all occurrences are replaced
            const regex = new RegExp(key, 'g');
            // Replace all occurrences of the key with its corresponding value
            str = str.replace(regex, value);
        }
        return str;
    }

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
        state = e.detail.value;
        // let hostname = use_default_url ? "localhost" : window.location.hostname;
        
        // window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/?" + e.detail.value;
        // window.location.href = "https://"+ use_default_url ? "localhost" : window.location.hostname + ":" + use_default_url ? "4005" : window.location.port + "/?" + e.detail.value + "&variables=" + encodeURIComponent(JSON.stringify(variables))
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
                        <Item value="construct" on:click={change_state}>
                            &nbsp;&nbsp;
                            <Icon ui hammer/>
                            Constructor 
                        </Item>
                        <!-- <Item value="mr" on:click={change_state}>
                            &nbsp;&nbsp;
                            <Icon ui box/>
                            Mixed Reality
                        </Item> -->

                        <Divider ui fitted/><Divider ui fitted/>
                        <Header ui>
                        Load
                        </Header>
                        <Item value="load_variables" on:click={()=>{ variables_loader.click(); }}>
                            &nbsp;&nbsp;
                            <Label ui>1</Label>
                            <Icon database/>
                            Variables
                            <Menu ui>
                                <Table ui>
                                    <Table_Head>
                                        <Table_Row>
                                            <Table_Col head>key</Table_Col>
                                            <Table_Col head>value</Table_Col>
                                        </Table_Row>
                                    </Table_Head>
                                    <Table_Body>
                                        {#each Object.keys(variables) as key}
                                            <Table_Row>
                                                <Table_Col>{key}</Table_Col>
                                                <Table_Col>{variables[key]}</Table_Col>
                                            </Table_Row>
                                        {/each}
                                    </Table_Body>
                                </Table>
                            </Menu>
                        </Item>
                        <Divider ui horizontal tiny>
                            then
                        </Divider>
                        <Item value="load_sentant" on:click={()=>{ sentant_loader.click(); }}>
                            &nbsp;&nbsp;
                            <Label ui>2</Label>
                            <Icon user/>
                            Sentant
                        </Item>
                        <Divider ui horizontal tiny>
                            or
                        </Divider>
                        <Item value="load_swarm" on:click={()=>{ swarm_loader.click(); }}>
                            &nbsp;&nbsp;
                            <Label ui>2</Label>
                            <Icon users/>
                            Swarm
                        </Item>
                    </Menu>
                </Dropdown>
            </Menu>
        </Menu>
        <Segment ui bottom attached grey style="height: {fullHeight}; width: 100%;">
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
            {:else if state == "construct"}
            <!--------------------------------------------------------------------------------------------->
                <Construct {r2_node} {sentantData} bind:savedState />
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
            {:else if none_or_monitor_only(sentantData)}
            <!--------------------------------------------------------------------------------------------->
                <Text ui large>No Sentants</Text>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "view"}
            <!--------------------------------------------------------------------------------------------->
                <SentantCards {r2_node} {sentantData} {variables}/>
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "map"}
            <!--------------------------------------------------------------------------------------------->
                <Map {r2_node} {sentantData} />
            <!--------------------------------------------------------------------------------------------->
            {:else if state == "mr"}
            <!--------------------------------------------------------------------------------------------->
                <Text ui large>Coming Soon...</Text>
            <!--------------------------------------------------------------------------------------------->
            {/if}
        </Segment>
    {/if}
</main>
<!----------------------------------------------------------------------------------------------------->