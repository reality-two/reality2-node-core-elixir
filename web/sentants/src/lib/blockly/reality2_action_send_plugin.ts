// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_send_plugin",
    "message0":"ACTION - PLUGIN",
	"message1":" - send to %1",
	"args1":[
        {
			"type":"field_input",
			"name":"plugin",
			"check":"String",
			"text":""
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
    "colour": 350
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var params = {};

    const plugin = block.getFieldValue('plugin');
    const parameters = generator.statementToCode(block, "parameters");
    if (parameters !== "") {
       params = splitConcatenatedJSON(parameters);
    };

    const action = {
        "command": "send",
        "plugin": plugin,
        "parameters": params
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
            "type": "reality2_action_send_plugin",
            "fields": {
                "plugin": R2.JSONPath(action, "plugin")
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