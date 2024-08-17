// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_automation",
    "message0":"name %1",
    "args0":[
        {
            "type":"field_input",
            "name":"name",
            "check":"String",
            "text":""
        }
    ],
    "message1":"description %1",
    "args1":[
        {
            "type":"field_input",
            "name":"description",
            "check":"String",
            "text":""
        }
    ],
    "message2":"transitions %1",
    "args2":[
        {
            "type":"input_statement",
            "name":"transitions",
            "check": "reality2_transition"
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
    var automation: any = {};

    automation["name"] = block.getFieldValue('name');
    automation["description"] = block.getFieldValue('description');

    const transitions = generator.statementToCode(block, "transitions");
    if (transitions != "") {
        automation["transitions"] = splitConcatenatedJSON(transitions);
    }

    return JSON.stringify(automation);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------