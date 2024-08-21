// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_automation",
    "message0":"AUTOMATION",
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
    "message3":" - transitions %1",
    "args3":[
        {
            "type":"input_statement",
            "name":"transitions",
            "check": "reality2_transition"
        }
    ],
    "previousStatement":null,
	"nextStatement":null,
    "colour": 200,
    "tooltip": "An automation, which is a type of Finite State Machine",
    "helpUrl": "https://github.com/reality-two/reality2-node-core-elixir/blob/f39e4ac1ef781632781fde73d8a7b4f3c2a52abf/docs/instructions/2%20Definitions/Automations.md"
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
        automation["transitions"] = splitConcatenatedJSON(transitions, false);
    }

    return JSON.stringify(automation);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------