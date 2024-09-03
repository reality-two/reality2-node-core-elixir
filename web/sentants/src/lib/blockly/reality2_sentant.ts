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

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_sentant",
    "message0":"SENTANT",
    "message1":" - name %1",
    "args1":[
        {
            "type":"field_input",
            "name":"name",
            "check":"String",
            "text":""
        }
    ],
    "message2":" - description %1",
    "args2":[
        {
            "type":"field_input",
            "name":"description",
            "check":"String",
            "text":""
        }
    ],
    "message3":" - keys %1",
    "args3":[
        {
            "type":"input_statement",
            "name":"keys",
            "check": "reality2_encrypt_decrypt_keys"
        }
    ],
    "message4":" - data %1",
    "args4":[
        {
            "type":"input_statement",
            "name":"data",
            "check": "reality2_data"
        }
    ],
    "message5":" - plugins %1",
    "args5":[
        {
            "type":"input_statement",
            "name":"plugins",
            "check": ["reality2_get_plugin", "reality2_post_plugin"]
        }
    ],
    "message6":" - automations %1",
    "args6":[
        {
            "type":"input_statement",
            "name":"automations",
            "check": "reality2_automation"
        }
    ],
    "previousStatement":null,
	"nextStatement":null,
    "colour": 50,
    "tooltip": "A Reality2 Sentient Digital Agent",
    "helpUrl": "https://github.com/reality-two/reality2-node-core-elixir/blob/f39e4ac1ef781632781fde73d8a7b4f3c2a52abf/docs/instructions/2%20Definitions/Sentants.md"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var sentant: any = {};

    sentant["name"] = block.getFieldValue('name');
    sentant["description"] = block.getFieldValue('description');

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
    if (sentant) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_sentant",
            "fields": {
                "name": R2.JSONPath(sentant, "name"),
                "description": R2.JSONPath(sentant, "description")
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

        console.log("PLUGINS: ", plugins);

        let plugins_block = plugins.reduce((acc, plugin) => {
            let method = R2.JSONPath(sentant, "plugin.method");
            let the_plugin: any;
            switch (method) {
                case "GET":
                    var plugin_block: any = reality2_get_plugin.construct(plugin);
                    if (plugin_block) {
                        the_plugin = plugin_block["plugin"];
                        the_plugin["next"] =  { "block": acc };
                    }
                    break;
                case "POST":
                    var plugin_block: any = reality2_post_plugin.construct(plugin);
                    if (plugin_block) {
                        the_plugin = plugin_block["plugin"];
                        the_plugin["next"] =  { "block": acc };
                    }
                    break;
                default:
                    the_plugin = acc;
                    break;
            };

            return the_plugin;
        }, {});

        console.log("PLUGINS: ", plugins_block);

        if (plugins_block) block["inputs"]["plugins"] = { "block": plugins_block };

        // Check if there are automations

        console.log("SENTANT:", block);
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