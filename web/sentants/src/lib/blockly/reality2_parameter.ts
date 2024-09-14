

// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_parameter",
    "message0":"input %1 as %2",
	"args0":[
		{
			"type":"field_input",
			"name":"parameter",
			"check":"String",
			"text":""
		},
        {
            "type":"field_dropdown",
            "name":"type",
            "options":[
                ["number", "number"],
                ["string", "string"],
                ["boolean", "boolean"],
                ["json", "json"]
            ],
            "tooltip":"Various parameter types"
        }
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 250,
    "tooltip": "Additional information to add to the data flow.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const parameter = block.getFieldValue('parameter');
    const type = block.getFieldValue('type');

    return ("{\"" + parameter + "\":\"" + type + "\"}")
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(parameters: any)
{
    if (parameters) {
        let keys = Object.keys(parameters);
        if (keys.length > 0) {
            let param_name = keys[0];
            let param_type = R2.JSONPath(parameters, param_name);

            let block: any = {
                "kind": "BLOCK",
                "type": "reality2_parameter",
                "fields": {
                    "parameter": param_name,
                    "type": param_type
                }
            }
    
            // Remove the key we've just been using
            delete parameters[keys[0]];
    
            // get any other keys, recursively
            let next = construct(parameters);
            if (next) {
                block["next"] = {
                    "block": next
                };
            }
    
            // Return the structure
            return (block);
        }
        else
        {
            return null;
        }
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