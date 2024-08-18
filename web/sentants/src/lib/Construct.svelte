<!------------------------------------------------------------------------------------------------------
  A Login dialog

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    import {Icon, Button, Segment, Buttons, Grid, Column} from "svelte-fomantic-ui";


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

    import reality2_sentant from "./blockly/reality2_sentant";
    import reality2_key_value from "./blockly/reality2_key_value";
    import reality2_encrypt_decrypt_keys from "./blockly/reality2_encrypt_decrypt_keys";
    import reality2_get_plugin from "./blockly/reality2_get_plugin";
    import reality2_post_plugin from "./blockly/reality2_post_plugin";
    import reality2_plugin_header from "./blockly/reality2_plugin_header";
    import reality2_automation from "./blockly/reality2_automation";
    import reality2_transition from "./blockly/reality2_transition";
    import toolbox from "./blockly/reality2_blockly_toolbox.json";

    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};

    $: height = "400px";
    $: fullHeight = "800px";
    $: fullscreen = false;

    let workspace: any;
    $: code = "";

    let blockly_definition = [
        reality2_sentant.shape,
        reality2_key_value.shape,
        reality2_encrypt_decrypt_keys.shape,
        reality2_get_plugin.shape,
        reality2_post_plugin.shape,
        reality2_plugin_header.shape,
        reality2_automation.shape,
        reality2_transition.shape
    ];



    function updateHeight() {
        height = `${(window.innerHeight - 140)/2}px`;
        fullHeight = `${(window.innerHeight - 140)}px`;
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
        javascriptGenerator.forBlock['reality2_sentant'] = reality2_sentant.process;
        javascriptGenerator.forBlock['reality2_encrypt_decrypt_keys'] = reality2_encrypt_decrypt_keys.process;
        javascriptGenerator.forBlock['reality2_get_plugin'] = reality2_get_plugin.process;
        javascriptGenerator.forBlock['reality2_post_plugin'] = reality2_post_plugin.process;
        javascriptGenerator.forBlock['reality2_plugin_header'] = reality2_plugin_header.process;   
        javascriptGenerator.forBlock['reality2_key_value'] = reality2_key_value.process;   
        javascriptGenerator.forBlock['reality2_automation'] = reality2_automation.process;   
        javascriptGenerator.forBlock['reality2_transition'] = reality2_transition.process;   
        
    });

    onDestroy(() => { 
        window.removeEventListener("resize", updateHeight); 
    });


</script>
<Grid ui inverted>
    <Column thirteen wide left attached>
        <div id="blocklyDiv" style="height: {fullscreen?fullHeight:height}; width: 100%;"></div>
        <Segment ui attached inverted style="height: {fullscreen?"0px":height}; width: 100%; text-align: left">
            <div class="json">
                <JSONTree value={code} />
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
                {fullscreen?"Half Height":"Full Height"}
            </Button>
            <Button ui huge basic on:click={()=>{}}>
                <Icon ui arrow down></Icon>&nbsp;
                Load to Reality2
            </Button>
            <Button ui huge basic on:click={() => {const state = Blockly.serialization.workspaces.save(workspace); console.log(state);}}>
                <Icon ui save></Icon>&nbsp;
                Save
            </Button>
        </Buttons>
    </Column>
</Grid>


