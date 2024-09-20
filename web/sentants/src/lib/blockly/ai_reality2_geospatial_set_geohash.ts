// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"ai_reality2_geospatial_set_geohash",
    "message0":"store geohash %1",
	"args0":[
		{
			"type":"field_input",
			"name":"geohash",
			"check":"String",
			"text":""
		}
	],
    "message1":"with privacy radius %1",
	"args1":[
		{
			"type":"field_input",
			"name":"radius",
			"check":"String",
			"text":"0"
		}
	],
    "message2": "use a radius of zero for 'completely public'.",
	"previousStatement":null,
	"nextStatement":null,
    "colour": 360,
    "tooltip": "Store geospatial parameters on a Bee.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const geohash = block.getFieldValue('geohash');
    const radius = R2.convert(block.getFieldValue('radius'));

    const action: any = {
        "plugin": "ai.reality2.geospatial",
        "command": "set",
        "parameters": {
            "geohash": geohash,
            "radius": radius
        }
    };

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
            "type": "ai_reality2_geospatial_set_geohash",
            "fields": {
                "geohash": R2.JSONPath(action, "parameters.geohash"),
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