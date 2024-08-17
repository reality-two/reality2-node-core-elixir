// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_sentant",
    "message0":"name %1",
    "args0":[
        {
            "type":"field_input",
            "name":"name",
            "check":"String",
            "text":"Sentant Name"
        }
    ],
    "message1":"description %1",
    "args1":[
        {
            "type":"field_input",
            "name":"description",
            "check":"String",
            "text":"A brief description"
        }
    ],
    "message2":"keys %1",
    "args2":[
        {
            "type":"input_statement",
            "name":"keys",
            "check": "reality2_encrypt_decrypt_keys"
        }
    ],
    "message3":"plugins %1",
    "args3":[
        {
            "type":"input_statement",
            "name":"plugins",
            "check": ["reality2_get_plugin", "reality2_post_plugin"]
        }
    ],
    "message4":"automations %1",
    "args4":[
        {
            "type":"input_statement",
            "name":"automations",
            "check": "reality2_automation"
        }
    ],
    "colour": 50
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
        var multiple_keys: any = splitConcatenatedJSON(keys);
        sentant["keys"] = multiple_keys[0];
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