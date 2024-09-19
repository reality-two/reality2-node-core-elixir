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
	"type":"reality2_action_test",
    "message0":"if %1",
	"args0":[
        {
			"type":"field_input",
			"name":"if",
			"check":"String",
			"text":""
		}
    ],
    "message1":"send event %1",
    "args1":[
        {
			"type":"field_input",
			"name":"then",
			"check":"String",
			"text":""
		}
    ],
    "message2":"otherwise send event %1",
    "args2":[
        {
			"type":"field_input",
			"name":"else",
			"check":"String",
			"text":""
        }
    ],
    "message3":"to %1",
    "args3": [
        {
			"type":"field_input",
			"name":"to",
			"check":"String",
			"text":""
        }
	],
    "message4":"with %1",
    "args4":[
        {
            "type":"input_statement",
            "name":"parameters",
            "check":"reality2_action_parameter"
        }
    ],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300,
    "tooltip": "Test the condition, and if true, send one event or send the other.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var params = {};

    const if_param = block.getFieldValue('if');
    const then_param = block.getFieldValue('then');
    const else_param = block.getFieldValue('else');
    const to = block.getFieldValue('to');

    const parameters = generator.statementToCode(block, "parameters");
    if (parameters !== "") {
       params = splitConcatenatedJSON(parameters);
    };

    const action:any  = {
        "command": "test",
        "parameters": {
            "if": if_param,
            "then": then_param
        }
    }

    if (else_param !== "") action["parameters"]["else"] = else_param;
    if ((to !== "") && (to !== "me")) action["parameters"]["to"] = to;
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
        let to = R2.JSONPath(action, "parameters.to");

        let block = {
            "kind": "BLOCK",
            "type": "reality2_action_test",
            "fields": {
                "if": R2.JSONPath(action, "parameters.if"),
                "then": R2.JSONPath(action, "parameters.then"),
                "else": R2.JSONPath(action, "parameters.else"),
                "to": (to === "") ? "me" : to,
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