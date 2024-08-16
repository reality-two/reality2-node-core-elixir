// ----------------------------------------------------------------------------------------------------
// A Blockly Block
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Block Definition
// ----------------------------------------------------------------------------------------------------
const shape = {
    "type":"reality2_sentant",
    "message0":"name %1",
    "args0":[
        {
            "type":"field_input",
            "name":"name",
            "check":"String",
            "text":"Sentant Name"
        }
    ],
    "message1":"description %1",
    "args1":[
        {
            "type":"field_input",
            "name":"description",
            "check":"String",
            "text":"A brief description"
        }
    ],
    "message2":"keys %1",
    "args2":[
        {
            "type":"input_statement",
            "name":"keys"
        }
    ],
    "message3":"plugins %1",
    "args3":[
        {
            "type":"input_statement",
            "name":"plugins"
        }
    ],
    "message4":"automations %1",
    "args4":[
        {
            "type":"input_statement",
            "name":"automations"
        }
    ],
    "colour":120
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Process Block
// ----------------------------------------------------------------------------------------------------
function process(block: any, generator: any): string | [string, number] | null
{
    var sentant: any = {};

    sentant["name"] = block.getFieldValue('name');
    sentant["description"] = block.getFieldValue('description');

    const keys = generator.statementToCode(block, "keys");
    if (keys != "") {
        var multiple_keys: any = splitConcatenatedJsonObjects(keys);
        sentant["keys"] = JSON.parse(multiple_keys[0]);
    }

    const plugins = generator.statementToCode(block, "plugins");
    if (plugins != "") {
        var multiple_plugins: any = splitConcatenatedJsonObjects(plugins);
        sentant["plugins"] = multiple_plugins.map((plugin: any) => JSON.parse(plugin))
    }

    return JSON.stringify(sentant);
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