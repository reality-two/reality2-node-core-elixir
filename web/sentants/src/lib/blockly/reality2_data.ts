

// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

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
    const value = block.getFieldValue('value');

    return ("{\"" + key + "\":\"" + value + "\"}")
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------