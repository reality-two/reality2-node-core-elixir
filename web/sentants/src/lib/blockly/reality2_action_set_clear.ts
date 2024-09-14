// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_set_data from "./reality2_action_set_data";
import reality2_action_set_jsonpath from "./reality2_action_set_jsonpath";
import reality2_action_set_value from "./reality2_action_set_value";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_set_clear",
    "message0":"clear %1",
	"args0":[
        {
			"type":"field_input",
			"name":"key",
			"check":"String",
			"text":""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300,
    "tooltip": "Remove a variable from the data flow.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const key = block.getFieldValue('key');

    const action = {
        "command": "set",
        "parameters": {
            "key": key
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
            "type": "reality2_action_set_clear",
            "fields": {
                "key": R2.JSONPath(action, "parameters.key")
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