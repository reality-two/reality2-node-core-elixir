// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_set_data from "./reality2_action_set_data";
import reality2_action_set_jsonpath from "./reality2_action_set_jsonpath";
import reality2_action_set_value from "./reality2_action_set_value";
import reality2_action_set_calc_binary from "./reality2_action_set_calc_binary";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_set",
    "message0":"set %1 to %2",
	"args0":[
        {
			"type":"field_input",
			"name":"key",
			"check":"String",
			"text":""
		},
        {
			"type":"input_value",
			"name":"value",
			"check":"Json",
			"text":""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300,
    "tooltip": "Set a variable in the data flow.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const key = block.getFieldValue('key');
    const raw_value = generator.valueToCode(block, 'value', 99);

    const value = (raw_value === "" ? null : R2.ToJSON(raw_value));
    const action1 = {
        "command": "set",
        "parameters": {
            "key": key,
            "value": value
        }
    }

    return (JSON.stringify(action1));
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
            "type": "reality2_action_set",
            "fields": {
                "key": R2.JSONPath(action, "parameters.key")
            },
            "inputs": {
                "value": {}
            }
        }

        if (R2.JSONPath(action, "parameters.value.data"))
        {
            block["inputs"]["value"] = {"block": reality2_action_set_data.construct(R2.JSONPath(action, "parameters.value"))};
        }
        else if (R2.JSONPath(action, "parameters.value.jsonpath"))
        {
            block["inputs"]["value"] = {"block": reality2_action_set_jsonpath.construct(R2.JSONPath(action, "parameters.value"))};
        }
        else if (R2.JSONPath(action, "parameters.value.expr"))
        {
            block["inputs"]["value"] = {"block": reality2_action_set_calc_binary.construct(R2.JSONPath(action, "parameters.value.expr"))};
        }
        else
        {
            block["inputs"]["value"] = {"block": reality2_action_set_value.construct(R2.JSONPath(action, "parameters.value"))};
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