// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_plugin_header from "./reality2_plugin_header";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_get_plugin",
    "message0":"ANTENNA %1",
	"args0":[
		{
			"type":"field_input",
			"name":"name",
			"check":"String",
			"text":"name",
			"tooltip":"Link name in reverse DNS format eg: com.openai.api"
		}
	],
    "message1":"%1",
    "args1":[
        {
            "type":"field_input",
            "name":"description",
            "check":"String",
            "text":"description"
        }
    ],
	"message2":"GET from %1 with",
	"args2":[
		{
			"type":"field_input",
			"name":"url",
			"check":"String",
			"text":"",
			"tooltip":"The full URL of the API"
		}
	],
	"message3":" - headers %1",
	"args3":[
		{
			"type":"input_statement",
			"name":"headers"
		}
	],
	"message4":"OUTPUT %1 = %2 with event %3",
	"args4":[
		{
			"type":"field_input",
			"name":"output_key",
			"check":"String",
			"text":""
		},
		{
			"type":"field_input",
			"name":"output_value",
			"check":"String",
			"text":"",
			"tooltip":"A JSONPath, for example choices.0.message.content"
		},
		{
			"type":"field_input",
			"name":"output_event",
			"check":"String",
			"text":""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
	"colour":150,
    "tooltip":"An antenna to get information from an internet connected resource that uses a GET API.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var plugin: any = {};

    plugin["name"] = block.getFieldValue('name');
    if (block.getFieldValue('description') !== "") plugin["description"] = block.getFieldValue('description');
    plugin["url"] = block.getFieldValue('url');
    plugin["method"] = "GET";

    const headers = generator.statementToCode(block, "headers");
    if (headers != "") {
        plugin["headers"] = splitConcatenatedJSON(headers);
    };

    plugin["output"] = {
        "key": block.getFieldValue('output_key'),
        "value": block.getFieldValue('output_value'),
        "event": block.getFieldValue('output_event')
    };

    return JSON.stringify({"plugin": plugin});
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(plugin: any)
{
    let description = R2.JSONPath(plugin, "description") ? R2.JSONPath(plugin, "description") : "";

    if (plugin) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_get_plugin",
            "fields": {
                "name": R2.JSONPath(plugin, "name"),
                "description": description,
                "url": R2.JSONPath(plugin, "url"),
                "method": "GET",
                "output_key": R2.JSONPath(plugin, "output.key"),
                "output_value": R2.JSONPath(plugin, "output.value"),
                "output_event": R2.JSONPath(plugin, "output.event")
            },
            "inputs": {
                "headers": {}
            }
        }

        // Check if there are headers
        let headers = reality2_plugin_header.construct(R2.JSONPath(plugin, "headers"));
        if (headers) block["inputs"]["headers"] = { "block": headers }

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