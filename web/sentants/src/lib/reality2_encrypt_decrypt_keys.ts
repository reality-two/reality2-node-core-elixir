// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_encrypt_decrypt_keys",
	"message0":"encryption key = %1",
	"args0":[
		{
			"type":"field_input",
			"name":"encryption_key",
			"check":"String",
			"text":"data"
		}
	],
	"message1":"decryption key = %1",
	"args1":[
		{
			"type":"field_input",
			"name":"decryption_key",
			"check":"String",
			"text":"data"
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
    const encryption_key = block.getFieldValue('encryption_key');
    const decryption_key = block.getFieldValue('decryption_key');

    return JSON.stringify({"__encryption_key__": encryption_key, "__decryption_key__": decryption_key})
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