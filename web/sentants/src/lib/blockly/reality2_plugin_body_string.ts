// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_plugin_body_string",
    "message0":"body %1",
    "args0":[
        {
            "type":"field_input",
            "name":"body_string",
            "check":"String",
            "text":""
        }
    ],
    "previousStatement":null,
    "nextStatement":null,
    "colour": 150,
    "tooltip": "When defining a POST antenna, often there are data to be sent as the body of the API call.  Check with the API definition help pages.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const body_string = block.getFieldValue('body_string');

    return (body_string);
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
            "type": "reality2_plugin_body_string",
            "fields": {
                "body_string": R2.ToSimple(data)
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