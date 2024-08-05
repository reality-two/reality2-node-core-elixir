<!------------------------------------------------------------------------------------------------------
  IoTDemo WebApp Demo for a Reality Node

  Author: Dr. Roy C. Davies
  Created: July 2024
  Contact: roy.c.davies@ieee.org
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { Cards, Link, Segment, Button, Buttons, Text, Message, Header, Card, Content, Input } from "svelte-fomantic-ui";

    import R2 from "./lib/reality2";
    import SentantCard from './lib/SentantCard.svelte';
    import SensorCard from './lib/SensorCard.svelte';
    import Graph from './lib/Graph.svelte';
   
    import { getQueryStringVal } from './lib/Querystring.svelte';

    import { onMount } from 'svelte';
    import QrCode from 'svelte-qrcode';

    var template = {
        "sentant": {
            "name": "__name__",
            "automations": [
                {
                    "name": "counter",
                    "transitions": [
                        {
                            "event": "init",
                            "actions": [
                                { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "name", "value": "__name__" } },
                                { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": 0 } }
                            ]
                        },
                        {
                            "event": "set_sensor", "public": true, "parameters": { "sensor": "integer" },
                            "actions": [
                                { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": "__sensor__" } }
                            ]
                        },
                        {
                            "event": "update", "public": true,
                            "actions": [
                                { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor" } },
                                { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "name" } },
                                { "command": "send", "parameters": { "event": "update", "to": "view" } },
                                { "command": "signal", "public": true, "parameters": { "event": "update" } }
                            ]
                        }
                    ]
                }
            ]
        }
    }

    var view_sentant = {
        "sentant": {
            "name": "view",
            "automations": [
                {
                    "name": "view",
                    "transitions": [
                        {
                            "event": "update", "public": true,
                            "actions": [
                                { "command": "signal", "public": true, "parameters": { "event": "update" } }
                            ]
                        }
                    ]
                }
            ]
        }
    }


    // Set up the sentant loading
    var loadedData: any[] = [];
    $: sentantData = loadedData;

    var graphData: any[] = [];
    var liveData: any[] = [];


    // -------------------------------------------------------------------------------------------------
    // Query Strings
    // -------------------------------------------------------------------------------------------------
    $: name_query = getQueryStringVal("name");
    $: id_query = getQueryStringVal("id");
    $: view_query = getQueryStringVal("view")
    $: connect_query = getQueryStringVal("connect")
    $: graph_query = getQueryStringVal("graph")

    // Set up the state
    var set_state = "loading";
    $: state = set_state;

    var set_ip_addr = window.location.hostname;
    $: ip_addr = set_ip_addr;
    var set_ssid = "SDLmetaverse";
    $: ssid = set_ssid;
    var set_pass = "6ddf9f9ce4";
    $: pass = set_pass;
    $: network_qr = "WIFI:T:WPA;S:"+ssid+";P:"+pass+";H:False;;";
    // -------------------------------------------------------------------------------------------------
    

    // -------------------------------------------------------------------------------------------------
    // Window width, and set the state
    // -------------------------------------------------------------------------------------------------
    let windowWidth: number = 0;

    const setDimensions = () => { windowWidth = window.innerWidth; };

    onMount(() => {

        // Set the state depending on the query string
        if (name_query == null && id_query == null && view_query == null && graph_query == null && connect_query == null) set_state = "start"
        else if (connect_query != null) set_state = "connect"
        else if (id_query != null) set_state == "id"
        else if (name_query != null) set_state == "name"
        else if (view_query != null) set_state = "view";
        else if (graph_query != null) set_state = "graph";

        // Adjust the dimensions of the window automatically
        setDimensions();
        window.addEventListener('resize', setDimensions);
        return () => { window.removeEventListener('resize', setDimensions); }
    });
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Main functionality
    // -------------------------------------------------------------------------------------------------

    function convert_colour(colour: number): string {
        if (colour < 72) { return "red"; }
        if (colour < 144) { return "yellow"; }
        if (colour < 216) { return "green"; }
        if (colour < 288) { return "blue"; }
        return "purple";
    }

    function count_colours(graphData: any[]): any {
        let result = [0, 0, 0, 0, 0];
        Object.keys(graphData).forEach((name: string) => {
            let colour = R2.JSONPath(graphData, name);
            if (colour == "red") result[0] = result[0] + 1;
            else if (colour == "yellow") result[1] = result[1] + 1;
            else if (colour == "green") result[2] = result[2] + 1;
            else if (colour == "blue") result[3] = result[3] + 1;
            else if (colour == "purple") result[4] = result[4] + 1;
        });
        return result;
    }


    // GraphQL client setup 
    let r2_node = new R2(window.location.hostname, Number(window.location.port));

    // Set up the monitoring of the Reality2 Node only if we are in the main window
    if (id_query == null && name_query == null) {
        setTimeout(() => {
            // Set up monitoring callback
            r2_node.monitor((data: any) => { updateSentants(data); });

            r2_node.sentantLoad(JSON.stringify(view_sentant))
            .then((data) => {
                let id = R2.JSONPath(data, "data.sentantLoad.id");
                r2_node.awaitSignal(id, "update", (signal_data: any) => {
                    if(R2.JSONPath(signal_data, "status") == "connected")
                    {
                        console.log("Connected to the view Sentant");
                    }
                    else
                    {
                        let name = R2.JSONPath(signal_data, "parameters.name");
                        let sensor = R2.JSONPath(signal_data, "parameters.sensor");
                        graphData[name] = convert_colour(sensor);
                        liveData = count_colours(graphData);
                    }
                });
            })
            .catch((error) => {
                console.error(error);
            })

            // Load the Sentants
            loadSentants()
            .then((data) => {
                loadedData = data;
            })
        }, 1000);
    }
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Load the Sentant(s) the first time.
    // -------------------------------------------------------------------------------------------------
    function loadSentants() : Promise<[any]|[]> {
        return new Promise((resolve, reject) => {
            if (id_query != null) {
                set_state = "loading";
                r2_node.sentantGet(id_query, {}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantGet")
                    if (result == null) {
                        set_state = "id"
                        resolve([])
                    }
                    else {
                        set_state = "id"
                        resolve([result])
                    }
                })
                .catch((_error) => {
                    set_state = "error";
                    resolve([])
                })
            }
            else if (name_query != null) {
                set_state = "loading";
                r2_node.sentantGetByName(name_query, {}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantGet")
                    if (result == null) {
                        set_state = "name"
                        resolve([])
                    }
                    else {
                        set_state = "name"
                        resolve([result])
                    }
                })
                .catch((_error) => {
                    set_state = "error"
                    resolve([])
                })
            }
            else if (view_query != null) {
                set_state = "loading";
                r2_node.sentantAll({}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantAll")
                    if (result == null) {
                        set_state = "view"
                        resolve([])
                    }
                    else {
                        set_state = "view"
                        resolve(result)
                    }
                })
                .catch((_error) => {
                    set_state = "error";
                    resolve([])
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
                liveData = count_colours(graphData);
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

    // -------------------------------------------------------------------------------------------------
    // return true if there are no Sentants, or only the one called "monitor"
    // -------------------------------------------------------------------------------------------------
    function none_or_monitor_only(sentants: any[]) : boolean {
        let response = true;
        for (let i = 0; i < sentants.length; i++) {
            let name = R2.JSONPath(sentants[i], "name")
            if ((name !== "monitor") && (name !== ".deleted") && (name !== "view")) {
                response = false;
                break;
            }
        }
        return response;
    }
    // -------------------------------------------------------------------------------------------------



    // -------------------------------------------------------------------------------------------------
    // Connect a new device
    // -------------------------------------------------------------------------------------------------
    function newDevice() {

        // Get all the existing Sentants so we can count them to add a new one
        r2_node.sentantAll()
        .then((data) => {
            // Find out how many Sentants there are
            var counter = 0;
            var sentants: [] = R2.JSONPath(data, "data.sentantAll");
            sentants.forEach((sentant) => {
                let name = R2.JSONPath(sentant, "name");
                if ((name !== ".deleted") && (name != "monitor") && (name != "view"))
                {
                    counter = counter + 1;
                }
            });

            // Set the new one to be one more in the sequence
            var newName = "device " + String(counter+1).padStart(4, '0');

            // Set the new name by replacing the '__name__' in the text version of the json definition
            var sentantDefinition = JSON.stringify(template).replace(/__name__/gi, newName);

            // Load Sentant definition to the Reality2 node
            r2_node.sentantLoad(sentantDefinition)
            .then((data) => {
                // Get the ID of the new Sentant
                var sentantID = R2.JSONPath(data, "data.sentantLoad.id");

                // Change the page to view that new Sentant
                window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?id=" + sentantID;
            })
            .catch((_error) => {
                set_state = "error";
                loadedData = [];
            })
        })
        .catch((_error) => {
            set_state = "error";
            loadedData = []
        })
    }
    // -------------------------------------------------------------------------------------------------


    // -------------------------------------------------------------------------------------------------
    // Load the main view showing all the devices
    // -------------------------------------------------------------------------------------------------
    function showView() {
        window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?view";
    }
    // -------------------------------------------------------------------------------------------------


    // -------------------------------------------------------------------------------------------------
    // Load the main view showing all the devices
    // -------------------------------------------------------------------------------------------------
    function showGraph() {
        window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?graph";
    }
    // -------------------------------------------------------------------------------------------------

</script>
<!----------------------------------------------------------------------------------------------------->



<!------------------------------------------------------------------------------------------------------
Layout - how to draw stuff in the browser
------------------------------------------------------------------------------------------------------->
<main>
    <Segment ui bottom attached grey>
        <!--------------------------------------------------------------------------------------------->
        {#if state == "start"}
        <!--------------------------------------------------------------------------------------------->
            <Cards ui centered>
                <Card ui centered>
                    <Message ui blue large>
                        <Header>
                            Scan this QR code to join the IoT network.
                        </Header>
                    </Message>
                    <Content>
                        <Link ui href={"https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?connect"}>
                        <QrCode value={network_qr} size={250} fluid/>
                    </Link>
                    </Content>
                    <Input ui labeled fluid massive>
                        <Input text massive placeholder={"SSID"} bind:value={set_ssid}/>
                    </Input>
                    <Input ui labeled fluid massive>
                        <Input text massive placeholder={"PASS"} bind:value={set_pass} centered/>
                    </Input>
                </Card>
                <Card ui centered>
                    <Message ui blue large>
                        <Header>
                            Scan this QR code to connect your device.
                        </Header>
                    </Message>
                    <Content>
                        <Link ui href={"https://"+ ip_addr + ":" + window.location.port + "/iotdemo?connect"}>
                            <QrCode size={250} value={"https://"+ ip_addr + ":" + window.location.port + "/iotdemo?connect"} isResponsive/>
                        </Link>
                    </Content>
                    <Input ui labeled fluid massive>
                        <Input text massive placeholder={"IP ADDR"} bind:value={set_ip_addr}/>
                    </Input>
                    <Buttons ui fluid>
                        <Button ui massive blue on:click={showView}>
                            Devices
                        </Button>
                        <Button ui massive green on:click={showGraph}>
                            Graph
                        </Button>
                    </Buttons>
                </Card>
            </Cards>
        <!--------------------------------------------------------------------------------------------->
        {:else if state == "connect"}
        <!--------------------------------------------------------------------------------------------->
            <Message ui blue large>
                <Header>
                    Connect your device
                </Header>
            </Message>
            <Button ui massive fluid green on:click={newDevice}>
                connect
            </Button>
        <!--------------------------------------------------------------------------------------------->
        {:else if state == "error"}
        <!--------------------------------------------------------------------------------------------->
            <Message ui negative large>
                <Header>
                    Something bad happened
                </Header>
            </Message>
        <!--------------------------------------------------------------------------------------------->
        {:else if state == "loading"}
        <!--------------------------------------------------------------------------------------------->
            <Text ui large>Loading...</Text>
        <!--------------------------------------------------------------------------------------------->
        {:else if state == "view"}
        <!--------------------------------------------------------------------------------------------->
            {#if none_or_monitor_only(sentantData)}
                <Text ui large>No Devices Connected</Text>
            {:else}
                <Cards ui centered>
                    {#each sentantData as sentant}
                        {#if ((sentant.name !== "monitor") && (sentant.name !== ".deleted") && (sentant.name !== "view"))}
                            <SentantCard {sentant} {r2_node}/>
                        {/if}
                    {/each}
                </Cards>
            {/if}
        <!--------------------------------------------------------------------------------------------->
        {:else if state == "graph"}
        <!--------------------------------------------------------------------------------------------->
            <Graph {liveData}/>
        <!--------------------------------------------------------------------------------------------->
        {:else if none_or_monitor_only(sentantData)}
        <!--------------------------------------------------------------------------------------------->
            <Message ui teal large>
                <Header>
                    No Devices Connected
                </Header>
            </Message>
        <!--------------------------------------------------------------------------------------------->
        {:else if state == "id"}
        <!--------------------------------------------------------------------------------------------->
            <Cards ui centered>
                <SensorCard sentant={sentantData[0]} {r2_node}/>
            </Cards>
        <!--------------------------------------------------------------------------------------------->
        {:else if state == "name"}
        <!--------------------------------------------------------------------------------------------->
            <Cards ui centered>
                <SensorCard sentant={sentantData[0]} {r2_node}/>
            </Cards>
        {/if}
    </Segment>
</main>
<!----------------------------------------------------------------------------------------------------->