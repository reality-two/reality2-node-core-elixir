<!------------------------------------------------------------------------------------------------------
  A Login dialog

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    import {Icon, Button, Segment, Buttons, Grid, Column, Text, Divider} from "svelte-fomantic-ui";


    // Import Blockly core.
    import * as Blockly from "blockly";
    // Import the default blocks.
    import * as libraryBlocks from "blockly/blocks";
    // Import a generator.
    import {javascriptGenerator, Order} from "blockly/javascript";
    // Import a message file.
    import * as En from "blockly/msg/en";

    import Theme from '@blockly/theme-dark';

    import {Backpack} from '@blockly/workspace-backpack';

    import { onMount } from "svelte";
    import { onDestroy } from "svelte";

    import JSONTree from 'svelte-json-tree';

    import R2 from "./reality2";

    import reality2_swarm from "./blockly/reality2_swarm";
    import reality2_sentant from "./blockly/reality2_sentant";
    import reality2_key_value from "./blockly/reality2_key_value";
    import reality2_data from "./blockly/reality2_data";
    import reality2_encrypt_decrypt_keys from "./blockly/reality2_encrypt_decrypt_keys";
    import reality2_get_plugin from "./blockly/reality2_get_plugin";
    import reality2_post_plugin from "./blockly/reality2_post_plugin";
    import reality2_plugin_header from "./blockly/reality2_plugin_header";
    import reality2_automation from "./blockly/reality2_automation";
    import reality2_parameter from "./blockly/reality2_parameter";
    import reality2_transition from "./blockly/reality2_transition";
    import reality2_start_transition from "./blockly/reality2_start_transition";
    import reality2_simple_transition from "./blockly/reality2_simple_transition";
    import reality2_action_set from "./blockly/reality2_action_set";
    import reality2_action_send from "./blockly/reality2_action_send";
    
    import toolbox from "./blockly/reality2_blockly_toolbox.json";

    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};
    export let savedState: any; 

    $: height = "400px";
    $: fullHeight = "800px";
    $: fullscreen = true;
    $: message = "";

    let workspace: any;
    $: code = {};

    let blockly_definition = [
        reality2_swarm.shape,
        reality2_sentant.shape,
        reality2_key_value.shape,
        reality2_data.shape,
        reality2_encrypt_decrypt_keys.shape,
        reality2_get_plugin.shape,
        reality2_post_plugin.shape,
        reality2_plugin_header.shape,
        reality2_automation.shape,
        reality2_parameter.shape,
        reality2_transition.shape,
        reality2_start_transition.shape,
        reality2_simple_transition.shape,
        reality2_action_set.shape,
        reality2_action_send.shape
    ];



    function updateHeight() {
        height = `${(window.innerHeight - 140)/2}px`;
        fullHeight = `${(window.innerHeight - 140)}px`;
    }


    function beforeUnload() {
        console.log("leaving");
        savedState = Blockly.serialization.workspaces.save(workspace);

        return '...';
    }


    onMount(() => {
        Blockly.setLocale(En);
        Blockly.defineBlocksWithJsonArray(blockly_definition);

        // Passes the injection div.
        workspace = Blockly.inject( "blocklyDiv", 
        {
            toolbox: toolbox,
            theme: Theme
        });


        const backpack = new Backpack(workspace);
        backpack.init();

        // Add resize event listener
        window.addEventListener("resize", updateHeight);

        // Update the height for the first time
        updateHeight();

        // Update the Blockly workspace
        setTimeout(() => { Blockly.svgResize(workspace); }, 0);

        // Set up the blocks
        javascriptGenerator.forBlock['reality2_swarm'] = reality2_swarm.process;
        javascriptGenerator.forBlock['reality2_sentant'] = reality2_sentant.process;
        javascriptGenerator.forBlock['reality2_encrypt_decrypt_keys'] = reality2_encrypt_decrypt_keys.process;
        javascriptGenerator.forBlock['reality2_get_plugin'] = reality2_get_plugin.process;
        javascriptGenerator.forBlock['reality2_post_plugin'] = reality2_post_plugin.process;
        javascriptGenerator.forBlock['reality2_plugin_header'] = reality2_plugin_header.process;   
        javascriptGenerator.forBlock['reality2_key_value'] = reality2_key_value.process;   
        javascriptGenerator.forBlock['reality2_data'] = reality2_data.process;   
        javascriptGenerator.forBlock['reality2_automation'] = reality2_automation.process;   
        javascriptGenerator.forBlock['reality2_parameter'] = reality2_parameter.process;   
        javascriptGenerator.forBlock['reality2_transition'] = reality2_transition.process;   
        javascriptGenerator.forBlock['reality2_start_transition'] = reality2_start_transition.process;   
        javascriptGenerator.forBlock['reality2_simple_transition'] = reality2_simple_transition.process;   
        javascriptGenerator.forBlock['reality2_action_set'] = reality2_action_set.process;   
        javascriptGenerator.forBlock['reality2_action_send'] = reality2_action_send.process;

        setTimeout(() => { 
            try {
                let savedState = {
                    "backpack" : [
                        {
                            "kind": "BLOCK",
                            "type": "reality2_sentant",
                            "fields": {
                                "name":"hello",
                                "description":"world"
                            }
                        }
                    ]
                }

                console.log("LOADING");
                Blockly.serialization.workspaces.load(savedState, workspace);
            }
            catch {

            }
        }, 2000);
        
    });

    onDestroy(() => { 
        window.removeEventListener("resize", updateHeight); 
    });



    function reLoadSentant(name, definition) {

    }



    function loadToNode() {
        var definition: string = javascriptGenerator.workspaceToCode(workspace);
        var definitionJSON: any = JSON.parse(definition);
        var isSentant = definitionJSON["sentant"] !== null;
        var isSwarm = definitionJSON["swarm"] != null;

        if (isSentant) {
            var new_name = definitionJSON["sentant"]["name"];
            if (new_name) {
                r2_node.sentantGetByName(new_name)
                .then((result: any) => {
                    r2_node.sentantUnload(R2.JSONPath(result, "sentantGet.id"))
                    .then((_) => {
                        r2_node.sentantLoad(definition)
                        .then((_) => {
                            message = "Sentant Loaded OK";
                            setTimeout(() => { message = ""; }, 10);
                        })
                        .catch((error) => {
                            console.log("error loading");
                            message = "Sentant didn't load: " + error;
                        })
                    })
                    .catch((error) => {
                        console.log("error unloading");
                        message = "Error unloading";
                    })
                })
                .catch((error) => {
                    r2_node.sentantLoad(definition)
                    .then((_) => {
                        message = "Sentant Loaded OK";
                        setTimeout(() => { message = ""; }, 10);
                    })
                })
            }
        }
    }


