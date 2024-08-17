// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_post_plugin",
	"message0":"name: %1",
	"args0":[
		{
			"type":"field_input",
			"name":"name",
			"check":"String",
			"text":"name",
			"tooltip":"Plugin name in reverse DNS format eg: com.openai.api"
		}
	],
	"message1":"description: %1",
	"args1":[
		{
			"type":"field_input",
			"name":"url",
			"check":"String",
			"text":"url",
			"tooltip":"Full URL including http:// or https://"
		}
	],
	"message2":"headers: %1",
	"args2":[
		{
			"type":"input_statement",
			"name":"headers"
		}
	],
	"message3":"body: %1",
	"args3":[
		{
			"type":"input_statement",
			"name":"body"
		}
	],
	"message4":"output: send %1 = %2 with event %3",
	"args4":[
		{
			"type":"field_input",
			"name":"output_key",
			"check":"String",
			"text":"key"
		},
		{
			"type":"field_input",
			"name":"output_value",
			"check":"String",
			"text":"value",
			"tooltip":"A JSONPath, for example choices.0.message.content"
		},
		{
			"type":"field_input",
			"name":"output_event",
			"check":"String",
			"text":"event"
		}
	],
	"previousStatement":null,
	"nextStatement":null,
	"colour":100
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var plugin: any = {};

    plugin["name"] = block.getFieldValue('name');
    plugin["description"] = block.getFieldValue('description');

    const headers = generator.statementToCode(block, "headers");
    if (headers != "") {
        plugin["headers"] = splitConcatenatedJSON(headers);
    };

    const body = generator.statementToCode(block, "body");
    if (body != null) {
        plugin["body"] = {};
    }

    plugin["output"] = {
        "key": block.getFieldValue('output_key'),
        "value": block.getFieldValue('output_value'),
        "event": block.getFieldValue('output_event')
    };

    return JSON.stringify(plugin);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------


