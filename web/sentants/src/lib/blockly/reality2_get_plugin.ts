// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_get_plugin",
	"message0":"name %1",
	"args0":[
		{
			"type":"field_input",
			"name":"name",
			"check":"String",
			"text":"",
			"tooltip":"Plugin name in reverse DNS format eg: com.openai.api"
		}
	],
	"message1":"url %1",
	"args1":[
		{
			"type":"field_input",
			"name":"url",
			"check":"String",
			"text":"",
			"tooltip":"The full URL of the API"
		}
	],
	"message2":"headers %1",
	"args2":[
		{
			"type":"input_statement",
			"name":"headers"
		}
	],
	"message3":"output send %1 = %2 with event %3",
	"args3":[
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

    return JSON.stringify(plugin);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------