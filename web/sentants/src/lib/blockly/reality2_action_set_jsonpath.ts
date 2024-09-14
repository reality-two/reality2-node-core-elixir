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
    "message0":"jsonpath %1",
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
    "tooltip": "A JSON Path, which is a string used to pick data out of a JSON stucture.  For example 'information.[].name' returns and array of names from the information array, whilst 'information.0.name' returns the name of the first element of the information array.  If the JSON key doesn't exist, null is returned.",
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
        "jsonpath": value
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
            "type": "reality2_action_set_jsonpath",
            "fields": {
                "value": R2.ToSimple(R2.JSONPath(data, "jsonpath"))
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