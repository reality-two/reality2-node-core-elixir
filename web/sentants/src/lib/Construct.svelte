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
    import { behavior, Segment, Flyout, Pusher, Text, Divider, Checkbox } from "svelte-fomantic-ui";

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
    import reality2_automation from "./blockly/reality2_automation";
    import reality2_parameter from "./blockly/reality2_parameter";
    import reality2_transition from "./blockly/reality2_transition";
    import reality2_transition_no_params from "./blockly/reality2_transition_no_params";
    import reality2_start_transition from "./blockly/reality2_start_transition";
    import reality2_start_transition_no_params from "./blockly/reality2_start_transition_no_params";
    import reality2_simple_transition from "./blockly/reality2_simple_transition";
    import reality2_simple_transition_no_params from "./blockly/reality2_simple_transition_no_params";
    import reality2_action_set from "./blockly/reality2_action_set";
    import reality2_action_set_clear from "./blockly/reality2_action_set_clear";
    import reality2_action_set_jsonpath from "./blockly/reality2_action_set_jsonpath";
    import reality2_action_set_data from "./blockly/reality2_action_set_data";
    import reality2_action_set_calculation from "./blockly/reality2_action_set_calculation";
    import reality2_action_set_value from "./blockly/reality2_action_set_value";
    import reality2_action_send from "./blockly/reality2_action_send";
    import reality2_action_send_no_params from "./blockly/reality2_action_send_no_params";
    import reality2_action_send_now from "./blockly/reality2_action_send_now";
    import reality2_action_send_now_no_params from "./blockly/reality2_action_send_now_no_params";
    import reality2_action_send_plugin from "./blockly/reality2_action_send_plugin";
    import reality2_action_send_plugin_no_params from "./blockly/reality2_action_send_plugin_no_params";
    import reality2_action_debug from "./blockly/reality2_action_debug";
    import reality2_action_signal from "./blockly/reality2_action_signal";
    import reality2_action_signal_no_params from "./blockly/reality2_action_signal_no_params";
    import reality2_action_parameter from "./blockly/reality2_action_parameter";

    import ai_reality2_vars_set from "./blockly/ai_reality2_vars_set";
    import ai_reality2_vars_set_no_value from "./blockly/ai_reality2_vars_set_no_value";
    import ai_reality2_vars_get from "./blockly/ai_reality2_vars_get";
    import ai_reality2_vars_all from "./blockly/ai_reality2_vars_all";

    import { splitConcatenatedJSON } from "./blockly/blockly_common";
    
    import toolbox from "./blockly/reality2_blockly_toolbox.json";
    import { _SRGBAFormat } from "three";
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Exported parameters
    // ------------------------------------------------------------------------------------------------
    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};
    export let savedState: any;
    export let construct_command: string = "";
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Variables
    // ------------------------------------------------------------------------------------------------
    $: fullHeight = "800px";
    $: codeHeight = "300px";
    $: showJSON = [];
    let code_loader: any;

    let workspace: any;
    let backpack: any;
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
        reality2_plugin_body.shape,
        reality2_automation.shape,
        reality2_parameter.shape,
        reality2_transition.shape,
        reality2_transition_no_params.shape,
        reality2_start_transition.shape,
        reality2_start_transition_no_params.shape,
        reality2_simple_transition.shape,
        reality2_simple_transition_no_params.shape,
        reality2_action_set.shape,
        reality2_action_set_clear.shape,
        reality2_action_set_jsonpath.shape,
        reality2_action_set_data.shape,
        reality2_action_set_calculation.shape,
        reality2_action_set_value.shape,
        reality2_action_send.shape,
        reality2_action_send_no_params.shape,
        reality2_action_send_now.shape,
        reality2_action_send_now_no_params.shape,
        reality2_action_send_plugin.shape,
        reality2_action_send_plugin_no_params.shape,
        reality2_action_debug.shape,
        reality2_action_signal.shape,
        reality2_action_signal_no_params.shape,
        reality2_action_parameter.shape,

        ai_reality2_vars_set.shape,
        ai_reality2_vars_set_no_value.shape,
        ai_reality2_vars_get.shape,
        ai_reality2_vars_all.shape
    ];

    let blockly_construct = {
        "sentant": reality2_sentant.construct,
        "swarm": reality2_swarm.construct,
        "get_plugin": reality2_get_plugin.construct,
        "post_plugin": reality2_post_plugin.construct,
        "automation": reality2_automation.construct
    }

    $: if (construct_command) {
        switch (construct_command) {
        case 'load':
            code_loader.click();
            break;
        case 'save':
            saveSentantDefinition();
            break;
        case 'run':
            loadToNode()
            break;
        case 'code':
            convertBlocks();
            behavior('code_space', 'toggle');
            break;
        case '':
            break;
        default:
            showMessage("Problem", "Unknown command", "red");
        }
        // Reset the command if necessary
        construct_command = '';
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // What to do when the window size is changed
    // ------------------------------------------------------------------------------------------------
    function updateHeight() {
        const leftHeight = window.innerHeight - 90;
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
        Blockly.setLocale(En);
        Blockly.defineBlocksWithJsonArray(blockly_definition);

        // Passes the injection div.
        workspace = Blockly.inject( "blocklyDiv", 
        {
            toolbox: toolbox,
            theme: Theme,
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
                                var newCode = yaml.load(definition);
                                putIntoBackpack(newCode);
                            }
                        }
                    }
                }, 50);
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
        javascriptGenerator.forBlock['reality2_key_value'] = reality2_key_value.process;   
        javascriptGenerator.forBlock['reality2_data'] = reality2_data.process;   
        javascriptGenerator.forBlock['reality2_automation'] = reality2_automation.process;
        javascriptGenerator.forBlock['reality2_parameter'] = reality2_parameter.process;   
        javascriptGenerator.forBlock['reality2_transition'] = reality2_transition.process;   
        javascriptGenerator.forBlock['reality2_transition_no_params'] = reality2_transition_no_params.process;   
        javascriptGenerator.forBlock['reality2_start_transition'] = reality2_start_transition.process;   
        javascriptGenerator.forBlock['reality2_start_transition_no_params'] = reality2_start_transition_no_params.process;   
        javascriptGenerator.forBlock['reality2_simple_transition'] = reality2_simple_transition.process;   
        javascriptGenerator.forBlock['reality2_simple_transition_no_params'] = reality2_simple_transition_no_params.process;   
        javascriptGenerator.forBlock['reality2_action_set'] = reality2_action_set.process;   
        javascriptGenerator.forBlock['reality2_action_set_clear'] = reality2_action_set_clear.process;   
        javascriptGenerator.forBlock['reality2_action_set_jsonpath'] = reality2_action_set_jsonpath.process;   
        javascriptGenerator.forBlock['reality2_action_set_data'] = reality2_action_set_data.process;   
        javascriptGenerator.forBlock['reality2_action_set_calculation'] = reality2_action_set_calculation.process;   
        javascriptGenerator.forBlock['reality2_action_set_value'] = reality2_action_set_value.process;   
        javascriptGenerator.forBlock['reality2_action_send'] = reality2_action_send.process;
        javascriptGenerator.forBlock['reality2_action_send_no_params'] = reality2_action_send_no_params.process;
        javascriptGenerator.forBlock['reality2_action_send_now'] = reality2_action_send_now.process;
        javascriptGenerator.forBlock['reality2_action_send_now_no_params'] = reality2_action_send_now_no_params.process;
        javascriptGenerator.forBlock['reality2_action_send_plugin'] = reality2_action_send_plugin.process;
        javascriptGenerator.forBlock['reality2_action_send_plugin_no_params'] = reality2_action_send_plugin_no_params.process;
        javascriptGenerator.forBlock['reality2_action_debug'] = reality2_action_debug.process;
        javascriptGenerator.forBlock['reality2_action_signal'] = reality2_action_signal.process;
        javascriptGenerator.forBlock['reality2_action_signal_no_params'] = reality2_action_signal_no_params.process;
        javascriptGenerator.forBlock['reality2_action_parameter'] = reality2_action_parameter.process;

        javascriptGenerator.forBlock['ai_reality2_vars_set'] = ai_reality2_vars_set.process;
        javascriptGenerator.forBlock['ai_reality2_vars_set_no_value'] = ai_reality2_vars_set_no_value.process;
        javascriptGenerator.forBlock['ai_reality2_vars_get'] = ai_reality2_vars_get.process;
        javascriptGenerator.forBlock['ai_reality2_vars_all'] = ai_reality2_vars_all.process;

        // (re)load the blocks and backpack from variables, for when the mode changes.
        setTimeout(() => {
            if (typeof savedState === "object") {
                if (savedState.hasOwnProperty("backpack")) loadBackpack(savedState["backpack"]);
                if (savedState.hasOwnProperty("workspace")) loadWorkspace(savedState["workspace"]);
            }
        }, 2);
        
    });
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
        console.log(the_backpack);
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
            class : color,
            className: {
                toast: 'ui message'
        }}});
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Replace variables in the definition.
    // ------------------------------------------------------------------------------------------------
    function replaceVariables(str: string, variables: {}) {
        // Iterate over each key in the variables object
        for (const [key, value] of Object.entries(variables)) {
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
        var definitionJSON: any = firstWorkspaceBlock();
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
                                showMessage("Success", "Sentant Loaded", "green");
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
                            showMessage("Success", "Sentant Loaded", "green");
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
            showMessage("Success", "Swarm definition loaded into backpack", "green");
        }
        else if (R2.JSONPath(code, "sentant")) {
            backpack.addItem(JSON.stringify(blockly_construct["sentant"](R2.JSONPath(code, "sentant"))));
            backpack.open();
            showMessage("Success", "Sentant definition loaded into backpack", "green");
        }
        else if (R2.JSONPath(code, "plugin")) {
            const method = R2.JSONPath(code, "plugin.method");
            switch(method) {
                case "GET": 
                    backpack.addItem(JSON.stringify(blockly_construct["get_plugin"](R2.JSONPath(code, "plugin"))));
                    backpack.open();
                    showMessage("Success", "Plugin definition loaded into backpack", "green");
                    break;
                case "POST":
                    backpack.addItem(JSON.stringify(blockly_construct["post_plugin"](R2.JSONPath(code, "plugin"))));
                    backpack.open();
                    showMessage("Success", "Plugin definition loaded into backpack", "green");
                    break;
                default:
                    showMessage("Problem", "Incorrect format", "red");
            }          
        }
        else if (R2.JSONPath(code, "automation")) {
            backpack.addItem(JSON.stringify(blockly_construct["automation"](R2.JSONPath(code, "automation"))));
            backpack.open();
            showMessage("Success", "Automation definition loaded into backpack", "green");
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
        var newCode = firstWorkspaceBlock();
        if (Object.keys(newCode).length !== 0)
        {
            // Get the code in JSON format.
            code = newCode;
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
                    showMessage("Status", "Cancelled loading", "blue");
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

            showMessage("Success", "Definition saved successfully", "green");
        }
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Convert the first block to JSON.
    // ------------------------------------------------------------------------------------------------
    function firstWorkspaceBlock() {
        let newCode: any = {};
        let there_is_a_swarm = false;
        let num_sentants = 0;
        const codeOnPage: any = splitConcatenatedJSON(javascriptGenerator.workspaceToCode(workspace), false);

        // Check if there is a swarm block, with separated bees
        codeOnPage.forEach((element: any) => {
            if (element["swarm"]) {
                there_is_a_swarm = true;
                newCode = element;
            } else if (element["sentant"]) {
                num_sentants++;
            }
        });

        // If there was no swarm, but there are bees, create a swarm
        if ((! there_is_a_swarm) && (num_sentants > 1)) {
            newCode = {
                "swarm": {
                    "name": "A Swarm",
                    "sentants": []
                }
            };
            there_is_a_swarm = true;
        }

        // If there was a swarm, but no sentants, add the sentants array
        if (there_is_a_swarm && num_sentants > 0) newCode["swarm"]["sentants"] = [];

        console.log(newCode);

        // Now see if there any stray bees to add
        if (there_is_a_swarm) {
            codeOnPage.forEach((element: any) => {
                if (element["sentant"]) {
                    newCode["swarm"]["sentants"].push(element["sentant"]);
                }
            });  
        } else {
            newCode = codeOnPage[0];
        }
     

        const objType = Object.keys(newCode)[0];
        var theCode: any = {};
        theCode[objType] = newCode[objType];
        return (theCode);       
    }
    // ------------------------------------------------------------------------------------------------



    // ----------------------------------------------------------------------------------------------
    // Show the visible code.
    // ------------------------------------------------------------------------------------------------
    function convertBlocks() {
        code = firstWorkspaceBlock();
    }
    // ------------------------------------------------------------------------------------------------

</script>


<Flyout ui very wide id = "code_space">
    <Segment ui attached inverted style={'text-align: left; background-color: #444444; height:100%'}>
        <div style="text-align: center;">
            <Text ui large>YAML&nbsp;&nbsp;</Text><Checkbox ui toggle large inverted bind:group={showJSON} value="json" label=" " grey/><Text ui large>JSON</Text>
        </div>
        <Divider ui inverted></Divider>
        <div class="ui scrollable" id="codeDiv" style="text-align: left; height:{codeHeight}; overflow-y: auto; word-wrap: break-word;">
            <pre style="text-align: left;">
                {#if Object.keys(code).length !== 0}
                    {#if showJSON[0] === "json"}
                        {"\n"+JSON.stringify(code, null, 2)}
                    {:else}
                        {"\n"+yaml.dump(code)}
                    {/if}
                {/if}
            </pre>
        </div>
    </Segment>
</Flyout>

<Pusher>
    <div id="blocklyDiv" style="height: {fullHeight}; width: 100%;"/>
</Pusher>


