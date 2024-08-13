<!------------------------------------------------------------------------------------------------------
  A Login dialog

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    // Import Blockly core.
    import * as Blockly from 'blockly/core';
    // Import the default blocks.
    import * as libraryBlocks from 'blockly/blocks';
    // Import a generator.
    import {javascriptGenerator} from 'blockly/javascript';
    // Import a message file.
    import * as En from 'blockly/msg/en';

    import { onMount } from 'svelte';
    import { onDestroy } from 'svelte';



    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};

    let height = "800px";

    Blockly.defineBlocksWithJsonArray([{
        "type": "string_length",
        "message0": 'length of %1',
        "args0": [
            {
                "type": "input_value",
                "name": "VALUE",
                "check": "String"
            }
        ],
        "output": "Number",
        "colour": 160,
        "tooltip": "Returns number of letters in the provided text.",
        "helpUrl": "http://www.w3schools.com/jsref/jsref_length_string.asp"
    }]);


    const toolbox = {
        // There are two kinds of toolboxes. The simpler one is a flyout toolbox.
        kind: 'flyoutToolbox',
        // The contents is the blocks and other items that exist in your toolbox.
        contents: [
            {
                kind: 'block',
                type: 'controls_if'
            },
            {
                kind: 'block',
                type: 'controls_whileUntil'
            }
            // You can add more blocks to this array.
        ]
    };



    function updateHeight() {
        height = `${window.innerHeight - 120}px`;
    }


    onMount(() => {

        // Set the initial map height
        updateHeight();

        // Add resize event listener
        window.addEventListener('resize', updateHeight);

        Blockly.setLocale(En);

        // Passes the injection div.
        const workspace = Blockly.inject( 'blocklyDiv', 
        {
            toolbox: toolbox
        });
    });

    onDestroy(() => { 
        window.removeEventListener('resize', updateHeight); 
    });


</script>

<div id="blocklyDiv" style="height: {height}; width: 100%;"></div>
