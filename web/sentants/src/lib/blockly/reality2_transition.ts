// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_transition",
    "message0":"from %1",
    "args0":[
        {
            "type":"field_input",
            "name":"from",
            "check":"String",
            "text":""
        }
    ],
    "message1":"event %1",
    "args1":[
        {
            "type":"field_input",
            "name":"event",
            "check":"String",
            "text":""
        }
    ],
    "message2":"to %1",
    "args2":[
        {
            "type":"field_input",
            "name":"to",
            "check": "String",
            "text": ""
        }
    ],
    "message3":"actions %1",
    "args3":[
        {
            "type":"input_statement",
            "name":"actions",
            "check": "reality2_action"
        }
    ],
    "previousStatement":null,
	"nextStatement":null,
    "colour": 200
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var transition: any = {};

    transition["from"] = block.getFieldValue('from');
    transition["event"] = block.getFieldValue('event');
    transition["to"] = block.getFieldValue('to');

    // const transitions = generator.statementToCode(block, "transitions");
    // if (transitions != "") {
    //     transition["transitions"] = splitConcatenatedJSON(transitions);
    // }

    return JSON.stringify(transition);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------