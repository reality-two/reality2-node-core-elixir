// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------

import { splitConcatenatedJSON } from "./blockly_common";
import R2 from "../reality2";

// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
	"type":"reality2_action_set_calculation",
    "message0":"calc %1",
	"args0":[
        {
			"type":"field_input",
			"name":"value",
			"check":"String",
			"text":""
		}
	],
    "colour": 300,
    "output":"Json",
    "tooltip": "An expression in a string in reverse polish format.  So to add 1 and 2, for example, that would '1 2 +'.  To add 1 and 2, then multiply by 3 would be '1 2 + 3 *'.  Numbers from the data flow can be used by putting two underscores on either side, for example: '__answer__'.  Therefore, to add 2 to 'answer' would be 'answer 2 +'",
    "helpUrl": "https://github.com/reality-two/reality2-documentation"
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Infix to Postfix conversion
// ----------------------------------------------------------------------------------------------------
function infixToPostfix(infix: string): string {
    const precedence: { [key: string]: number } = {
        '+': 1, '-': 1,
        '*': 2, '/': 2, '%': 2,
        '^': 3
    };

    const associativity: { [key: string]: 'L' | 'R' } = {
        '+': 'L', '-': 'L',
        '*': 'L', '/': 'L', '%': 'L',
        '^': 'R'
    };

    const isOperator = (token: string): boolean => /[+\-*/^%]/.test(token);
    const isFunction = (token: string): boolean => /^(sin|cos|tan|log|exp|sqrt)$/.test(token);
    const isLeftParenthesis = (token: string): boolean => token === '(';
    const isRightParenthesis = (token: string): boolean => token === ')';

    let output: string[] = [];
    let operators: string[] = [];

    const tokens = infix.match(/([a-zA-Z]+(?:\([^\)]+\))?|[\d.]+|[+\-*/^%()]|\S)/g) || []; // Improved tokenization

    tokens.forEach(token => {
        if (/\d/.test(token) || /[a-zA-Z]+/.test(token)) { // Number or variable
            output.push(token);
        } else if (isFunction(token)) {
            operators.push(token);
        } else if (isOperator(token)) {
            while (operators.length && isOperator(operators[operators.length - 1]) &&
                ((associativity[token] === 'L' && precedence[token] <= precedence[operators[operators.length - 1]]) ||
                 (associativity[token] === 'R' && precedence[token] < precedence[operators[operators.length - 1]]))) {
                output.push(operators.pop()!);
            }
            operators.push(token);
        } else if (isLeftParenthesis(token)) {
            operators.push(token);
        } else if (isRightParenthesis(token)) {
            while (operators.length && !isLeftParenthesis(operators[operators.length - 1])) {
                output.push(operators.pop()!);
            }
            operators.pop(); // Discard '('

            if (operators.length && isFunction(operators[operators.length - 1])) {
                output.push(operators.pop()!); // Pop function
            }
        }
    });

    while (operators.length) {
        output.push(operators.pop()!);
    }

    return output.join(' ');
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Postfix to Infix conversion
// ----------------------------------------------------------------------------------------------------
function postfixToInfix(postfix: string): string {
    const isOperator = (token: string): boolean => /[+\-*/^%]/.test(token);
    const isFunction = (token: string): boolean => /^(sin|cos|tan|log|exp|sqrt)$/.test(token);

    let stack: string[] = [];
    const tokens = postfix.split(/\s+/); // Split by spaces

    tokens.forEach(token => {
        if (/\d/.test(token) || /[a-zA-Z]+/.test(token)) { // Number or variable
            stack.push(token);
        } else if (isOperator(token)) {
            const b = stack.pop()!;
            const a = stack.pop()!;
            stack.push(`(${a} ${token} ${b})`);
        } else if (isFunction(token)) {
            const a = stack.pop()!;
            stack.push(`${token}(${a})`);
        }
    });

    return stack.length ? stack[0] : '';
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number]
{
    const raw_value = block.getFieldValue('value');

    const value = (raw_value === "" ? null : R2.ToJSON(raw_value));

    const action = {
        "expr": value
    }
    
    return [JSON.stringify(action), 99];
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Create a blockly block object from the JSON
// ----------------------------------------------------------------------------------------------------
function construct(data: any)
{
    if (data) {
        // Set the initial structure
        let block = {
            "kind": "BLOCK",
            "type": "reality2_action_set_calculation",
            "fields": {
                "value": R2.ToSimple(R2.JSONPath(data, "expr"))
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