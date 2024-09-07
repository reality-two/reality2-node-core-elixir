// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_sentant from "./reality2_sentant";

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
			"name":"sentants",
            "check": ["reality2_sentant"]
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
        swarm["sentants"] = splitConcatenatedJSON(sentants, false).map((sentant: any) => { return (sentant["sentant"]) });
    };

    return JSON.stringify({"swarm":swarm});
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(swarm: any)
{
    let block = {
        "kind": "BLOCK",
        "type": "reality2_swarm",
        "fields": {
            "name": R2.JSONPath(swarm, "name"),
            "description": R2.JSONPath(swarm, "description")
        },
        "inputs": {
            "sentants": {}
        }
    }

    // Check if there are sentants
    let sentants: [any] = R2.JSONPath(swarm, "sentants");

    // If there are, go backwards through the array creating each block, and linking to the next
    if (sentants) {
        let sentants_block = sentants.reduceRight((acc, sentant) => {

            // Get a Sentant block
            let sentant_block: any = reality2_sentant.construct(sentant);
    
            // If the block is not empty, and the accumulator is also not empty, add it as the next.
            if (sentant_block && acc) {
                sentant_block["next"] = { "block": acc }
            }
    
            // accumulate the block so far
            return sentant_block;
        }, null);
    
        // Sentants starts as a block
        block["inputs"]["sentants"] = {"block": sentants_block};
    }

    return (block);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process, construct};
// ----------------------------------------------------------------------------------------------------


