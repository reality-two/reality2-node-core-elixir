// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_parameter from "./reality2_action_parameter";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_send_plugin_no_params",
    "message0":"send %1 to antenna %2",
	"args0":[
        {
			"type":"field_input",
			"name":"command",
			"check":"String",
			"text":""
        },
        {
			"type":"field_input",
			"name":"plugin",
			"check":"String",
			"text":""
        }
	],
	"previousStatement":null,
	"nextStatement":null,
    "colour": 330,
    "tooltip": "Send an event to an antenna.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var params = {};

    const plugin = block.getFieldValue('plugin');
    const command = block.getFieldValue('command');

    const action: any = {
        "command": command,
        "plugin": plugin
    }

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
            "type": "reality2_action_send_plugin",
            "fields": {
                "plugin": R2.JSONPath(action, "plugin"),
                "command": R2.JSONPath(action, "command")
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