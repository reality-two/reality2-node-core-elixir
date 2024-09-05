// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_set from "./reality2_action_set";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_transition",
    "message0":"TRANSITION",
    "message1":"%1 :: %2 :  %3 => %4",
    "args1":[
        {
            "type":"field_dropdown",
            "name":"access",
            "options":[
                ["public", "public"],
                ["private", "private"]
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
    "message2":" - parameters %1",
    "args2":[
        {
            "type":"input_statement",
            "name":"parameters",
            "check":"reality_parameter"
        }
    ],
    "message3":" - actions %1",
    "args3":[
        {
            "type":"input_statement",
            "name":"actions",
            "check": "reality2_action"
        }
    ],
    "previousStatement":null,
	"nextStatement":null,
    "colour": 250,
    "tooltip":"A Transition  which signifies a state change given an event.",
    "helpUrl":"https://github.com/reality-two/reality2-node-core-elixir/blob/f39e4ac1ef781632781fde73d8a7b4f3c2a52abf/docs/instructions/2%20Definitions/Automations.md"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var transition: any = {};

    transition["public"] = block.getFieldValue('access') === "public"
    transition["from"] = block.getFieldValue('from');
    transition["event"] = block.getFieldValue('event');
    transition["to"] = block.getFieldValue('to');

    const parameters = generator.statementToCode(block, "parameters");
    if (parameters != "") {
        transition["parameters"] = splitConcatenatedJSON(parameters);
    };

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
            "type": "reality2_transition",
            "fields": {
                "from": R2.JSONPath(transition, "from"),
                "event": R2.JSONPath(transition, "event"),
                "to": R2.JSONPath(transition, "to")
            },
            "inputs": {
                "parameters": {},
                "actions": {}
            }
        }

        // Check if there are parameters




        // Check if there are actions
        let actions: [any] = R2.JSONPath(transition, "actions");

        // If there are, go backwards through the array creating each block, and linking to the next
        if (actions) {
            let actions_block = actions.reduceRight((acc, action) => {

                let command = action["command"];

                let action_block: any;

                switch (command) {
                    case "set":
                        action_block = reality2_action_set.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        }
                        break;
                    case "send":
                        break;
                    case "signal":
                        break;
                    case "debug":
                        break;
                }
        
                // accumulate the block so far
                return action_block;
            }, null);
        
            // Sentants starts as a block
            block["inputs"]["actions"] = {"block": actions_block};
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