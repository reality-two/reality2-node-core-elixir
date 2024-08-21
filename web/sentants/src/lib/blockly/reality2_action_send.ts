// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_send",
    "message0":"ACTION - SEND",
	"message1":" - send %1 to %2 after %3 seconds",
	"args1":[
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
    "message2":" - parameters %1",
    "args2":[
        {
            "type":"input_statement",
            "name":"parameters",
            "check":"reality_parameter"
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
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------