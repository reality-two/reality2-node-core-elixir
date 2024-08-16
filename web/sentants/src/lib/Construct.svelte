<!------------------------------------------------------------------------------------------------------
  A Login dialog

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    import {Card, Content, Header, Image, Button, Text, Input, Link, Popup} from "svelte-fomantic-ui";


    // Import Blockly core.
    import * as Blockly from "blockly/core";
    // Import the default blocks.
    import * as libraryBlocks from "blockly/blocks";
    // Import a generator.
    import {javascriptGenerator, Order} from "blockly/javascript";
    // Import a message file.
    import * as En from "blockly/msg/en";

    import { onMount } from "svelte";
    import { onDestroy } from "svelte";

    import JSONTree from 'svelte-json-tree';

    import R2 from "./reality2";

    import reality2_sentant from "./reality2_sentant";
    import reality2_key_value from "./reality2_key_value.json";
    import reality2_encrypt_decrypt_keys from "./reality2_encrypt_decrypt_keys";
    import reality2_get_plugin from "./reality2_get_plugin";
    import reality2_post_plugin from "./reality2_post_plugin.json";
    import reality2_plugin_header from "./reality2_plugin_header";
    import toolbox from "./reality2_blockly_toolbox.json";


    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};

    $: height = "400px";
    let workspace: any;
    $: code = "";

    let blockly_definition = [
        reality2_sentant.shape,
        reality2_key_value,
        reality2_encrypt_decrypt_keys.shape,
        reality2_get_plugin.shape,
        reality2_post_plugin,
        reality2_plugin_header.shape
    ];



    function updateHeight() {
        height = `${(window.innerHeight - 120)/2}px`;
    }


    onMount(() => {
        Blockly.setLocale(En);
        Blockly.defineBlocksWithJsonArray(blockly_definition);

        // Passes the injection div.
        workspace = Blockly.inject( "blocklyDiv", 
        {
            toolbox: toolbox
        });

        // Add resize event listener
        window.addEventListener("resize", updateHeight);

        // Update the height for the first time
        updateHeight();

        // Update the Blockly workspace
        setTimeout(() => { Blockly.svgResize(workspace); }, 0);

        javascriptGenerator.forBlock['reality2_sentant'] = reality2_sentant.process;
        javascriptGenerator.forBlock['reality2_encrypt_decrypt_keys'] = reality2_encrypt_decrypt_keys.process;
        javascriptGenerator.forBlock['reality2_get_plugin'] = reality2_get_plugin.process;
        javascriptGenerator.forBlock['reality2_plugin_header'] = reality2_plugin_header.process;        
    });

    onDestroy(() => { 
        window.removeEventListener("resize", updateHeight); 
    });


</script>
<Button ui on:click={()=>{code = JSON.parse(javascriptGenerator.workspaceToCode(workspace))}}>Generate</Button>
<div id="blocklyDiv" style="height: {height}; width: 100%; --json-tree-font-size: 16px;"></div>
<div style="height: {height}; width: 100%; text-align: left">
    <JSONTree value={code} />
</div>

