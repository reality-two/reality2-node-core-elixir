// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_plugin_header from "./reality2_plugin_header";
import reality2_plugin_body from "./reality2_plugin_body";


// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_post_plugin",
    "message0":"ANTENNA %1",
	"args0":[
		{
			"type":"field_input",
			"name":"name",
			"check":"String",
			"text":"name",
			"tooltip":"Antenna name in reverse DNS format eg: com.openai.api"
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
	"message2":"POST to %1 with",
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
	"message4":" - body %1",
	"args4":[
		{
			"type":"input_statement",
			"name":"body"
		}
	],
    "message5":"OUTPUT %1 = %2 with event %3",
	"args5":[
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
    "tooltip":"An antenna to retrieve information from an internet connected resource that uses a POST API.",
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
    plugin["method"] = "POST";

    const headers = generator.statementToCode(block, "headers");
    if (headers != "") {
        plugin["headers"] = splitConcatenatedJSON(headers);
    };

    const body = generator.statementToCode(block, "body");
    if (body != "") {
        plugin["body"] = splitConcatenatedJSON(body);
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
            "type": "reality2_post_plugin",
            "fields": {
                "name": R2.JSONPath(plugin, "name"),
                "description": description,
                "url": R2.JSONPath(plugin, "url"),
                "method": "POST",
                "output_key": R2.JSONPath(plugin, "output.key"),
                "output_value": R2.JSONPath(plugin, "output.value"),
                "output_event": R2.JSONPath(plugin, "output.event")
            },
            "inputs": {
                "headers": {},
                "body": {}
            }
        }

        // Check if there are headers
        let headers = reality2_plugin_header.construct(R2.JSONPath(plugin, "headers"));
        if (headers) block["inputs"]["headers"] = { "block": headers }

        // Check if there are body parameters
        let body = reality2_plugin_body.construct(R2.JSONPath(plugin, "body"));
        if (body) block["inputs"]["body"] = { "block": body }

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


