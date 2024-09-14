// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_encrypt_decrypt_keys from "./reality2_encrypt_decrypt_keys";
import reality2_key_value from "./reality2_key_value";
import reality2_data from "./reality2_data";
import reality2_get_plugin from "./reality2_get_plugin";
import reality2_post_plugin from "./reality2_post_plugin";
import reality2_automation from "./reality2_automation";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_sentant",
    "message0":"BEE %1",
    "args0":[
        {
            "type":"field_input",
            "name":"name",
            "check":"String",
            "text":"name",
            "tooltip":"Name of Bee"
        }
    ],
    "message1":"%1",
    "args1":[
        {
            "type":"field_input",
            "name":"description",
            "check":"String",
            "text":"description"
        }
    ],
    "message2":" - keys %1",
    "args2":[
        {
            "type":"input_statement",
            "name":"keys",
            "check": "reality2_encrypt_decrypt_keys"
        }
    ],
    "message3":" - data %1",
    "args3":[
        {
            "type":"input_statement",
            "name":"data",
            "check": "reality2_data"
        }
    ],
    "message4":"ANTENNAE",
    "message5":"%1",
    "args5":[
        {
            "type":"input_statement",
            "name":"plugins",
            "check": ["reality2_get_plugin", "reality2_post_plugin"]
        }
    ],
    "message6":"BEHAVIOURS",
    "message7":"%1",
    "args7":[
        {
            "type":"input_statement",
            "name":"automations",
            "check": "reality2_automation"
        }
    ],
    "previousStatement":null,
	"nextStatement": null,
    "colour": 50,
    "tooltip": "A Reality2 Sentient Digital Agent, otherwise known as a Bee, or a Sentant.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var sentant: any = {};

    sentant["name"] = block.getFieldValue('name');
    if (block.getFieldValue('description') !== "") sentant["description"] = block.getFieldValue('description');

    let keys = generator.statementToCode(block, "keys");
    if (keys != "") {
        sentant["keys"] = splitConcatenatedJSON(keys);
    }

    let data = generator.statementToCode(block, "data");
    if (data != "") {
        sentant["data"] = splitConcatenatedJSON(data);
    }

    let plugins = generator.statementToCode(block, "plugins");
    if (plugins != "") {
        sentant["plugins"] = splitConcatenatedJSON(plugins, false).map((plugin: any) => {return (plugin["plugin"])});
    }

    let automations = generator.statementToCode(block, "automations");
    if (automations != "") {
        sentant["automations"] = splitConcatenatedJSON(automations, false).map((automation: any) => {return (automation["automation"])});
    }

    return JSON.stringify({"sentant":sentant});
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(sentant: any)
{
    let description = R2.JSONPath(sentant, "description") ? R2.JSONPath(sentant, "description") : "";
    if (sentant) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_sentant",
            "fields": {
                "name": R2.JSONPath(sentant, "name"),
                "description": description
            },
            "inputs": {
                "keys": {},
                "data": {},
                "plugins": {},
                "automations": {}
            }
        }

        // Check if there are any keys - first, are there encryption or decryption keys
        if (R2.JSONPath(sentant, "keys.encryption_key") || R2.JSONPath(sentant, "keys.decryption_key")) {
            let keys = reality2_encrypt_decrypt_keys.construct(R2.JSONPath(sentant, "keys"));
            if (keys) block["inputs"]["keys"] = { "block": keys }
        } else {
            let keys = reality2_key_value.construct(R2.JSONPath(sentant, "keys"));
            if (keys) block["inputs"]["keys"] = { "block": keys }
        }

        // Check if there is data
        let data = reality2_data.construct(R2.JSONPath(sentant, "data"));
        if (data) block["inputs"]["data"] = { "block": data };

        // Check if there are plugins
        let plugins: [any] = R2.JSONPath(sentant, "plugins");

        // If there are, go backwards through the array creating each block, and linking to the next
        if (plugins) {
            let plugins_block = plugins.reduceRight((acc, plugin) => {

                let method = R2.JSONPath(plugin, "method");
                let plugin_block: any;
                switch (method) {
                    case "GET":
                        plugin_block = reality2_get_plugin.construct(plugin);
                        if (plugin_block && acc) {
                            plugin_block["next"] =  { "block": acc };
                        }
                        break;
                    case "POST":
                        plugin_block = reality2_post_plugin.construct(plugin);
                        if (plugin_block && acc) {
                            plugin_block["next"] =  { "block": acc };
                        }
                        break;
                    default:
                        plugin_block = acc;
                        break;
                };
        
                // accumulate the block so far
                return plugin_block;
            }, null);
        
            // Sentants starts as a block
            block["inputs"]["plugins"] = {"block": plugins_block};
        }

        // Check if there are automations
        let automations: [any] = R2.JSONPath(sentant, "automations");

        // If there are, go backwards through the array creating each block, and linking to the next
        if (automations) {
            let automations_block = automations.reduceRight((acc, automation) => {

                let automation_block: any = reality2_automation.construct(automation);
                if (automation_block && acc) {
                    automation_block["next"] =  { "block": acc };
                }
        
                // accumulate the block so far
                return automation_block;
            }, null);
        
            // Sentants starts as a block
            block["inputs"]["automations"] = {"block": automations_block};
        }

        return (block);
    }
    else {
        return null;
    }
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process, construct};
// ----------------------------------------------------------------------------------------------------