# ----------------------------------------------------------------------------------------------------
# A Python script for loading and interacting with a single Sentant.
# Usage:
#
# python3 load_sentant.py <filename> <host>
#
# The filename is the name of the file containing the Sentant definition (JSON, TOML, or YAML format).
# The host is the IP address or domain name of the Reality2 node (default is localhost).
# ----------------------------------------------------------------------------------------------------

from reality2 import Reality2 as R2
import sys
import time
import json
import toml
from os.path import exists
from getkey import getkey
import copy
import ruamel.yaml
import re
import base64

yaml = ruamel.yaml.YAML(typ='safe')
print_cr = False

# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the help
# ----------------------------------------------------------------------------------------------------
def printhelp(events):
    print("---------- Send Events ----------")
    
    for counter, event in enumerate(events):
        print(" Press [", counter, "] for {", event["event"], event["parameters"], "}")

    print(" Press [ h ] for help.")
    print(" Press [ q ] to quit.")
    print("---------------------------------")    
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Create a prompt for the user to enter a number between 0 and the number of events, or h or q
# ----------------------------------------------------------------------------------------------------
def prompt(events):
    global print_cr
    
    prompt = ""
    for counter, event in enumerate(events):
        prompt += str(counter) + " "
    prompt += "h q >"
    print_cr = True
    return prompt
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the result from an awaitSignal
# ----------------------------------------------------------------------------------------------------
def printout(data):
    global print_cr
    
    event = R2.JSONPath(data, "awaitSignal.event")
    
    if (print_cr):
        print_cr = False
        print()
    
    if (event == "debug"):
        print("DEBUG  :", R2.JSONPath(data, "awaitSignal.parameters")) 
    else: 
        print("SIGNAL : [", R2.JSONPath(data, "awaitSignal.event"), "] :", R2.JSONPath(data, "awaitSignal.parameters"), "::", R2.JSONPath(data, "awaitSignal.passthrough"))
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Replace the variables in the definition file
# ----------------------------------------------------------------------------------------------------
def replace_variables(definition, variables_filename):
    with open(variables_filename, 'r') as file:
        variables_txt = file.read()
    
    # Convert the variables to a dictionary
    variables = json.loads(variables_txt)

    # Replace the variables in the definition file
    for key in variables:
        definition = definition.replace(key, variables[key])
        
    return definition
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Replace file(filename) references with base64 encoded file contents
# ----------------------------------------------------------------------------------------------------
def encode_file_to_base64(filename):
    # Read a file and return its base64 encoded contents.
    if (exists(filename)):
        with open(filename, 'rb') as file:
            file_contents = file.read()
        return base64.b64encode(file_contents).decode('utf-8')
    else:
        print("The file", filename, "does not exist.")
        return ""

def replace_file_references(definition):
    # Replace file(filename) references with base64 encoded file contents.
    pattern = re.compile(r'file\((.*?)\)')
    
    def replace_match(match):
        filename = match.group(1)
        encoded_content = encode_file_to_base64(filename)
        return encoded_content
    
    return pattern.sub(replace_match, definition)    
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(filename, host, port):

    # ------------------------------------------------------------------------------------------------
    # Connect to the Reality2 node
    # ------------------------------------------------------------------------------------------------
    r2_node = R2(host, port)

    # ------------------------------------------------------------------------------------------------
    # Read the definition file
    # ------------------------------------------------------------------------------------------------
    if (exists(filename)):
        with open(filename, 'r') as file:
            definition = file.read()
    else:
        print("The file", filename, "does not exist.")
        return
    
    # ------------------------------------------------------------------------------------------------
    # Read the variables files (if they exist)
    # ------------------------------------------------------------------------------------------------
    if exists('../../../variables.json'):
        definition = replace_variables(definition, '../../../variables.json')
    if exists('./variables.json'):
        definition = replace_variables(definition, './variables.json')
        
    # ------------------------------------------------------------------------------------------------
    # Replace file(filename) references with base64 encoded file contents
    # ------------------------------------------------------------------------------------------------
    definition = replace_file_references(definition)
   
    # ------------------------------------------------------------------------------------------------
    # Unload the existing Sentant named in the file if it exists
    # ------------------------------------------------------------------------------------------------
    if filename.endswith('.yaml'):
        definition_json = yaml.load(definition)
    elif filename.endswith('.toml'):
        definition_json = toml.loads(definition)
    elif filename.endswith('.json'):
        definition_json = json.loads(definition)
    else:
        print("The file", filename, "is not a valid format.")
        return
        
    sentant_name = R2.JSONPath(definition_json, "sentant.name")
    print("Unloading existing Sentant named \"", sentant_name, "\"")
    r2_node.sentantUnloadByName(sentant_name)

    # ------------------------------------------------------------------------------------------------
    # Load the Sentant
    # ------------------------------------------------------------------------------------------------
    result = r2_node.sentantLoad(definition, {}, "id name signals events { event parameters }")

    # ------------------------------------------------------------------------------------------------
    # Get the ID of the loaded Sentant
    # ------------------------------------------------------------------------------------------------
    id = R2.JSONPath(result, "sentantLoad.id")

    # ------------------------------------------------------------------------------------------------
    # Get the signals and events
    # ------------------------------------------------------------------------------------------------
    signals = R2.JSONPath(result, "sentantLoad.signals")
    events = R2.JSONPath(result, "sentantLoad.events")

    # ------------------------------------------------------------------------------------------------
    # Start the subscriptions to the Sentant
    # ------------------------------------------------------------------------------------------------
    r2_node.awaitSignal(id, "debug", printout)
    for signal in signals:
        r2_node.awaitSignal(id, signal, printout)

    # ------------------------------------------------------------------------------------------------
    # Wait a second to allow the subscriptions to catch up
    # ------------------------------------------------------------------------------------------------
    time.sleep(1)

    # ------------------------------------------------------------------------------------------------
    # Print out the help
    # ------------------------------------------------------------------------------------------------
    printhelp(events)

    # ------------------------------------------------------------------------------------------------
    # Wait for user input and send the events
    # ------------------------------------------------------------------------------------------------
    while (True):
        print (prompt(events), end=" ", flush=True)
        key = getkey()
        print("\n")
        
        if (key =="q"):
            break
        elif (key == "h"):
            printhelp(events)
        else:
            if key.isdigit():
                index = int(key)
                if (index >= 0 and index < len(events)):
                    parameters = copy.deepcopy(events[index]["parameters"])

                    for parameter in parameters:
                        print("Type in a", parameters[parameter], "for", parameter, end=" : ")
                        parameters[parameter] = input()

                    print("SEND   : [", events[index]["event"], "]")
                    r2_node.sentantSend(id, events[index]["event"], parameters)
                else:
                    print("Please enter a number from 0 to", len(events) - 1)
            else:
                print("Please enter a number, h for help, or q to quit.")
                
        time.sleep(1)

    # ------------------------------------------------------------------------------------------------
    # Close the subscriptions
    # ------------------------------------------------------------------------------------------------
    print("Closing the subscriptions and quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# If this script is run from the command line then call the main function.
# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'):
    if (len(sys.argv) < 2):
        print("Usage: python3 load_sentant.py <filename> <host> <port>")
        sys.exit(1)

    main(sys.argv[1], sys.argv[2] if (len(sys.argv) > 2) else "localhost", sys.argv[3] if (len(sys.argv) > 3) else 4005)
# ----------------------------------------------------------------------------------------------------