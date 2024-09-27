// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_set_calculation",
    "message0":"calc %1",
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
    "tooltip": "An expression in a string in reverse polish format.  So to add 1 and 2, for example, that would '1 2 +'.  To add 1 and 2, then multiply by 3 would be '1 2 + 3 *'.  Numbers from the data flow can be used by putting two underscores on either side, for example: '__answer__'.  Therefore, to add 2 to 'answer' would be 'answer 2 +'",
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

    const action = {
        "expr": value
    }
    
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
            "type": "reality2_action_set_calculation",
            "fields": {
                "value": R2.ToSimple(R2.JSONPath(data, "expr"))
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