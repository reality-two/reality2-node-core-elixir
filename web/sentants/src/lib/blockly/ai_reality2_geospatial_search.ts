// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"ai_reality2_geospatial_search",
    "message0":"search within radius %1",
	"args0":[
		{
			"type":"field_input",
			"name":"radius",
			"check":"Number",
			"text": ""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 360,
    "tooltip": "Search for Bees within the given radius of this Bee (in meters) and return an array of those that are nearby in the 'to' variable.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const radius = R2.convert(block.getFieldValue('radius'));

    const action: any = {
        "plugin": "ai.reality2.geospatial",
        "command": "search"
    };

    if (radius) action["parameters"] = { "radius": radius };

    return (JSON.stringify(action));
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(action: any)
{
    if (action) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "ai_reality2_geospatial_search",
            "fields": {
                "radius": R2.JSONPath(action, "parameters.radius")
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