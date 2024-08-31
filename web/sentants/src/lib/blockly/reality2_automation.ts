// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";


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

    return JSON.stringify({"automation": automation});
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(automation: any)
{
    if (automation) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_automation",
            "fields": {
                "name": R2.JSONPath(automation, "name"),
                "description": R2.JSONPath(automation, "description")
            },
            "inputs": {
                "transitions": {}
            }
        }

        // Check if there are headers
        // let transitions = reality2_transition.construct(R2.JSONPath(automation, "transitions"));
        // if (transitions) block["inputs"]["transitions"] = { "block": transitions }

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