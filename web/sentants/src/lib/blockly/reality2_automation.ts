// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_transition from "./reality2_transition";
import reality2_transition_no_params from "./reality2_transition_no_params";
import reality2_simple_transition from "./reality2_simple_transition";
import reality2_simple_transition_no_params from "./reality2_simple_transition_no_params";
import reality2_start_transition from "./reality2_start_transition";
import reality2_start_transition_no_params from "./reality2_start_transition_no_params";
import reality2_start_transition_simple from "./reality2_start_transition_simple";
import reality2_monitor from "./reality2_monitor";


// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_automation",
    "message0":"BEHAVIOUR %1",
    "args0":[
        {
            "type":"field_input",
            "name":"name",
            "check":"String",
            "text":"name"
        }
    ],
    "message1":"%1",
    "args1":[
        {
            "type":"field_input",
            "name":"description",
            "check":"String",
            "text":"description"
        }
    ],
    "message2":"DECISIONS",
    "message3":"%1",
    "args3":[
        {
            "type":"input_statement",
            "name":"transitions",
            "check": "reality2_transition"
        }
    ],
    "previousStatement":null,
	"nextStatement":null,
    "colour": 200,
    "tooltip": "A behaviour, which defines what a Bee is able to do.",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var automation: any = {};

    automation["name"] = block.getFieldValue('name');
    if (block.getFieldValue('description') !== "") automation["description"] = block.getFieldValue('description');

    const transitions = generator.statementToCode(block, "transitions");

    if (transitions != "") {
        automation["transitions"] = splitConcatenatedJSON(transitions, false);
    }

    return JSON.stringify({"automation": automation});
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(automation: any)
{
    if (automation) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_automation",
            "fields": {
                "name": R2.JSONPath(automation, "name"),
                "description": R2.JSONPath(automation, "description") ? R2.JSONPath(automation, "description") : ""
            },
            "inputs": {
                "transitions": {}
            }
        }

        // Check if there are transitions
        let transitions: [any] = R2.JSONPath(automation, "transitions");

        // If there are, go backwards through the array creating each block, and linking to the next
        if (transitions) {
            let transitions_block = transitions.reduceRight((acc, transition) => {

                let event = transition["event"];
                let to = transition["to"];
                let from = transition["from"];

                let transition_block: any;

                if (event == "__internal") {
                    // Internal
                    transition_block = reality2_monitor.construct(transition);
                    if (transition_block && acc) {
                        transition_block["next"] =  { "block": acc };
                    }
                }
                else if ((event && !to && !from)) {
                    // Command
                    let parameters: [any] = R2.JSONPath(transition, "parameters");
                    if (parameters && Object.keys(parameters).length > 0) {
                        transition_block = reality2_simple_transition.construct(transition);
                        if (transition_block && acc) {
                            transition_block["next"] =  { "block": acc };
                        }
                    } else {
                        transition_block = reality2_simple_transition_no_params.construct(transition);
                        if (transition_block && acc) {
                            transition_block["next"] =  { "block": acc };
                        }
                    }
                }
                else if ((event == "init") && (from == "start")) {
                    // Init
                    let parameters: [any] = R2.JSONPath(transition, "parameters");
                    if (!to) {
                        transition_block = reality2_start_transition_simple.construct(transition);
                        if (transition_block && acc) {
                            transition_block["next"] =  { "block": acc };
                        }
                    }
                    else if (parameters && Object.keys(parameters).length > 0) {
                        transition_block = reality2_start_transition.construct(transition);
                        if (transition_block && acc) {
                            transition_block["next"] =  { "block": acc };
                        }
                    } else {
                        transition_block = reality2_start_transition_no_params.construct(transition);
                        if (transition_block && acc) {
                            transition_block["next"] =  { "block": acc };
                        }
                    }
                }
                else {
                    let parameters: [any] = R2.JSONPath(transition, "parameters");
                    if (parameters && Object.keys(parameters).length > 0) {
                        transition_block = reality2_transition.construct(transition);
                        if (transition_block && acc) {
                            transition_block["next"] =  { "block": acc };
                        }
                    } else {
                        transition_block = reality2_transition_no_params.construct(transition);
                        if (transition_block && acc) {
                            transition_block["next"] =  { "block": acc };
                        }                        
                    }
                }
        
                // accumulate the block so far
                return transition_block;
            }, null);
        
            // Sentants starts as a block
            block["inputs"]["transitions"] = {"block": transitions_block};
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