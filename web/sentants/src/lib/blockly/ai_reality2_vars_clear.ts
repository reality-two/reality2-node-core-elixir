// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// -------ai.reality2.vars_set---------------------------------------------------------------------------------------------
const shape = {
	"type":"ai_reality2_vars_clear",
    "message0":"clear all",
	"previousStatement":null,
	"nextStatement":null,
    "colour": 300,
    "tooltip": "Clears all the persistent variables for this Bee.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    const key = block.getFieldValue('key');

    const action: any = {
        "plugin": "ai.reality2.vars",
        "command": "clear"
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
            "type": "ai_reality2_vars_clear"
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