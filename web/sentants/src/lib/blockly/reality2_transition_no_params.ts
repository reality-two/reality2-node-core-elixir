// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON, interpret_actions } from "./blockly_common";
import R2 from "../reality2";
import reality2_parameter from "./reality2_parameter";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_transition_no_params",
    "message0":"in state %2 when %3 : %1 happens, go to %4",
    "args0":[
        {
            "type":"field_dropdown",
            "name":"access",
            "options":[
                ["visible", "visible"],
                ["internal", "internal"]
            ],
            "tooltip":"Only public events can be triggered by external Sentants."
        },
        {
            "type":"field_input",
            "name":"from",
            "check":"String",
            "text":"",
            "tooltip":"from"
        },
        {
            "type":"field_input",
            "name":"event",
            "check":"String",
            "text":"",
            "tooltip":"event"
        },
        {
            "type":"field_input",
            "name":"to",
            "check": "String",
            "text": "",
            "tooltip":"to"
        }
    ],
    "message1":"TASKS",
    "message2":"%1",
    "args2":[
        {
            "type":"input_statement",
            "name":"actions",
            "check": ["reality2_action_debug", "reality2_action_send", "reality2_action_send_plugin", "reality2_action_set", "reality2_action_signal"]
        }
    ],
    "previousStatement":null,
	"nextStatement":null,
    "colour": 270,
    "tooltip":"When a Bee is in a particular state, and it receives notice that something has happened, it goes to a new state, and performs some tasks.  For example, a switch may be off, then be told to 'turn on', whereupon it goes into the on state.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var transition: any = {};

    if (block.getFieldValue('access') === "visible") transition["public"] = true;
    transition["from"] = block.getFieldValue('from');
    transition["event"] = block.getFieldValue('event');
    transition["to"] = block.getFieldValue('to');

    const actions = generator.statementToCode(block, "actions");

    if (actions != "") {
        transition["actions"] = splitConcatenatedJSON(actions, false);
    }

    return JSON.stringify(transition);
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(transition: any)
{
    if (transition) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_transition_no_params",
            "fields": {
                "access": R2.JSONPath(transition, "public") ? "visible" : "internal",
                "from": R2.JSONPath(transition, "from"),
                "event": R2.JSONPath(transition, "event"),
                "to": R2.JSONPath(transition, "to")
            },
            "inputs": {
                "actions": {}
            }
        }

        return (interpret_actions(transition, block));
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