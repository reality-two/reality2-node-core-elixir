// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_plugin_header",
	"message0":"%1 = %2",
	"args0":[
		{
			"type":"field_input",
			"name":"key",
			"check":"String",
			"text":"key"
		},
		{
			"type":"field_input",
			"name":"value",
			"check":"String",
			"text":"value"
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
    const key = block.getFieldValue('key');
    const value = block.getFieldValue('value');

    return ("{\"" + key + "\":\"" + value + "\"}")
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Export defaults
// ----------------------------------------------------------------------------------------------------
export default {shape, process};
// ----------------------------------------------------------------------------------------------------
