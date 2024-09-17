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
	"type":"reality2_action_send_now",
    "message0":"send %1 to %2",
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
    "colour": 300,
    "tooltip": "Send an event with some additional information to add to the data flow.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
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
    const parameters = generator.statementToCode(block, "parameters");
    if (parameters !== "") {
       params = splitConcatenatedJSON(parameters);
    };

    const action:any  = {
        "command": "send",
        "parameters": {
            "event": event
        }
    }

    if (to) action["parameters"]["to"] = to;
    if (Object.keys(params).length !== 0) action["parameters"]["parameters"] = params;

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
        let delay = R2.ToSimple(R2.JSONPath(action, "parameters.delay"));
        let to = R2.JSONPath(action, "parameters.to");

        let block = {
            "kind": "BLOCK",
            "type": "reality2_action_send_now",
            "fields": {
                "event": R2.JSONPath(action, "parameters.event"),
                "to": to
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