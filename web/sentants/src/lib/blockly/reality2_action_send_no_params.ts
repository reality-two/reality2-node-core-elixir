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
	"type":"reality2_action_send_no_params",
    "message0":"send %1 to %2 after %3 milliseconds",
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
			"text":""
        }
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 330,
    "tooltip": "Send an event after a delay.",
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
    const delay = R2.ToSimple(block.getFieldValue('delay'));

    const action:any  = {
        "command": "send",
        "parameters": {
            "event": event
        }
    }

    if (to) action["parameters"]["to"] = to;
    if (delay && (delay > 0)) action["parameters"]["delay"] = delay;

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
            "type": "reality2_action_send_no_params",
            "fields": {
                "event": R2.JSONPath(action, "parameters.event"),
                "to": to,
                "delay": (delay && (delay > 0)) ? delay : ""
            }
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