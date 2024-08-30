// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_data",
    "message0":"DATA",
	"message1":" - %1 = %2",
	"args1":[
		{
			"type":"field_input",
			"name":"key",
			"check":"String",
			"text":"key"
		},
		{
			"type":"field_input",
			"name":"value",
			"check":"String",
			"text":"value"
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 110
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const key = block.getFieldValue('key');
    const value = R2.convert(block.getFieldValue('value'), false);

    var return_value:any = {};
    return_value[key] = R2.convert(value, true);

    return (JSON.stringify(return_value));
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(data: any)
{
    console.log(data);
    let keys = Object.keys(data);
    if (keys.length > 0) {
        let block: any = {
            "kind": "BLOCK",
            "type": "reality2_key_value",
            "fields": {
                "key": keys[0],
                "value": R2.convert(R2.JSONPath(data, keys[0]))
            }
        }

        console.log(block);

        // Remove the key we've just been using
        delete data[keys[0]];

        // get any other keys, recursively
        if (Object.keys(data).length > 0)
        {
            let next = construct(data);
            if (next) {
                block["next"] = {
                    "block": next
                };
            }
        }

        // Return the structure
        return (block);
    }
    else
    {
        return null;
    }
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process, construct};
// ----------------------------------------------------------------------------------------------------