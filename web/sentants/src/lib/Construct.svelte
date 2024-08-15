<!------------------------------------------------------------------------------------------------------
  A Login dialog

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    // Import Blockly core.
    import * as Blockly from "blockly/core";
    // Import the default blocks.
    import * as libraryBlocks from "blockly/blocks";
    // Import a generator.
    import {javascriptGenerator} from "blockly/javascript";
    // Import a message file.
    import * as En from "blockly/msg/en";

    import { onMount } from "svelte";
    import { onDestroy } from "svelte";

    import R2 from "./reality2";

    import reality2_sentant from "./reality2_sentant.json";
    import reality2_key_value from "./reality2_key_value.json";
    import reality2_encrypt_decrypt_keys from "./reality2_encrypt_decrypt_keys.json";
    import reality2_get_plugin from "./reality2_get_plugin.json";
    import reality2_post_plugin from "./reality2_post_plugin.json";
    import reality2_plugin_header from "./reality2_plugin_header.json";
    import toolbox from "./reality2_blockly_toolbox.json";


    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};

    $: height = "800px";
    let workspace: any;

    let blockly_definition = [
        reality2_sentant,
        reality2_key_value,
        reality2_encrypt_decrypt_keys,
        reality2_get_plugin,
        reality2_post_plugin,
        reality2_plugin_header
    ];

    Blockly.defineBlocksWithJsonArray(blockly_definition);


    function updateHeight() {
        height = `${window.innerHeight - 120}px`;
    }


    onMount(() => {
        Blockly.setLocale(En);

        // Passes the injection div.
        workspace = Blockly.inject( "blocklyDiv", 
        {
            toolbox: toolbox
        });

        // Add resize event listener
        window.addEventListener("resize", updateHeight);

        updateHeight();

        setTimeout(() => {
            Blockly.svgResize(workspace);
        }, 0);
        
    });

    onDestroy(() => { 
        window.removeEventListener("resize", updateHeight); 
    });


</script>
<div id="blocklyDiv" style="height: {height}; width: 100%;"></div>
