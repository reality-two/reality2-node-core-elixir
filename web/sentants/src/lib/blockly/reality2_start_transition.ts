// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_set from "./reality2_action_set";
import reality2_action_debug from "./reality2_action_debug";
import reality2_action_send from "./reality2_action_send";
import reality2_action_send_now from "./reality2_action_send_now";
import reality2_action_send_plugin from "./reality2_action_send_plugin";
import reality2_action_signal from "./reality2_action_signal";
import reality2_parameter from "./reality2_parameter";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_start_transition",
    "message0":"start as %1",
    "args0":[
        {
            "type":"field_input",
            "name":"to",
            "check": "String",
            "text": ""
        }
    ],
    "message1":"with %1",
    "args1":[
        {
            "type":"input_statement",
            "name":"parameters",
            "check":["reality_parameter"]
        }
    ],
    "message2":"TASKS",
    "message3":"%1",
    "args3":[
        {
            "type":"input_statement",
            "name":"actions",
            "check": ["reality2_action_debug", "reality2_action_send", "reality2_action_send_plugin", "reality2_action_set", "reality2_action_signal"]
        }
    ],
    "previousStatement":null,
	"nextStatement":null,
    "colour": 250,
    "tooltip":"The initialise transition called once when an Automation begins.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation",
    "inputsInline": true
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var transition: any = {};

    transition["from"] = "start";
    transition["event"] = "init";
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
            "type": "reality2_start_transition",
            "fields": {
                "to": R2.JSONPath(transition, "to")
            },
            "inputs": {
                "parameters": {},
                "actions": {}
            }
        }

        // Check if there are parameters
        let parameters: [any] = R2.JSONPath(transition, "parameters");
        if (parameters) {
            let parameters_block = reality2_parameter.construct(parameters);
            block["inputs"]["parameters"] = {"block": parameters_block}
        }

        // Check if there are actions
        let actions: [any] = R2.JSONPath(transition, "actions");

        // If there are, go backwards through the array creating each block, and linking to the next
        if (actions) {
            let actions_block = actions.reduceRight((acc, action) => {

                let command = action["command"];

                let action_block: any;
                let plugin_name = action["plugin"];

                if (plugin_name) {
                    action_block = reality2_action_send_plugin.construct(action);
                    if (action_block && acc) {
                        action_block["next"] =  { "block": acc };
                    }
                }
                else
                {
                    switch (command) {
                        case "set":
                            action_block = reality2_action_set.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }
                            break;
                        case "send":
                            let delay = R2.JSONPath(action, "delay");
                            if (delay > 0) {
                                action_block = reality2_action_send.construct(action);
                                if (action_block && acc) {
                                    action_block["next"] =  { "block": acc };
                                }
                            } else {
                                action_block = reality2_action_send_now.construct(action);
                                if (action_block && acc) {
                                    action_block["next"] =  { "block": acc };
                                }
                            }
                            break;
                        case "signal":
                            action_block = reality2_action_signal.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }
                            break;
                        case "debug":
                            action_block = reality2_action_debug.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }
                            break;
                    }
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