// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_set_calc_binary from "./reality2_action_set_calc_binary";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_test_simple",
    "message0":"if %1 send %2",
	"args0":[
        {
			"type":"input_value",
			"name":"if"
		},
        {
			"type":"field_input",
			"name":"then",
			"check":"String",
			"text":""
		}
    ],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300,
    "tooltip": "Test the condition, and if true, send one event or send the other.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation",
    "inputsInline": true
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var params = {};

    const raw_if_param = generator.valueToCode(block, 'if', 99);
    const if_param = (raw_if_param === "" ? null : R2.JSONPath(R2.ToJSON(raw_if_param), "expr"));
    
    const then_param = block.getFieldValue('then');

    const action:any  = {
        "command": "test",
        "parameters": {
            "if": if_param,
            "then": then_param
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
        let to = R2.JSONPath(action, "parameters.to");

        let block = {
            "kind": "BLOCK",
            "type": "reality2_action_test_simple",
            "fields": {
                "then": R2.JSONPath(action, "parameters.then"),
                "to": (to === "") ? "me" : to
            },
            "inputs": {
                "if": {"block": reality2_action_set_calc_binary.construct(R2.JSONPath(action, "parameters.if"))}
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