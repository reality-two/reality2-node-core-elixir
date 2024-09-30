// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";
import reality2_action_set_value from "./reality2_action_set_value";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_set_calc_binary",
    "message0":"( %1 %2 %3 )",
	"args0":[
        {
			"type":"input_value",
			"name":"value1"
		},
        {
            "type":"field_dropdown",
            "name":"operator",
            "options":[
                ["+", "+"],
                ["-", "-"],
                ["*", "*"],
                ["/", "/"],

                ["&&", "&&"],
                ["||", "||"],
                
                ["==", "=="],
                ["!=", "!="],
                ["<", "<"],
                [">", ">"],
                ["<=", "<="],
                [">=", ">="],

                ["pow", "pow"],
                ["fmod", "fmod"],
                ["atan2", "atan2"],
                ["geohash", "geohash"]
            ]
        },
        {
			"type":"input_value",
			"name":"value2"
		}
	],
    "colour": 300,
    "output":"Json",
    "tooltip": "An binary expression",
    "helpUrl": "https://github.com/reality-two/reality2-documentation",
    "inputsInline": true
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number]
{
    const raw_value1 = generator.valueToCode(block, "value1", 99);
    const raw_value2 = generator.valueToCode(block, "value2", 99);
    const operator = block.getFieldValue('operator');

    const value1expr = (raw_value1 === "" ? null : R2.ToJSON(raw_value1));
    const value2expr = (raw_value2 === "" ? null : R2.ToJSON(raw_value2));

    const value1 = R2.JSONPath(value1expr, "expr") ? R2.JSONPath(value1expr, "expr") : value1expr;
    const value2 = R2.JSONPath(value2expr, "expr") ? R2.JSONPath(value2expr, "expr") : value2expr;

    let expr:any = {};
    expr[operator] = [value1, value2];
    
    let action = {
        "expr": expr
    }
    return [JSON.stringify(action), 99];
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(expr: any)
{
    if (expr) {
        const operator:any = Object.keys(expr)[0];
        const parameters:any[] = expr[operator];

        if (parameters.length == 1)
        {

            // Set the initial structure
            let block = {
                "kind": "BLOCK",
                "type": "reality2_action_set_calc_unary",
                "fields": {
                    "operator": operator
                },
                "inputs": {
                    "value1": {}
                }
            }

            if (typeof(parameters[0]) == "object") {
                block["inputs"]["value1"] = {"block": construct(parameters[0])}
            } else {
                block["inputs"]["value1"] = {"block": reality2_action_set_value.construct(parameters[0])}
            }

            return (block);

        } 
        else if (parameters.length == 2)
        {

            // Set the initial structure
            let block = {
                "kind": "BLOCK",
                "type": "reality2_action_set_calc_binary",
                "fields": {
                    "operator": operator
                },
                "inputs": {
                    "value1": {},
                    "value2": {}
                }
            }

            if (typeof(parameters[0]) == "object") {
                block["inputs"]["value1"] = {"block": construct(parameters[0])}
            } else {
                block["inputs"]["value1"] = {"block": reality2_action_set_value.construct(parameters[0])}
            }
            if (typeof(parameters[1]) == "object") {
                block["inputs"]["value2"] = {"block": construct(parameters[1])}
            } else {
                block["inputs"]["value2"] = {"block": reality2_action_set_value.construct(parameters[1])}
            }

            return (block);

        }
        else return null;
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