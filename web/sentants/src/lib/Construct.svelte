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

    import R2 from "./reality2";


    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};

    $: height = "800px";
    let workspace;

    Blockly.defineBlocksWithJsonArray([{
        "type": "reality2_sentant",
        "message0": 'name %1',
        "args0": [
            {"type": "field_input", "name": "name", "check": "String", "text": "Sentant Name"}
        ],
        "message1": 'description %1',
        "args1": [
            {"type": "field_input", "name": "description", "check": "String", "text": "A brief description"}            
        ],
        "message2": 'keys %1',
        "args2": [
            {"type": "input_statement", "name": "keys"}
        ],
        "message3": 'plugins %1',
        "args3": [
            {"type": "input_statement", "name": "plugins"}
        ],
        "message4": 'automations %1',
        "args4": [
            {"type": "input_statement", "name": "automations"}
        ],


        // "previousStatement": null,
        // "nextStatement": null,
        "colour": 120

    }, {
        "type": "reality2_key_value",
        "message0": "%1 = %2",
        "args0": [
            {"type": "field_input", "name": "name", "check": "String", "text": "name"},
            {"type": "field_input", "name": "data", "check": "String", "text": "data"}            
        ],
        "previousStatement": null,
        "nextStatement": null,
        "colour": 100
    }, {
        "type": "reality2_encrypt_decrypt_keys",
        "message0": "encryption key = %1",
        "args0": [
            {"type": "field_input", "name": "encryption_key", "check": "String", "text": "data"},
        ],
        "message1": "decryption key = %1",
        "args1": [
            {"type": "field_input", "name": "decryption_key", "check": "String", "text": "data"},
        ],
        "previousStatement": null,
        "nextStatement": null,
        "colour": 100
    }, {
        "type": "reality2_generic_plugin",
        "message0": 'name %1',
        "args0": [
            {"type": "field_input", "name": "name", "check": "String", "text": "name", "tooltip": "Plugin name in reverse DNS format eg: com.openai.api" }
        ],
        "message1": 'description %1',
        "args1": [
            {"type": "field_input", "name": "url", "check": "String", "text": "url", "tooltip": "Full URL including http:// or https://"}            
        ],
        "message2": "method %1",
        "args2": [
            {
                "type": "field_dropdown",
                "name": "method",
                "options": [
                    [ "post", "POST" ],
                    [ "get", "GET" ]
                ]
            }
        ],
        "message3": 'headers %1',
        "args3": [
            {"type": "input_statement", "name": "headers"}
        ],
        "message4": 'body %1',
        "args4": [
            {"type": "input_statement", "name": "body"}
        ],
        "message5": 'output %1',
        "args5": [
            {"type": "input_statement", "name": "output"}
        ],
        "previousStatement": null,
        "nextStatement": null,
        "colour": 100
    }, {
        "type": "reality2_plugin_output",
        "text": "output",
        "message0": 'send %1 = %2 with event %3',
        "args0": [
            {"type": "field_input", "name": "key", "check": "String", "text": "key" },
            {"type": "field_input", "name": "value", "check": "String", "text": "value", "tooltip": "A JSONPath, for example choices.0.message.content"},
            {"type": "field_input", "name": "event", "check": "String", "text": "event"}         
        ],
        "previousStatement": null,
        "nextStatement": null,
        "colour": 100
    }, {
        "type": "reality2_plugin_header",
        "message0": "%1 = %2",
        "args0": [
            {"type": "field_input", "name": "name", "check": "String", "text": "name"},
            {"type": "field_input", "name": "data", "check": "String", "text": "data"}            
        ],
        "previousStatement": null,
        "nextStatement": null,
        "colour": 100
    }]);



    // const toolbox = {
    //     // There are two kinds of toolboxes. The simpler one is a flyout toolbox.
    //     kind: 'flyoutToolbox',
    //     // The contents is the blocks and other items that exist in your toolbox.
    //     contents: [
    //         {
    //             kind: 'block',
    //             type: 'reality2_sentant'
    //         }
    //         // You can add more blocks to this array.
    //     ]
    // };

    const toolbox = {
        "kind": "categoryToolbox",
        "contents": [
            {
                "kind": "category",
                "name": "Sentant",
                "contents": [
                    {
                        "kind": "block",
                        "type": "reality2_sentant"
                    },
                ]
            },
            {
                "kind": "category",
                "name": "Keys",
                "contents": [
                    {
                        "kind": "block",
                        "type": "reality2_key_value"
                    },
                    {
                        "kind": "block",
                        "type": "reality2_encrypt_decrypt_keys"
                    }
                ]
            },
            {
                "kind": "category",
                "name": "Plugins",
                "contents": [
                    {
                        "kind": "block",
                        "type": "reality2_generic_plugin"
                    },
                    {
                        "kind": "block",
                        "type": "reality2_plugin_header"
                    },                    {
                        "kind": "block",
                        "type": "reality2_plugin_output"
                    }
                ]
            }
        ]
    }



    function updateHeight() {
        height = `${window.innerHeight - 120}px`;
    }


    onMount(() => {
        Blockly.setLocale(En);

        // Passes the injection div.
        workspace = Blockly.inject( 'blocklyDiv', 
        {
            toolbox: toolbox
        });

        // Add resize event listener
        window.addEventListener('resize', updateHeight);

        updateHeight();

        setTimeout(() => {
            Blockly.svgResize(workspace);
        }, 0);
        
    });

    onDestroy(() => { 
        window.removeEventListener('resize', updateHeight); 
    });


</script>
{height}
<div id="blocklyDiv" style="height: {height}; width: 100%;"></div>
