// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_signal_no_params",
    "message0":"signal %1",
	"args0":[
        {
			"type":"field_input",
			"name":"event",
			"check":"String",
			"text":""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 330,
    "tooltip": "Send a signal to any connected devices.",
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

    const action: any = {
        "command": "signal",
        "parameters": {
            "event": event,
            "public": true
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
    let access = "private";
    if ((R2.JSONPath(action, "parameters.public") === true) || (R2.JSONPath(action, "public") === true)) access = "public";

    if (action) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_action_signal_no_params",
            "fields": {
                "event": R2.JSONPath(action, "parameters.event")
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