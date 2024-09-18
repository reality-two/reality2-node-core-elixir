// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"ai_reality2_vars_set",
    "message0":"store %1 as %2",
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
    "colour": 360,
    "tooltip": "Store a persistent variable.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const key = block.getFieldValue('key');
    const value = R2.convert(block.getFieldValue('value'));

    const action: any = {
        "plugin": "ai.reality2.vars",
        "command": "set",
        "parameters": {
            "key": key,
            "value": value
        }
    };

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
            "type": "ai_reality2_vars_set",
            "fields": {
                "key": R2.JSONPath(action, "parameters.key"),
                "value": R2.JSONPath(action, "parameters.value")
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