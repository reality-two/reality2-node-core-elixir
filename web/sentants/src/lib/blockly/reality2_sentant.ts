// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

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

    const keys = generator.statementToCode(block, "keys");
    if (keys != "") {
        sentant["keys"] = splitConcatenatedJSON(keys);
    }

    const data = generator.statementToCode(block, "data");
    if (data != "") {
        sentant["data"] = splitConcatenatedJSON(data);
    }

    const plugins = generator.statementToCode(block, "plugins");
    if (plugins != "") {
        sentant["plugins"] = splitConcatenatedJSON(plugins);
    }

    const automations = generator.statementToCode(block, "automations");
    if (automations != "") {
        sentant["automations"] = splitConcatenatedJSON(automations);
    }

    return JSON.stringify(sentant);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------