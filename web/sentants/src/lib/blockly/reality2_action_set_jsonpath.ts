// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_set_jsonpath",
    "message0":"set %1 to jsonpath %2",
	"args0":[
        {
			"type":"field_input",
			"name":"key",
			"check":"String",
			"text":""
		},
        {
			"type":"field_input",
			"name":"value",
			"check":"String",
			"text":""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300,
    "inputsInline": true
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const key = block.getFieldValue('key');
    const raw_value = block.getFieldValue('value');

    const value = (raw_value === "" ? null : R2.ToJSON(raw_value));
    const action = {
        "command": "set",
        "parameters": {
            "key": key,
            "value": {
                "jsonpath": value
            }
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
            "type": "reality2_action_set_jsonpath",
            "fields": {
                "key": R2.JSONPath(action, "parameters.key"),
                "value": R2.ToSimple(R2.JSONPath(action, "parameters.value.jsonpath"))
            },
            "inputs": {
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