</script>


<svelte:window on:beforeunload={beforeUnload}/>

<Grid ui inverted>
    <Column thirteen wide left attached>
        <Segment id="blocklyDiv" style="height: {fullscreen?fullHeight:height}; width: 100%;"></Segment>
        <Segment ui attached>
            <Text ui>{message}</Text>
        </Segment>
        <Segment ui attached inverted style="height: {fullscreen?"0px":height}; width: 100%; text-align: left">
            <div class="json">
                <Text ui large>JSON</Text>
                <Divider ui inverted></Divider>
                <JSONTree value={JSON.parse(JSON.stringify(code))} />
            </div>
            <Divider ui inverted></Divider>
            <div class="json">
                <Text ui large>Blockly</Text>
                <Divider ui inverted></Divider>
                <JSONTree value={JSON.parse(JSON.stringify(savedState))} />
            </div>
        </Segment>
    </Column>
    <Column three wide right attached>
        <Buttons ui icon vertical fluid>
            <Button ui huge basic on:click={()=>{code = JSON.parse(javascriptGenerator.workspaceToCode(workspace))}}>
                <Icon ui code></Icon>&nbsp;
                JSON
            </Button>
            <Button ui huge basic on:click={()=>{fullscreen = !fullscreen; updateHeight(); setTimeout(() => { Blockly.svgResize(workspace); }, 0);}}>
                <Icon ui _={fullscreen?"compress":"expand"}></Icon>&nbsp;
                {(fullscreen?"Show":"Hide") + " definitions"}
            </Button>
            <Button ui huge basic on:click={()=>loadToNode()}>
                <Icon ui arrow down></Icon>&nbsp;
                load to Reality2 Node
            </Button>
            <Button ui huge basic on:click={()=>{}}>
                <Icon ui load></Icon>&nbsp;
                Load from library
            </Button>
            <Button ui huge basic on:click={() => {savedState = Blockly.serialization.workspaces.save(workspace); console.log(savedState);}}>
                <Icon ui save></Icon>&nbsp;
                Save to library
            </Button>
        </Buttons>
    </Column>
</Grid>


