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
	"type":"reality2_action_signal",
    "message0":"send %2 : %1 signal",
	"args0":[
        {
            "type":"field_dropdown",
            "name":"access",
            "options":[
                ["visible", "visible"],
                ["hidden", "hidden"]
            ],
            "tooltip":"Only public signals can be received by external Sentants and Devices."
        },
        {
			"type":"field_input",
			"name":"event",
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
    const public_var = block.getFieldValue('access') === "visible"
    const parameters = generator.statementToCode(block, "parameters");
    if (parameters !== "") {
       params = splitConcatenatedJSON(parameters);
    };

    const action: any = {
        "command": "signal",
        "parameters": {
            "event": event
        }
    }

    if (public_var) action["parameters"]["public"] = true;
    if (Object.keys(params).length !== 0) action["parameters"]["parameters"] = params;

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
            "type": "reality2_action_signal",
            "fields": {
                "event": R2.JSONPath(action, "parameters.event"),
                "access": access
            },
            "inputs": {
                "parameters": {}
            }
        }

        // Check if there are parameters
        let parameters = reality2_action_parameter.construct(R2.JSONPath(action, "parameters.parameters"));
        if (parameters) block["inputs"]["parameters"] = { "block": parameters };
        
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