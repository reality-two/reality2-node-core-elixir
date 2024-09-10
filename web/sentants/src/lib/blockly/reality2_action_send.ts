// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_parameter from "./reality2_action_parameter";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_send",
    "message0":"send %1 to %2 after %3 seconds",
	"args0":[
        {
			"type":"field_input",
			"name":"event",
			"check":"String",
			"text":""
		},
        {
			"type":"field_input",
			"name":"to",
			"check":"String",
			"text":""
		},
        {
			"type":"field_input",
			"name":"delay",
			"check":"Number",
			"text":"0"
        }
	],
    "message1":"with %1",
    "args1":[
        {
            "type":"input_statement",
            "name":"parameters",
            "check":"reality2_action_parameter"
        }
    ],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var params = {};

    const event = block.getFieldValue('event');
    const to = block.getFieldValue('to');
    const delay = block.getFieldValue('delay');
    const parameters = generator.statementToCode(block, "parameters");
    if (parameters !== "") {
       params = splitConcatenatedJSON(parameters);
    };

    const action = {
        "command": "send",
        "parameters": {
            "event": event,
            "to": to,
            "delay": delay,
            "parameters": params
        }
    }

    return (JSON.stringify(action));
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(action: any)
{
    if (action) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_action_send",
            "fields": {
                "event": R2.JSONPath(action, "parameters.event"),
                "to": R2.JSONPath(action, "parameters.to"),
                "delay": R2.JSONPath(action, "parameters.delay")
            },
            "inputs": {
                "parameters": {}
            }
        }

        // Check if there are parameters
        let parameters = reality2_action_parameter.construct(R2.JSONPath(action, "parameters.parameters"));
        if (parameters) block["inputs"]["parameters"] = { "block": parameters }

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