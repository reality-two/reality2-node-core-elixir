<!------------------------------------------------------------------------------------------------------
Construct Swarms and Bees / Sentants

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    // ------------------------------------------------------------------------------------------------
    // Imports
    // ------------------------------------------------------------------------------------------------
    import { behavior, Segment, reload, Flyout, Pusher, Text, Divider, Checkbox, Modal, Icon, Header, Content, Input, Actions, Button, Buttons, Field, Dropdown, Table, Table_Body, Table_Head, Table_Col, Table_Row, update } from "svelte-fomantic-ui";

    //@ts-ignore

    // Import Blockly core.
    import * as Blockly from "blockly";
    // Import the default blocks.
    import * as libraryBlocks from "blockly/blocks";
    // Import a generator.
    import {javascriptGenerator, Order} from "blockly/javascript";
    // Import a message file.
    import * as En from "blockly/msg/en";

    //@ts-ignore
    import Theme from '@blockly/theme-dark';

    //@ts-ignore
    import yaml from 'js-yaml';

    import {Backpack, backpackChange} from '@blockly/workspace-backpack';

    import { onMount } from "svelte";
    import { onDestroy } from "svelte";

    import R2 from "./reality2";

    import reality2_swarm from "./blockly/reality2_swarm";
    import reality2_sentant from "./blockly/reality2_sentant";
    import reality2_key_value from "./blockly/reality2_key_value";
    import reality2_data from "./blockly/reality2_data";
    import reality2_encrypt_decrypt_keys from "./blockly/reality2_encrypt_decrypt_keys";
    import reality2_get_plugin from "./blockly/reality2_get_plugin";
    import reality2_post_plugin from "./blockly/reality2_post_plugin";
    import reality2_plugin_header from "./blockly/reality2_plugin_header";
    import reality2_plugin_body from "./blockly/reality2_plugin_body";
    import reality2_plugin_parameter from "./blockly/reality2_plugin_parameter";
    import reality2_automation from "./blockly/reality2_automation";
    import reality2_parameter from "./blockly/reality2_parameter";
    import reality2_transition from "./blockly/reality2_transition";
    import reality2_transition_no_params from "./blockly/reality2_transition_no_params";
    import reality2_start_transition from "./blockly/reality2_start_transition";
    import reality2_start_transition_no_params from "./blockly/reality2_start_transition_no_params";
    import reality2_simple_transition from "./blockly/reality2_simple_transition";
    import reality2_simple_transition_no_params from "./blockly/reality2_simple_transition_no_params";
    import reality2_start_transition_simple from "./blockly/reality2_start_transition_simple";
    import reality2_monitor from "./blockly/reality2_monitor";
    import reality2_action_set from "./blockly/reality2_action_set";
    import reality2_action_set_clear from "./blockly/reality2_action_set_clear";
    import reality2_action_set_jsonpath from "./blockly/reality2_action_set_jsonpath";
    import reality2_action_set_data from "./blockly/reality2_action_set_data";
    import reality2_action_set_calculation from "./blockly/reality2_action_set_calculation";
    import reality2_action_set_calc_binary from "./blockly/reality2_action_set_calc_binary";
    import reality2_action_set_calc_unary from "./blockly/reality2_action_set_calc_unary";
    import reality2_action_set_value from "./blockly/reality2_action_set_value";
    import reality2_action_send from "./blockly/reality2_action_send";
    import reality2_action_send_no_params from "./blockly/reality2_action_send_no_params";
    import reality2_action_send_now from "./blockly/reality2_action_send_now";
    import reality2_action_send_now_no_params from "./blockly/reality2_action_send_now_no_params";
    import reality2_action_send_plugin from "./blockly/reality2_action_send_plugin";
    import reality2_action_send_plugin_no_params from "./blockly/reality2_action_send_plugin_no_params";
    import reality2_action_send_plugin_no_params_no_event from "./blockly/reality2_action_send_plugin_no_params_no_event";
    import reality2_action_debug from "./blockly/reality2_action_debug";
    import reality2_action_test from "./blockly/reality2_action_test";
    import reality2_action_test_no_params from "./blockly/reality2_action_test_no_params";
    import reality2_action_test_simple from "./blockly/reality2_action_test_simple";
    import reality2_action_signal from "./blockly/reality2_action_signal";
    import reality2_action_signal_no_params from "./blockly/reality2_action_signal_no_params";
    import reality2_action_parameter from "./blockly/reality2_action_parameter";

    import ai_reality2_vars_set from "./blockly/ai_reality2_vars_set";
    import ai_reality2_vars_set_no_value from "./blockly/ai_reality2_vars_set_no_value";
    import ai_reality2_vars_get from "./blockly/ai_reality2_vars_get";
    import ai_reality2_vars_all from "./blockly/ai_reality2_vars_all";
    import ai_reality2_vars_delete from "./blockly/ai_reality2_vars_delete";
    import ai_reality2_vars_clear from "./blockly/ai_reality2_vars_clear";

    import ai_reality2_geospatial_set from "./blockly/ai_reality2_geospatial_set";
    import ai_reality2_geospatial_set_simple from "./blockly/ai_reality2_geospatial_set_simple";
    import ai_reality2_geospatial_set_geohash from "./blockly/ai_reality2_geospatial_set_geohash";
    import ai_reality2_geospatial_set_radius from "./blockly/ai_reality2_geospatial_set_radius";
    import ai_reality2_geospatial_get from "./blockly/ai_reality2_geospatial_get";
    import ai_reality2_geospatial_search from "./blockly/ai_reality2_geospatial_search";
    import ai_reality2_geospatial_remove from "./blockly/ai_reality2_geospatial_remove";

    import ai_reality2_backup_save from "./blockly/ai_reality2_backup_save";
    import ai_reality2_backup_load from "./blockly/ai_reality2_backup_load";
    import ai_reality2_backup_delete from "./blockly/ai_reality2_backup_delete";


    import { splitConcatenatedJSON } from "./blockly/blockly_common";
    
    import toolbox from "./blockly/reality2_blockly_toolbox.json";
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Exported parameters
    // ------------------------------------------------------------------------------------------------
    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables: any = {};
    export let savedState: any;
    export let location: any = {longitude: 0, latitude: 0};
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Variables
    // ------------------------------------------------------------------------------------------------
    $: fullHeight = "800px";
    $: codeHeight = "300px";
    $: showJSON = [];
    let code_loader: any;
    let variables_loader: any;


    let workspace: any;
    let backpack: any;
    let setcode: any = {};
    $: code = setcode;

    let swarm_name: string = "";
    let swarm_description: string = "";
    let swarm_name_dialog = {
        callback: {},
        codeOnPage: {}
    }

    let blockly_definition = [
        reality2_swarm.shape,
        reality2_sentant.shape,
        reality2_key_value.shape,
        reality2_data.shape,
        reality2_encrypt_decrypt_keys.shape,
        reality2_get_plugin.shape,
        reality2_post_plugin.shape,
        reality2_plugin_header.shape,
        reality2_plugin_body.shape,
        reality2_plugin_parameter.shape,
        reality2_automation.shape,
        reality2_parameter.shape,
        reality2_transition.shape,
        reality2_transition_no_params.shape,
        reality2_start_transition.shape,
        reality2_start_transition_no_params.shape,
        reality2_start_transition_simple.shape,
        reality2_simple_transition.shape,
        reality2_simple_transition_no_params.shape,
        reality2_monitor.shape,
        reality2_action_set.shape,
        reality2_action_set_clear.shape,
        reality2_action_set_jsonpath.shape,
        reality2_action_set_data.shape,
        reality2_action_set_calculation.shape,
        reality2_action_set_calc_binary.shape,
        reality2_action_set_calc_unary.shape,
        reality2_action_set_value.shape,
        reality2_action_send.shape,
        reality2_action_send_no_params.shape,
        reality2_action_send_now.shape,
        reality2_action_send_now_no_params.shape,
        reality2_action_send_plugin.shape,
        reality2_action_send_plugin_no_params.shape,
        reality2_action_send_plugin_no_params_no_event.shape,
        reality2_action_debug.shape,
        reality2_action_test.shape,
        reality2_action_test_no_params.shape,
        reality2_action_test_simple.shape,
        reality2_action_signal.shape,
        reality2_action_signal_no_params.shape,
        reality2_action_parameter.shape,

        ai_reality2_vars_set.shape,
        ai_reality2_vars_set_no_value.shape,
        ai_reality2_vars_get.shape,
        ai_reality2_vars_all.shape,
        ai_reality2_vars_delete.shape,
        ai_reality2_vars_clear.shape,

        ai_reality2_geospatial_set.shape,
        ai_reality2_geospatial_set_simple.shape,
        ai_reality2_geospatial_set_geohash.shape,
        ai_reality2_geospatial_set_radius.shape,
        ai_reality2_geospatial_get.shape,
        ai_reality2_geospatial_search.shape,
        ai_reality2_geospatial_remove.shape,

        ai_reality2_backup_save.shape,
        ai_reality2_backup_load.shape,
        ai_reality2_backup_delete.shape
    ];

    let blockly_construct = {
        "sentant": reality2_sentant.construct,
        "swarm": reality2_swarm.construct,
        "get_plugin": reality2_get_plugin.construct,
        "post_plugin": reality2_post_plugin.construct,
        "automation": reality2_automation.construct
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // What to do when the window size is changed
    // ------------------------------------------------------------------------------------------------
    function updateHeight() {
        const leftHeight = window.innerHeight - 64;
        const leftDiv = document.getElementById('blocklyDiv');
        const rightDiv = document.getElementById('codeDiv');

        if (leftDiv && rightDiv) {
            // Get the top Y position of the right div
            const rightDivTopY = rightDiv.getBoundingClientRect().top;

            // Calculate the bottom Y position of the left div (assumed it's positioned at the same level)
            const leftDivTopY = leftDiv.getBoundingClientRect().top;
            const leftDivBottomY = leftDivTopY + leftHeight;

            // Calculate the required height for the right div to align the bottoms
            codeHeight = `${leftDivBottomY - rightDivTopY - 30}px`;
        }

        fullHeight = `${leftHeight}px`;
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // What to do whe the page is loaded
    // ------------------------------------------------------------------------------------------------
    onMount(() => {
        // Blockly.setLocale(En);
        Blockly.defineBlocksWithJsonArray(blockly_definition);

        // Passes the injection div.
        workspace = Blockly.inject( "blocklyDiv", 
        {
            toolbox: toolbox,
            theme: Theme,
            renderer: 'thrasos',
            zoom: {
                controls: true,
                wheel: false,
                startScale: 1.0,
                maxScale: 3,
                minScale: 0.3,
                scaleSpeed: 1.2,
                pinch: true
            },
            grid: {
                spacing: 20,
                length: 3,
                colour: '#333',
                snap: true
            },
            trashcan: true
        });

        // The Blockly backpack
        backpack = new Backpack(workspace, {
            allowEmptyBackpackOpen: true,
            useFilledBackpackImage: true,
            skipSerializerRegistration: true,
            contextMenu: {
                emptyBackpack: true,
                removeFromBackpack: true,
                copyToBackpack: true,
                copyAllToBackpack: true,
                pasteAllToBackpack: true,
                disablePreconditionChecks: false,
            },
        });
        backpack.init();

        // Add resize event listener
        window.addEventListener("resize", updateHeight);

        // Update the height for the first time
        updateHeight();

        // Set up the item loader
        code_loader = document.createElement('input');
        code_loader.type = 'file';
        code_loader.accept=".json, .yaml";

        code_loader.onchange = (e:any) => { 
            // getting a hold of the file reference
            const file = e.target.files[0];

            // setting up the reader
            var reader = new FileReader();
            reader.readAsText(file,'UTF-8');

            // here we tell the reader what to do when it's done reading...
            reader.onload = (readerEvent: any) => {
                setTimeout(() => { 
                    if (readerEvent !== null) {
                        var definition: any = readerEvent["target"]["result"];

                        if (definition !== null) {
                            if (file.type.includes("json")) {
                                var newCode = JSON.parse(definition);
                                putIntoBackpack(newCode);
                            }
                            else if (file.type.includes("yaml")) {
                                var newCode2 = yaml.load(definition);
                                putIntoBackpack(newCode2);
                            }
                        }
                    }
                }, 50);
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
                    showMessage("Success", "Variables loaded successfully", "green");
                }
            }
        }

        // Update the Blockly workspace
        setTimeout(() => { Blockly.svgResize(workspace); }, 0);

        // Set up the blocks
        javascriptGenerator.forBlock['reality2_swarm'] = reality2_swarm.process;
        javascriptGenerator.forBlock['reality2_sentant'] = reality2_sentant.process;
        javascriptGenerator.forBlock['reality2_encrypt_decrypt_keys'] = reality2_encrypt_decrypt_keys.process;
        javascriptGenerator.forBlock['reality2_get_plugin'] = reality2_get_plugin.process;
        javascriptGenerator.forBlock['reality2_post_plugin'] = reality2_post_plugin.process;
        javascriptGenerator.forBlock['reality2_plugin_header'] = reality2_plugin_header.process;   
        javascriptGenerator.forBlock['reality2_plugin_body'] = reality2_plugin_body.process;   
        javascriptGenerator.forBlock['reality2_plugin_parameter'] = reality2_plugin_parameter.process;   
        javascriptGenerator.forBlock['reality2_key_value'] = reality2_key_value.process;   
        javascriptGenerator.forBlock['reality2_data'] = reality2_data.process;   
        javascriptGenerator.forBlock['reality2_automation'] = reality2_automation.process;
        javascriptGenerator.forBlock['reality2_parameter'] = reality2_parameter.process;   
        javascriptGenerator.forBlock['reality2_transition'] = reality2_transition.process;   
        javascriptGenerator.forBlock['reality2_transition_no_params'] = reality2_transition_no_params.process;   
        javascriptGenerator.forBlock['reality2_start_transition'] = reality2_start_transition.process;   
        javascriptGenerator.forBlock['reality2_start_transition_no_params'] = reality2_start_transition_no_params.process;   
        javascriptGenerator.forBlock['reality2_start_transition_simple'] = reality2_start_transition_simple.process;   
        javascriptGenerator.forBlock['reality2_simple_transition'] = reality2_simple_transition.process;   
        javascriptGenerator.forBlock['reality2_simple_transition_no_params'] = reality2_simple_transition_no_params.process;   
        javascriptGenerator.forBlock['reality2_monitor'] = reality2_monitor.process;   
        javascriptGenerator.forBlock['reality2_action_set'] = reality2_action_set.process;   
        javascriptGenerator.forBlock['reality2_action_set_clear'] = reality2_action_set_clear.process;   
        javascriptGenerator.forBlock['reality2_action_set_jsonpath'] = reality2_action_set_jsonpath.process;   
        javascriptGenerator.forBlock['reality2_action_set_data'] = reality2_action_set_data.process;   
        javascriptGenerator.forBlock['reality2_action_set_calculation'] = reality2_action_set_calculation.process;   
        javascriptGenerator.forBlock['reality2_action_set_calc_binary'] = reality2_action_set_calc_binary.process;   
        javascriptGenerator.forBlock['reality2_action_set_calc_unary'] = reality2_action_set_calc_unary.process;   
        javascriptGenerator.forBlock['reality2_action_set_value'] = reality2_action_set_value.process;   
        javascriptGenerator.forBlock['reality2_action_send'] = reality2_action_send.process;
        javascriptGenerator.forBlock['reality2_action_send_no_params'] = reality2_action_send_no_params.process;
        javascriptGenerator.forBlock['reality2_action_send_now'] = reality2_action_send_now.process;
        javascriptGenerator.forBlock['reality2_action_send_now_no_params'] = reality2_action_send_now_no_params.process;
        javascriptGenerator.forBlock['reality2_action_send_plugin'] = reality2_action_send_plugin.process;
        javascriptGenerator.forBlock['reality2_action_send_plugin_no_params'] = reality2_action_send_plugin_no_params.process;
        javascriptGenerator.forBlock['reality2_action_send_plugin_no_params_no_event'] = reality2_action_send_plugin_no_params_no_event.process;
        javascriptGenerator.forBlock['reality2_action_debug'] = reality2_action_debug.process;
        javascriptGenerator.forBlock['reality2_action_test'] = reality2_action_test.process;
        javascriptGenerator.forBlock['reality2_action_test_no_params'] = reality2_action_test_no_params.process;
        javascriptGenerator.forBlock['reality2_action_test_simple'] = reality2_action_test_simple.process;
        javascriptGenerator.forBlock['reality2_action_signal'] = reality2_action_signal.process;
        javascriptGenerator.forBlock['reality2_action_signal_no_params'] = reality2_action_signal_no_params.process;
        javascriptGenerator.forBlock['reality2_action_parameter'] = reality2_action_parameter.process;

        javascriptGenerator.forBlock['ai_reality2_vars_set'] = ai_reality2_vars_set.process;
        javascriptGenerator.forBlock['ai_reality2_vars_set_no_value'] = ai_reality2_vars_set_no_value.process;
        javascriptGenerator.forBlock['ai_reality2_vars_get'] = ai_reality2_vars_get.process;
        javascriptGenerator.forBlock['ai_reality2_vars_all'] = ai_reality2_vars_all.process;
        javascriptGenerator.forBlock['ai_reality2_vars_delete'] = ai_reality2_vars_delete.process;
        javascriptGenerator.forBlock['ai_reality2_vars_clear'] = ai_reality2_vars_clear.process;

        javascriptGenerator.forBlock['ai_reality2_geospatial_set'] = ai_reality2_geospatial_set.process;
        javascriptGenerator.forBlock['ai_reality2_geospatial_set_simple'] = ai_reality2_geospatial_set_simple.process;
        javascriptGenerator.forBlock['ai_reality2_geospatial_set_geohash'] = ai_reality2_geospatial_set_geohash.process;
        javascriptGenerator.forBlock['ai_reality2_geospatial_set_radius'] = ai_reality2_geospatial_set_radius.process;
        javascriptGenerator.forBlock['ai_reality2_geospatial_get'] = ai_reality2_geospatial_get.process;
        javascriptGenerator.forBlock['ai_reality2_geospatial_search'] = ai_reality2_geospatial_search.process;
        javascriptGenerator.forBlock['ai_reality2_geospatial_remove'] = ai_reality2_geospatial_remove.process;

        javascriptGenerator.forBlock['ai_reality2_backup_save'] = ai_reality2_backup_save.process;
        javascriptGenerator.forBlock['ai_reality2_backup_load'] = ai_reality2_backup_load.process;
        javascriptGenerator.forBlock['ai_reality2_backup_delete'] = ai_reality2_backup_delete.process;


        // (re)load the blocks and backpack from variables, for when the mode changes.
        setTimeout(() => {
            if (typeof savedState === "object") {
                if ("backpack" in savedState) loadBackpack(savedState["backpack"]);
                if ("workspace" in savedState) loadWorkspace(savedState["workspace"]);
            }
        }, 2);
        
    });
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Generate encryption (and decryption) keys for synchronous encryption / decryption.
    // ------------------------------------------------------------------------------------------------
    function generateEncryptionKey() {
        // Generate 32 random bytes
        const binaryKey = new Uint8Array(32);
        window.crypto.getRandomValues(binaryKey);

        // Convert to base64
        const encryptionKey = btoa(String.fromCharCode(...binaryKey));

        // Add to the variables
        if (variables) {
            variables["__encryption_key__"] = encryptionKey;
            variables["__decryption_key__"] = encryptionKey;
        }      
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Load and Save workspace and backpack
    // ------------------------------------------------------------------------------------------------
    function saveWorkspace() {
        return Blockly.serialization.workspaces.save(workspace);
    }
    function loadWorkspace(state: any) {
        Blockly.serialization.workspaces.load(state, workspace);
    }
    function saveBackpack() {
        const the_backpack: [any] = backpack.getContents();
        return (the_backpack);
    }
    function loadBackpack(backpack_data: [any]) {
        backpack.setContents(backpack_data);
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // What to do when the page is removed
    // ------------------------------------------------------------------------------------------------
    onDestroy(() => { 
        savedState = {
            workspace: saveWorkspace(),
            backpack: saveBackpack()
        };
        window.removeEventListener("resize", updateHeight); 
    });
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Briefly show a message
    // ------------------------------------------------------------------------------------------------
    function showMessage(title: String, message: String, color: String) {
        behavior({type:"toast", settings:{
            title: title,
            message: message,
            position: 'top attached',
            class: 'center aligned huge ' + color,
            className: {
                toast: 'ui message'
        }}});
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Replace variables in the definition.
    // ------------------------------------------------------------------------------------------------
    function replaceVariables(str: string, variables: {}) {
        const all_variables = {...variables, ...{"__latitude__": location.latitude, "__longitude__": location.longitude}}
        // Iterate over each key in the variables object
        for (const [key, value] of Object.entries(all_variables)) {
            // Create a regular expression to match the key in the string
            // The 'g' flag ensures that all occurrences are replaced
            const regex = new RegExp(key, 'g');
            // Replace all occurrences of the key with its corresponding value
            //@ts-ignore
            str = str.replace(regex, value);
        }
        return str;
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Load the current definition as a swarm or sentant
    // ------------------------------------------------------------------------------------------------
    function loadToNode() {
        firstWorkspaceBlock((definitionJSON: any) => {
            if (Object.keys(definitionJSON).length !== 0) {
                var definition = replaceVariables(JSON.stringify(definitionJSON), variables);
                var isSentant = definitionJSON.hasOwnProperty("sentant");
                var isSwarm = definitionJSON.hasOwnProperty("swarm");

                if (isSentant) {
                    var new_name = definitionJSON["sentant"]["name"];
                    if (new_name) {
                        r2_node.sentantGetByName(new_name)
                        .then((result: any) => {
                            r2_node.sentantUnload(R2.JSONPath(result, "sentantGet.id"))
                            .then((_) => {
                                r2_node.sentantLoad(definition)
                                .then((_) => {
                                    showMessage("Success", "Bee Loaded", "green");
                                })
                                .catch((error) => {
                                    showMessage("Problem", "Error Loading", "red");
                                })
                            })
                            .catch((error) => {
                                showMessage("Problem", "Error Unloading", "red");
                            })
                        })
                        .catch((error) => {
                            r2_node.sentantLoad(definition)
                            .then((_) => {
                                showMessage("Success", "Bee Loaded", "green");
                            })
                        })
                    }
                }
                else if(isSwarm) {
                    r2_node.swarmLoad(definition)
                    .then((_) => {
                        showMessage("Success", "Swarm Loaded", "green");
                    })
                    .catch((error) => {
                        showMessage("Problem", "Error Loading", "red");
                    })
                }
            }
            else {
                showMessage("Status", "Nothing to load", "blue");
            }
        })
    }
    // ------------------------------------------------------------------------------------------------




    // ------------------------------------------------------------------------------------------------
    // Put the given definition into the backpack
    // ------------------------------------------------------------------------------------------------
    function putIntoBackpack(code: any)
    {    
        if (R2.JSONPath(code, "swarm")) {
            backpack.addItem(JSON.stringify(blockly_construct["swarm"](R2.JSONPath(code, "swarm"))));
            backpack.open();
            showMessage("Success", "Swarm loaded into backpack", "green");
        }
        else if (R2.JSONPath(code, "sentant")) {
            backpack.addItem(JSON.stringify(blockly_construct["sentant"](R2.JSONPath(code, "sentant"))));
            backpack.open();
            showMessage("Success", "Bee loaded into backpack", "green");
        }
        else if (R2.JSONPath(code, "plugin")) {
            const method = R2.JSONPath(code, "plugin.method");
            switch(method) {
                case "GET": 
                    backpack.addItem(JSON.stringify(blockly_construct["get_plugin"](R2.JSONPath(code, "plugin"))));
                    backpack.open();
                    showMessage("Success", "Antenna loaded into backpack", "green");
                    break;
                case "POST":
                    backpack.addItem(JSON.stringify(blockly_construct["post_plugin"](R2.JSONPath(code, "plugin"))));
                    backpack.open();
                    showMessage("Success", "Antenna loaded into backpack", "green");
                    break;
                default:
                    showMessage("Problem", "Incorrect format", "red");
            }          
        }
        else if (R2.JSONPath(code, "automation")) {
            backpack.addItem(JSON.stringify(blockly_construct["automation"](R2.JSONPath(code, "automation"))));
            backpack.open();
            showMessage("Success", "Behaviour loaded into backpack", "green");
        }
        else
            showMessage("Problem", "Incorrect format", "red");
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Save the current definition to the local computer (as a downloaded file)
    // ------------------------------------------------------------------------------------------------
    function saveSentantDefinition() {
        // Compile the code
        firstWorkspaceBlock((newCode: any) => {
            if (Object.keys(newCode).length !== 0)
            {
                // Get the code in JSON format.
                setcode = newCode;
                // Get filename
                var filename = "definition";
                if (R2.JSONPath(code, "swarm.name")) {
                    filename = R2.JSONPath(code, "swarm.name") + ".swarm";
                }
                else if (R2.JSONPath(code, "sentant.name")) {
                    filename = R2.JSONPath(code, "sentant.name") + ".bee";
                }
                else if (R2.JSONPath(code, "plugin.name")) {
                    filename = R2.JSONPath(code, "plugin.name") + ".antenna";
                }
                else if (R2.JSONPath(code, "automation.name")) {
                    filename = R2.JSONPath(code, "automation.name") + ".behaviour";
                }

                // Save JSON or YAML
                if (showJSON[0] === "json") {
                    var jsonDefinition = JSON.stringify(code);
                    downloadDefinition(jsonDefinition, filename + ".json"); 
                } else {
                    var yamlDefinition = yaml.dump(code);
                    downloadDefinition(yamlDefinition, filename + ".yaml");
                }
            }
        });
    }
    // ------------------------------------------------------------------------------------------------
 


    // ------------------------------------------------------------------------------------------------
    // Do the actual download
    // ------------------------------------------------------------------------------------------------
    async function downloadDefinition(definition: string, name: string) {

        // If there is a show file picker, then give the user an option of where to save the definition
        if (window.showSaveFilePicker) {
            try {
                // Open a file save dialog and get a file handle
                const handle = await window.showSaveFilePicker({
                    suggestedName: name,
                    types: [
                        {
                            description: 'Reality2 Files',
                            accept: { 'text/plain': ['.json', '.yaml', '.toml'] }
                        }
                    ]
                });

                // Create a writable stream
                const writable = await handle.createWritable();

                // Write the content to the file
                await writable.write(definition);

                // Close the writable stream
                await writable.close();

                showMessage("Success", "Definition saved successfully", "green");
            } catch (err: any) {
                if (err.name === 'AbortError') {
                    showMessage("Status", "Cancelled", "blue");
                } else {
                    showMessage("Problem", "Could not save", "red");
                }
            }
        } else {
            // Otherwise, just download it to the downloads folder

            // Create a Blob with the content
            const blob = new Blob([definition], { type: 'text/plain' });

            // Create an object URL from the Blob
            const url = URL.createObjectURL(blob);

            // Create an invisible <a> element with the download attribute
            const a = document.createElement('a');
            a.href = url;
            a.download = name;
            document.body.appendChild(a);

            // Programmatically click the <a> element to trigger the download
            a.click();

            // Clean up: remove the <a> element and revoke the object URL
            document.body.removeChild(a);
            URL.revokeObjectURL(url);

            showMessage("Success", "Saved successfully", "green");
        }
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Convert the first block to JSON.
    // ------------------------------------------------------------------------------------------------
    function firstWorkspaceBlock(callback: (code: any) => void) {
        let newCode: any = {};
        let theCode: any = {};
        let there_is_a_swarm = false;
        let num_sentants = 0;

        let codeOnPage: any = splitConcatenatedJSON(javascriptGenerator.workspaceToCode(workspace), false);
        // Check if there is a swarm block, with separated bees
        codeOnPage.forEach((element: any) => {
            if (element["swarm"]) {
                there_is_a_swarm = true;
                newCode = element;
            } else if (element["sentant"]) {
                num_sentants++;
            }
        });

        // If there was no swarm, but there are more than one bees, create a swarm
        if ((! there_is_a_swarm) && (num_sentants > 1)) {

            // Save the state for when the user presses ok or cancel.
            swarm_name_dialog.callback = callback;
            swarm_name_dialog.codeOnPage = codeOnPage;

            // Get a name and description for the swarm from the user.
            behavior("swarm_name", "show");
        }
        else
        {
            // If there was a swarm with no sentants, add the sentants array
            if (there_is_a_swarm && num_sentants > 0) newCode["swarm"]["sentants"] = [];

            // Now see if there any stray sentants to add
            if (there_is_a_swarm) {
                codeOnPage.forEach((element: any) => {
                    if (element["sentant"]) {
                        newCode["swarm"]["sentants"].push(element["sentant"]);
                    }
                });
                callback(newCode);
            } else {
                // Otherwise, it's a single sentant, plugin or automation, so get the first one
                if (codeOnPage.length > 0) {
                    newCode = codeOnPage[0];
                    const objType = Object.keys(newCode)[0];
                    theCode[objType] = newCode[objType];
                    callback(theCode);
                }
                else
                {
                    callback({});
                }
            }
        }
    }
    // ------------------------------------------------------------------------------------------------
    function close_swarm_name_dialog(ok: boolean) {
        let callback: any = swarm_name_dialog.callback;
        if (ok) {
            let codeOnPage: any = swarm_name_dialog.codeOnPage;

            let newCode: any = {
                "swarm": {
                    "name": swarm_name,
                    "description": swarm_description,
                    "sentants": []
                }
            };
            
            newCode["swarm"]["sentants"] = [];

            codeOnPage.forEach((element: any) => {
                if (element["sentant"]) {
                    newCode["swarm"]["sentants"].push(element["sentant"]);
                }
            });

            callback(newCode);
        }
        else {
            // Do nothing
            callback({});
        }
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // A work-around because the Flyout creates new versions of itself, which then means the data is
    // not updated because there are more than one div with the same name.
    // ------------------------------------------------------------------------------------------------
    function removeAllButLastById(id:string) 
    {
        let elements = document.querySelectorAll(`[id='${id}']`);

        if (elements.length > 1) {
            // Remove all except the last occurrence
            elements.forEach((el, index) => {
                if (index !== elements.length - 1) {
                el.remove();
                }
            });
        }
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Show the visible code.
    // ------------------------------------------------------------------------------------------------
    function convertBlocks() {
        firstWorkspaceBlock((newcode) => {
            removeAllButLastById("code_space");
            setcode = newcode;
            behavior('code_space', 'toggle');
        });
    }
    // ------------------------------------------------------------------------------------------------

</script>


<Flyout ui very wide id = "code_space">
    <Segment ui attached inverted style={'text-align: left; background-color: #444444; height:100%'}>
        <div style="text-align: center;">
            <Text ui large>YAML&nbsp;&nbsp;</Text><Checkbox ui toggle large inverted bind:group={showJSON} value="json" label=" " grey/><Text ui large>JSON</Text>
        </div>
        <Divider ui inverted></Divider>
        <Table ui inverted>
            <Table_Head>
                <Table_Row>
                    <Table_Col head>key</Table_Col>
                    <Table_Col head>value</Table_Col>
                </Table_Row>
            </Table_Head>
            <Table_Body>
                <Table_Row>
                    <Table_Col>__latitude__</Table_Col>
                    <Table_Col>{location.latitude}</Table_Col>
                </Table_Row>
                <Table_Row>
                    <Table_Col>__longitude__</Table_Col>
                    <Table_Col>{location.longitude}</Table_Col>
                </Table_Row>
                {#each Object.keys(variables) as key}
                    <Table_Row>
                        <Table_Col>{key}</Table_Col>
                        <Table_Col>{variables[key]}</Table_Col>
                    </Table_Row>
                {/each}
            </Table_Body>
        </Table>
        <Buttons ui fluid horizontal>
            <Button ui inverted blue data-variation="wide" data-tooltip="Generate encryption keys.  Use the same keys between subsequent versions of a Bee to ensure access to saved data." on:click={generateEncryptionKey}>generate encryption and decryption keys</Button>
            <Button ui inverted green on:click={() => {downloadDefinition(JSON.stringify(variables), "variables.json"); }}>Save Variables</Button>
        </Buttons>
        <Divider ui inverted></Divider>
        <div class="ui scrollable" id="codeDiv" style="text-align: left; height:{codeHeight}; overflow-y: auto; word-wrap: break-word;">
            {#if Object.keys(code).length !== 0}
                {#if showJSON[0] === "json"}
                    <pre style="text-align: left;">{JSON.stringify(code, null, 2).trim()}</pre>
                {:else}
                    <pre style="text-align: left;">{yaml.dump(code).trim()}</pre>
                {/if}
            {/if}
        </div>
    </Segment>
</Flyout>


<Pusher>
    <div id="blocklyDiv" style="height: {fullHeight}; width: 100%;"></div>
</Pusher>


<Modal ui small id="swarm_name">
    <Icon close/>
    <Header>
        Name your Swarm
    </Header>
    <Content>
        <Table ui>
            <Table_Body>
                <Table_Row>
                    <Table_Col>
                        <Input ui fluid>
                            <Input text placeholder="Swarm name..." bind:value={swarm_name} />
                        </Input>
                    </Table_Col>
                </Table_Row>
                <Table_Row>
                    <Table_Col>
                        <Input ui fluid>
                            <Input text placeholder="Optional Description" bind:value={swarm_description} />
                        </Input>
                    </Table_Col>
                </Table_Row>
            </Table_Body>
        </Table>
    </Content>
    <Actions>
        <Button ui red on:click={()=>{behavior("swarm_name", "hide"); close_swarm_name_dialog(false);}}>Cancel</Button>
        <Button ui green on:click={()=>{behavior({id: "swarm_name", commands: ["hide"]}); close_swarm_name_dialog(true);}}>OK</Button>
    </Actions>
</Modal>

<Button ui icon popup large data-tooltip="Load keys to use with your Bees." data-position="top right" style="position: fixed; top: 200px; right: 45px; background-color: #696969" on:click={()=>{ variables_loader.click(); }}>
    <Icon table></Icon>
</Button>

<Button ui icon large popup data-tooltip="Load Swarms, Bees, Antennae or Behaviours from a file." data-position="top right" style="position: fixed; top: 260px; right: 45px; background-color: #696969" on:click={() => { code_loader.click(); }}>
    <Icon folder open outline></Icon>
</Button>

<Button ui icon large popup data-tooltip="Save Swarms, Bees, Antennae or Behaviours to a file." data-position="top right" style="position: fixed; top: 320px; right: 45px; background-color: #696969" on:click={saveSentantDefinition}>
    <Icon share square></Icon>
</Button>

<Button ui icon large popup data-tooltip="Convert to JSON or YAML and show." data-position="top right" style="position: fixed; top: 440px; right: 45px; background-color: #696969" on:click={() => { convertBlocks(); }}>
    <Icon code></Icon>
</Button>

<Button ui icon large popup data-tooltip="Run the Swarm on the Reality2 node." data-position="top right" style="position: fixed; top: 500px; right: 45px; background-color: #696969" on:click={loadToNode}>
    <Icon running></Icon>
</Button>