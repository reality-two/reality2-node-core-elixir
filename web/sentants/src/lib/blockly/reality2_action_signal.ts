// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_signal",
    "message0":"SIGNAL",
	"message1":" - %1 signal %2 to %3",
	"args1":[
        {
            "type":"field_dropdown",
            "name":"access",
            "options":[
                ["public", "public"],
                ["private", "private"]
            ],
            "tooltip":"Only public events can be triggered by external Sentants."
        },
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
    "message2":" - parameters %1",
    "args2":[
        {
            "type":"input_statement",
            "name":"parameters",
            "check":"reality2_parameter"
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
    const public_var = block.getFieldValue('access') === "public"
    const parameters = generator.statementToCode(block, "parameters");
    if (parameters !== "") {
       params = splitConcatenatedJSON(parameters);
    };

    const action = {
        "command": "signal",
        "parameters": {
            "public": public_var,
            "event": event,
            "to": to,
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
            "type": "reality2_action_signal",
            "fields": {
                "event": R2.JSONPath(action, "parameters.event"),
                "to": R2.JSONPath(action, "parameters.to"),
                "public": R2.JSONPath(action, "public") === null ? (R2.JSONPath(action, "parameters.public") === true) : (R2.JSONPath(action, "public") === true)
            },
            "inputs": {
                "parameters": {}
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