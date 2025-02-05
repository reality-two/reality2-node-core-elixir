// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_plugin_parameter",
    "message0":"param %1 = %2",
	"args0":[
		{
			"type":"field_input",
			"name":"parameter",
			"check":"String",
			"text":""
		},
		{
			"type":"field_input",
			"name":"data",
			"check":"String",
			"text":""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
	"colour":150,
    "tooltip": "Some APIs use query parameters after the question mark.  Check with the API definition help pages.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const parameter = block.getFieldValue('parameter');
    const data = R2.ToJSON(block.getFieldValue('data'));

    var return_value:any = {};
    return_value[parameter] = data;

    return (JSON.stringify(return_value));
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(data: any)
{
    if (data) {
        let keys = Object.keys(data);
        if (keys.length > 0) {
            let block: any = {
                "kind": "BLOCK",
                "type": "reality2_plugin_parameter",
                "fields": {
                    "parameter": keys[0],
                    "data": R2.ToSimple(R2.JSONPath(data, keys[0]))
                }
            }
    
            // Remove the key we've just been using
            delete data[keys[0]];
    
            // get any other keys, recursively
            let next = construct(data);
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
