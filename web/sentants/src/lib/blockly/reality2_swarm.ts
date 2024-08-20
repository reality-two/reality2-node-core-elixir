// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_swarm",
    "message0": "SWARM",
	"message1": " - name %1",
	"args1":[
		{
			"type":"field_input",
			"name":"name",
			"check":"String",
			"text":"",
			"tooltip":"Name of Swarm"
		}
	],
	"message2":" - description %1",
	"args2":[
		{
			"type":"field_input",
			"name":"description",
			"check":"String",
			"text":"",
			"tooltip":"Swarm description"
		}
	],
	"message3":" - sentants %1",
	"args3":[
		{
			"type":"input_statement",
			"name":"sentants"
		}
	],
	"colour":20
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var swarm: any = {};

    swarm["name"] = block.getFieldValue('name');
    swarm["description"] = block.getFieldValue('description');

    const sentants = generator.statementToCode(block, "sentants");
    if (sentants != "") {
        swarm["sentants"] = splitConcatenatedJSON(sentants);
    };

    return JSON.stringify(swarm);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------


