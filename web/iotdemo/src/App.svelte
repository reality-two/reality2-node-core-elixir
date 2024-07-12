<!------------------------------------------------------------------------------------------------------
  Simple WebApp for a Reality Node

  Author: Dr. Roy C. Davies
  Created: April 2024
  Contact: roy.c.davies@ieee.org
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { behavior, Cards, Menu, Link, Icon, Segment, Button, Text, Message, Header, Card } from "svelte-fomantic-ui";

    import R2 from "./lib/reality2";
    import SentantCard from './lib/SentantCard.svelte';
    import SensorCard from './lib/SensorCard.svelte';
   
    import { getQueryStringVal } from './lib/Querystring.svelte';

    import { onMount } from 'svelte';
    import QRCode from '@castlenine/svelte-qrcode';

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
                            { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "counter", "value": 0 } },
                            { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": 0 } }
                        ]
                    },
                    {
                        "event": "setsensor", "public": true, "parameters": { "sensor": "integer" },
                        "actions": [
                            { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": "__sensor__" } }
                        ]
                    },
                    {
                        "event": "count", "public": true,
                        "actions": [
                            { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "counter" } },
                            { "command": "set", "parameters": { "key": "counter", "value": { "expr": "counter 1 +"  } } },
                            { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "counter", "value": "__counter__"  } }
                        ]
                    },
                    {
                        "event": "update", "public": true,
                        "actions": [
                            { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "counter" } },
                            { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor" } },
                            { "command": "signal", "public": true, "parameters": { "event": "update" } }
                        ]
                    }
                ]
            }
        ]
    }
}



    // Get all the sentants, or a single Sentant if there is a name or id in the query string
    var loadedData: any[] = [];
    $: sentantData = loadedData;


    // -------------------------------------------------------------------------------------------------
    // Query Strings
    // -------------------------------------------------------------------------------------------------
    $: name_query = getQueryStringVal("name");
    $: id_query = getQueryStringVal("id");
    $: view_query = getQueryStringVal("view")
    $: connect_query = getQueryStringVal("connect")

    var set_state = "loading";
    $: state = set_state;
   // -------------------------------------------------------------------------------------------------
    

    // -------------------------------------------------------------------------------------------------
    // Window width
    // -------------------------------------------------------------------------------------------------
    let windowWidth: number = 0;

    const setDimensions = () => { windowWidth = window.innerWidth; };

    onMount(() => {
        setDimensions();

        if (name_query == null && id_query == null && view_query == null && connect_query == null) set_state = "start"
        else if (connect_query != null) set_state = "connect"
        else if (id_query != null) set_state == "id"
        else if (name_query != null) set_state == "name"
        else if (view_query != null) set_state = "view";

        window.addEventListener('resize', setDimensions);
        return () => { window.removeEventListener('resize', setDimensions); }
    });
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

    // Set up the monitoring of the Reality2 Node only if we are in the main window
    if (id_query == null && name_query == null) {
        setTimeout(() => {
            // Set up monitoring callback
            r2_node.monitor((data: any) => { updateSentants(data); });

            // Load the Sentants
            loadSentants()
            .then((data) => {
                loadedData = data;
            })
        }, 1000);
    }


    function loadSentants() : Promise<[any]|[]> {
        console.log("Loading")
        return new Promise((resolve, reject) => {
            if (id_query != null) {
                set_state = "loading";
                r2_node.sentantGet(id_query, {}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantGet")
                    console.log (result)
                    if (result == null) {
                        set_state = "id"
                        resolve([])
                    }
                    else {
                        set_state = "id"
                        resolve([result])
                    }
                })
                .catch((error) => {
                    set_state = "error";
                    resolve([])
                })
            }
            else if (name_query != null) {
                set_state = "loading";
                r2_node.sentantGetByName(name_query, {}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantGet")
                    console.log (result)
                    if (result == null) {
                        set_state = "name"
                        resolve([])
                    }
                    else {
                        set_state = "name"
                        resolve([result])
                    }
                })
                .catch((error) => {
                    set_state = "error"
                    resolve([])
                })
            }
            else if (view_query != null) {
                set_state = "loading";
                r2_node.sentantAll({}, "name id description events { event parameters } signals")
                .then((data) => {
                    let result = R2.JSONPath(data, "data.sentantAll")
                    console.log (data)
                    if (result == null) {
                        set_state = "view"
                        resolve([])
                    }
                    else {
                        set_state = "view"
                        resolve(result)
                    }
                })
                .catch((error) => {
                    set_state = "error";
                    resolve([])
                })
            }
        })
    }

    function updateSentants(updates: any) {
        if ((name_query == null) && (id_query == null)){
            console.log(updates);
            var sentant_id = R2.JSONPath(updates, "parameters.id");
            if (sentant_id !== null)
            {
                switch (R2.JSONPath(updates, "parameters.activity")) {
                    case "created":
                        console.log("Creating");
                        r2_node.sentantGet(sentant_id, {}, "name id description events { event parameters } signals")
                        .then((data) => {
                            // Go through the loaded data and add the new Sentant.
                            loadedData = sentantData.concat(R2.JSONPath(data, "data.sentantGet"));
                        })
                        break;
                    case "deleted":
                        // Go through the loaded data, find the deleted sentant and remove it.
                        console.log("Deleting");
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

    // return true if there are no Sentants, or only the one called "monitor"
    function none_or_monitor_only(sentants: any[]) : boolean {
        let response = true;
        for (let i = 0; i < sentants.length; i++) {
            if ((R2.JSONPath(sentants[i], "name") !== "monitor") && (R2.JSONPath(sentants[i], "name") !== ".deleted")) {
                response = false;
                break;
            }
        }
        return response;
    }

    // Connect a new device
    function newDevice() {
        console.log("Adding New Device");
        // Load pattern
        r2_node.sentantAll()
        .then((data) => {
            var counter = 0;
            var sentants: [] = R2.JSONPath(data, "data.sentantAll");
            sentants.forEach((sentant) => {
                if ((R2.JSONPath(sentant, "name") !== ".deleted") && (R2.JSONPath(sentant, "name") != "monitor"))
                {
                    counter = counter + 1;
                }
            });
            var newName = "device " + String(counter+1).padStart(4, '0');
            var sentantDefinition = JSON.stringify(template).replace("__name__", newName);

            // Load Sentant
            r2_node.sentantLoad(sentantDefinition)
            .then((data) => {
                var sentantID = R2.JSONPath(data, "data.sentantLoad.id");
                window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?id=" + sentantID;
            })
            .catch((error) => {
                set_state = "error";
                loadedData = [];
            })
        })
        .catch((error) => {
            set_state = "error";
            loadedData = []
        })
    }

    function showView() {
        window.location.href = "https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?view";
    }

    // Reload the page
    function reload() {
        set_state = "loading";
        loadedData = [];
        loadSentants()
        .then((data) => {
            loadedData = data;
        })
     }
    // -------------------------------------------------------------------------------------------------
</script>
<!----------------------------------------------------------------------------------------------------->



<!------------------------------------------------------------------------------------------------------
Layout
------------------------------------------------------------------------------------------------------->
<main>
    <!-- <Menu ui top attached grey inverted borderless>
        <Item>
            <Button ui icon grey on:click={reload}>
                <Icon redo/>
            </Button>
        </Item>
        <Item style={"margin: auto; width:"+(windowWidth-220)+"px;"}>
            <Input ui big disabled style={"width:100%;"}>
                <Input text placeholder="Enter Path..." bind:value={path}/>
            </Input>
        </Item>
        <Menu right>
            <Link item on:click={() => behavior('sidebar', 'toggle')}>
                <Icon sidebar/>
            </Link>
        </Menu>
    </Menu> -->
    <Segment ui bottom attached grey>
        {#if state == "start"}
            <Message ui blue large>
                <Header>
                    <Icon cog/>
                    Scan the QR code to connect your device.
                </Header>
            </Message>
            <Cards ui centered>
                <Card ui>
                    <Link ui href={"https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?connect"}>
                        <QRCode data={"https://"+ window.location.hostname + ":" + window.location.port + "/iotdemo?connect"} isResponsive/>
                    </Link>
                    <Button ui massive fluid blue on:click={showView}>
                        Main View
                    </Button>
                </Card>
            </Cards>
        {:else if state == "connect"}
            <Message ui blue large>
                <Header>
                    <Icon cog/>
                    Connect your device
                </Header>
            </Message>
            <Button ui massive fluid green on:click={newDevice}>Connect</Button>
        {:else if state == "error"}
            <Message ui negative large>
                <Header>
                    <Icon warning/>
                    Something bad happened
                </Header>
            </Message>
        {:else if state == "loading"}
            <Text ui large>Loading...</Text>
        {:else if state == "view"}
            <Cards ui centered>
                {#each sentantData as sentant}
                    <SentantCard {sentant} {r2_node}/>
                {/each}
            </Cards>
        {:else if none_or_monitor_only(sentantData)}
            <Message ui teal large>
                <Header>
                    <Icon warning/>
                    No Devices Connected
                </Header>
            </Message>
        {:else if state == "id"}
            <Cards ui centered>
                <SensorCard sentant={sentantData[0]} {r2_node}/>
            </Cards>
        {:else if state == "name"}
            <Cards ui centered>
                <SensorCard sentant={sentantData[0]} {r2_node}/>
            </Cards>
        {/if}
    </Segment>
</main>
<!----------------------------------------------------------------------------------------------------->