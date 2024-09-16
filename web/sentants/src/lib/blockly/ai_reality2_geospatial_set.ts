// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"ai_reality2_geospatial_set",
    "message0":"store latitude %1 and longitude %2",
	"args0":[
		{
			"type":"field_input",
			"name":"latitude",
			"check":"String",
			"text":""
		},
		{
			"type":"field_input",
			"name":"longitude",
			"check":"String",
			"text":""
		}
	],
    "message1":"OR geohash %1",
	"args1":[
		{
			"type":"field_input",
			"name":"geohash",
			"check":"String",
			"text":""
		}
	],
    "message2":"with optional altitude %1",
	"args2":[
		{
			"type":"field_input",
			"name":"altitude",
			"check":"String",
			"text":"0"
		}
	],
    "message3":"and privacy radius %1",
	"args3":[
		{
			"type":"field_input",
			"name":"radius",
			"check":"String",
			"text":"0"
		}
	],
    "message4": "use a radius of zero for 'completely public'.",
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300,
    "tooltip": "Store geospatial parameters on a Bee.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const latitude = R2.convert(block.getFieldValue('latitude'));
    const longitude = R2.convert(block.getFieldValue('longitude'));
    const geohash = block.getFieldValue('geohash');
    const altitude = R2.convert(block.getFieldValue('altitude'));
    const radius = R2.convert(block.getFieldValue('radius'));

    const action: any = {
        "plugin": "ai.reality2.geospatial",
        "command": "set",
        "parameters": {
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude,
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
            "type": "ai_reality2_geospatial_set",
            "fields": {
                "latitude": R2.JSONPath(action, "parameters.latitude"),
                "longitude": R2.JSONPath(action, "parameters.longitude"),
                "altitude": R2.JSONPath(action, "parameters.altitude"),
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