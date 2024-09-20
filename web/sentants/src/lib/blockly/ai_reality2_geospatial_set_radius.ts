// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"ai_reality2_geospatial_set_radius",
    "message0":"set radius %1",
	"args0":[
		{
			"type":"field_input",
			"name":"radius",
			"check":"String",
			"text":"0"
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 360,
    "tooltip": "Set a radius of privacy for a location.  Seeker has to be within the radius in order to find this Bee.  A (default) value of zero (0) means no radius used.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    // const geohash = block.getFieldValue('geohash');
    const radius = R2.convert(block.getFieldValue('radius'));

    // const action: any = {
    //     "plugin": "ai.reality2.geospatial",
    //     "command": "set",
    //     "parameters": {
    //         "radius": radius
    //     }
    // };

    const action = {
        "command": "set",
        "parameters": {
            "key": "radius",
            "value": radius
        }
    }

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
            "type": "ai_reality2_geospatial_set_radius",
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