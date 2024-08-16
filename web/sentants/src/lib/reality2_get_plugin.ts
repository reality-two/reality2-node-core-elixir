// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_get_plugin",
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
			"name":"description",
			"check":"String",
			"text":"description",
			"tooltip":"A short decription of the plugin"
		}
	],
	"message2":"headers: %1",
	"args2":[
		{
			"type":"input_statement",
			"name":"headers"
		}
	],
	"message3":"output: send %1 = %2 with event %3",
	"args3":[
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
    console.log(headers);
    if (headers != "") {
        var multiple_headers: any = splitConcatenatedJsonObjects(headers);
        plugin["headers"] = multiple_headers.map((header: any) => JSON.parse(header))
    }

    console.log(plugin);
    console.log(JSON.stringify(plugin));

    return JSON.stringify(plugin);
}
// ----------------------------------------------------------------------------------------------------
function splitConcatenatedJsonObjects(concatenatedString: String): RegExpMatchArray|[]|[String]
{
    const matches = concatenatedString.match(/\{[^{}]*\}/g);
    return (!matches ? [concatenatedString] : matches);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------