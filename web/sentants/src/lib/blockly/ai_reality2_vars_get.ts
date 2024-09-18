// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"ai_reality2_vars_get",
    "message0":"fetch %1",
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
    "colour": 360,
    "tooltip": "Fetch a persistent variable.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const key = block.getFieldValue('key');

    const action: any = {
        "plugin": "ai.reality2.vars",
        "command": "get",
        "parameters": {
            "key": key
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
            "type": "ai_reality2_vars_get",
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