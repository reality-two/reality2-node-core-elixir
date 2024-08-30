// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";
import reality2_key_value from "./reality2_key_value";


// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_encrypt_decrypt_keys",
    "message0":"ENCRYPTION",
	"message1":" - encryption key = %1",
	"args1":[
		{
			"type":"field_input",
			"name":"encryption_key",
			"check":"String",
			"text":""
		}
	],
	"message2":" - decryption key = %1",
	"args2":[
		{
			"type":"field_input",
			"name":"decryption_key",
			"check":"String",
			"text":""
		}
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 80
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const encryption_key = block.getFieldValue('encryption_key');
    const decryption_key = block.getFieldValue('decryption_key');

    return JSON.stringify({"encryption_key": encryption_key, "decryption_key": decryption_key})
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(data: any)
{
    if (data) {
        // Get the encryption and decryption keys if they are there, then remove them
        const encryption_key = R2.JSONPath(data, "encryption_key");
        if (encryption_key) delete data.encryption_key;
        const decryption_key = R2.JSONPath(data, "decryption_key");
        if (decryption_key) delete data.decryption_key;

        let block: any = {
            "kind": "BLOCK",
            "type": "reality2_encrypt_decrypt_keys",
            "fields": {
                "encryption_key": encryption_key,
                "decryption_key": decryption_key
            }
        }

        // get any other keys
        if (Object.keys(data).length > 0)
        {
            let next = reality2_key_value.construct(data);
            if (next) {
                block["next"] = {
                    "block": next
                };
            }
        }

        return(block);
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