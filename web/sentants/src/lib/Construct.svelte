<!------------------------------------------------------------------------------------------------------
  A Login dialog

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    // ------------------------------------------------------------------------------------------------
    // Imports
    // ------------------------------------------------------------------------------------------------
    //@ts-ignore
    import {Icon, Button, Segment, Buttons, Grid, Column, Row, Text, Divider, Checkbox, Input, Label} from "svelte-fomantic-ui";


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
    import reality2_automation from "./blockly/reality2_automation";
    import reality2_parameter from "./blockly/reality2_parameter";
    import reality2_transition from "./blockly/reality2_transition";
    import reality2_start_transition from "./blockly/reality2_start_transition";
    import reality2_simple_transition from "./blockly/reality2_simple_transition";
    import reality2_action_set from "./blockly/reality2_action_set";
    import reality2_action_send from "./blockly/reality2_action_send";
    import reality2_action_debug from "./blockly/reality2_action_debug";
    
    import toolbox from "./blockly/reality2_blockly_toolbox.json";
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Exported parameters
    // ------------------------------------------------------------------------------------------------
    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let variables = {};
    export let savedState: any; 
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Variables
    // ------------------------------------------------------------------------------------------------
    $: fullHeight = "800px";
    $: codeHeight = "300px";
    $: message = "No Message";
    $: showJSON = [];

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
        reality2_automation.shape,
        reality2_parameter.shape,
        reality2_transition.shape,
        reality2_start_transition.shape,
        reality2_simple_transition.shape,
        reality2_action_set.shape,
        reality2_action_send.shape,
        reality2_action_debug.shape
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
        const leftHeight = window.innerHeight - 120;
        const leftDiv = document.getElementById('blocklyDiv');
        const rightDiv = document.getElementById('codeDiv');

        if (leftDiv && rightDiv) {
            // Get the top Y position of the right div
            const rightDivTopY = rightDiv.getBoundingClientRect().top;

            // Calculate the bottom Y position of the left div (assumed it's positioned at the same level)
            const leftDivTopY = leftDiv.getBoundingClientRect().top;
            const leftDivBottomY = leftDivTopY + leftHeight;

            // Calculate the required height for the right div to align the bottoms
            codeHeight = `${leftDivBottomY - rightDivTopY - 66}px`;
        }

        fullHeight = `${leftHeight}px`;
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // What to do when closing and unloading the page
    // ------------------------------------------------------------------------------------------------
    function beforeUnload() {
        console.log("leaving");
        savedState = Blockly.serialization.workspaces.save(workspace);

        return '...';
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
            theme: Theme
        });


        backpack = new Backpack(workspace, {
            allowEmptyBackpackOpen: true,
            useFilledBackpackImage: true,
            skipSerializerRegistration: true,
            contextMenu: {
                emptyBackpack: true,
                removeFromBackpack: true,
                copyToBackpack: true,
                copyAllToBackpack: false,
                pasteAllToBackpack: false,
                disablePreconditionChecks: false,
            },
        });
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
        javascriptGenerator.forBlock['reality2_action_debug'] = reality2_action_debug.process;
        
    });
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // What to do when the page is removed
    // ------------------------------------------------------------------------------------------------
    onDestroy(() => { 
        window.removeEventListener("resize", updateHeight); 
    });
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Load the current definition as a swarm or sentant
    // ------------------------------------------------------------------------------------------------
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
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Load a file from the local computer and use it to create blocks
    // ------------------------------------------------------------------------------------------------
    function loadSentantDefinitionFile(event: ProgressEvent) {
        const input = event.target as HTMLInputElement;

        if (input.files && input.files[0]) {
            const file = input.files[0];
            const fileName = file.name;

            if (file) {
                const reader = new FileReader();
                const fileType = fileName.split('.').pop()?.toLowerCase();

                reader.onload = function(e:ProgressEvent<FileReader>) {
                    var target: FileReader | null = e.target;
                    if (target !== null) {
                        let contents = target.result as string;
                        if (contents !== null) {
                            if (fileType == "json") {
                                var newCode = JSON.parse(contents);
                                putIntoBackpack(newCode);
                            }
                            else if (fileType == "yaml") {
                                var newCode = yaml.load(contents);
                                putIntoBackpack(newCode);
                            }
                        }
                    }
                };

                reader.onerror = function(e) {
                    console.error("Error reading file");
                };

                reader.readAsText(file); // Read the file as text
                input.value = ''; // Reset in case the same file is to be loaded again.
            }
        } else {
            console.error("No file selected");
        }
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // ------------------------------------------------------------------------------------------------
    function putIntoBackpack(code: any)
    {
        console.log(code);
        
        if (R2.JSONPath(code, "swarm")) {
            backpack.addItem(JSON.stringify(blockly_construct["swarm"](R2.JSONPath(code, "swarm"))));
            backpack.open();
            alert('Swarm definition loaded into backpack.');           
        }
        else if (R2.JSONPath(code, "sentant")) {
            backpack.addItem(JSON.stringify(blockly_construct["sentant"](R2.JSONPath(code, "sentant"))));
            backpack.open();
            alert('Sentant definition loaded into backpack.');           
        }
        else if (R2.JSONPath(code, "plugin")) {
            const method = R2.JSONPath(code, "plugin.method");
            switch(method) {
                case "GET": 
                    backpack.addItem(JSON.stringify(blockly_construct["get_plugin"](R2.JSONPath(code, "plugin"))));
                    backpack.open();
                    alert('Plugin definition loaded into backpack.');
                    break;
                case "POST":
                    backpack.addItem(JSON.stringify(blockly_construct["post_plugin"](R2.JSONPath(code, "plugin"))));
                    backpack.open();
                    alert('Plugin definition loaded into backpack.');
                    break;
                default:
                    alert('Incorrect format');                 
            }          
        }
        else if (R2.JSONPath(code, "automation")) {
            backpack.addItem(JSON.stringify(blockly_construct["automation"](R2.JSONPath(code, "automation"))));
            backpack.open();
            alert('Automation definition loaded into backpack.');           
        }
        else
            alert('Incorrect format');  
    }
    // ------------------------------------------------------------------------------------------------



    // ------------------------------------------------------------------------------------------------
    // Save the current definition to the local computer (as a downloaded file)
    // ------------------------------------------------------------------------------------------------
    function saveSentantDefinition() {
        // Compile the code
        var newCode = javascriptGenerator.workspaceToCode(workspace);
        if (newCode !== "")
        {
            // Get the code in JSON format.
            code = JSON.parse(newCode);

            // Get filename
            var filename = "definition";
            if (R2.JSONPath(code, "swarm.name")) {
                filename = R2.JSONPath(code, "swarm.name") + ".swarm";
            }
            else if (R2.JSONPath(code, "sentant.name")) {
                filename = R2.JSONPath(code, "sentant.name") + ".sentant";
            }
            else if (R2.JSONPath(code, "plugin.name")) {
                filename = R2.JSONPath(code, "plugin.name") + ".plugin";
            }
            else if (R2.JSONPath(code, "automation.name")) {
                filename = R2.JSONPath(code, "automation.name") + ".automation";
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

                alert('Definition saved successfully!');           
            } catch (err: any) {
                if (err.name === 'AbortError') {
                    console.log('User canceled the save operation.');
                } else {
                    console.error('Save failed:', err);
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

            alert('Definition saved successfully!');           
        }
    }
    // ------------------------------------------------------------------------------------------------
</script>


<svelte:window on:beforeunload={beforeUnload}/>

<Grid ui stackable>
    <Column thirteen wide left attached>
        <Segment id="blocklyDiv" style="height: {fullHeight}; width: 100%;"></Segment>
    </Column>
    <Column three wide right attached>
        <Grid ui>
            <Row>
                <Column attached>
                    <Buttons ui labeled icon vertical fluid>
                        <Input ui file invisible>
                            <Input type="file" id="load" accept=".json, .yaml, .toml" on:change={(e)=>loadSentantDefinitionFile(e)}/>
                        </Input>
                        <Label ui button huge _for="load">
                            <Icon ui cloud upload/>
                            load
                        </Label>
                        <Button ui huge on:click={()=>saveSentantDefinition()}>
                            <Icon ui cloud download></Icon>
                            save
                        </Button>
                        <Divider ui inverted></Divider>
                        <Button ui huge on:click={()=>loadToNode()}>
                            <Icon ui running></Icon>
                            run
                        </Button>
                    </Buttons>
                </Column>
            </Row>
            <Row>
                <Column attached>
                    <Button ui fluid huge top attached on:click={()=>{
                            const savedState = Blockly.serialization.workspaces.save(workspace);
                            console.log(JSON.stringify(savedState, null, 2));
                            var newCode=javascriptGenerator.workspaceToCode(workspace); code=(newCode==""?"":JSON.parse(newCode))
                        }}>
                        <Icon ui arrow down></Icon>
                        update&nbsp;&nbsp;
                        <Icon ui arrow down></Icon>
                    </Button>
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
                </Column>
            </Row>
        </Grid>
    </Column>
</Grid>


