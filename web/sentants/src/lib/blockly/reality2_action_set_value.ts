// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_set_value",
    "message0":"%1",
	"args0":[
        {
			"type":"field_input",
			"name":"value",
			"check":"String",
			"text":""
		}
	],
    "colour": 300,
    "output":"Json",
    "tooltip": "A value, which can be a number, a string or JSON.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number]
{
    const raw_value = block.getFieldValue('value');

    const value = (raw_value === "" ? null : R2.ToJSON(raw_value));

    const action = value;

    return [JSON.stringify(action), 99];
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(data: any)
{
    if (data) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_action_set_value",
            "fields": {
                "value": R2.ToSimple(data)
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