# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
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

yaml = ruamel.yaml.YAML(typ='safe')

# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the help
# ----------------------------------------------------------------------------------------------------
def printhelp(events):
    print (events)
    print("---------- Send Events ----------")
    
    for counter, event in enumerate(events):
        print(" Press [", counter, "] for {", event["event"], event["parameters"], "}")

    print(" Press [ h ] for help.")
    print(" Press [ q ] to quit.")
    print("---------------------------------")    
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the result from an awaitSignal
# ----------------------------------------------------------------------------------------------------
def printout(data):
    event = R2.JSONPath(data, "awaitSignal.event")
    
    if (event == "debug"):
        print("DEBUG\n", R2.JSONPath(data, "awaitSignal.parameters")) 
    else: 
        print(R2.JSONPath(data, "awaitSignal.event"), " : ", R2.JSONPath(data, "awaitSignal.parameters"), " :: ", R2.JSONPath(data, "awaitSignal.passthrough"))
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(filename, host):

    # ------------------------------------------------------------------------------------------------
    # Connect to the Reality2 node
    # ------------------------------------------------------------------------------------------------
    r2_node = R2(host, 4001)

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
    # Read the variables file (if it exists)
    # ------------------------------------------------------------------------------------------------
    if exists('../../../variables.json'):
        with open('../../../variables.json', 'r') as file:
            variables_txt = file.read()
        
        # Convert the variables to a dictionary
        variables = json.loads(variables_txt)

        # Replace the variables in the definition file
        for key in variables:
            definition = definition.replace(key, variables[key])

    # ------------------------------------------------------------------------------------------------
    # Unload the existing Sentants named in the file if it exists
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
            
    sentant_names = R2.JSONPath(definition_json, "swarm.sentants.[].name")
    print("Unloading existing Sentants named \"", sentant_names, "\"")
    for sentant_name in sentant_names:
        r2_node.sentantUnloadByName(sentant_name)

    # ------------------------------------------------------------------------------------------------
    # Load the Swarm
    # ------------------------------------------------------------------------------------------------
    result = r2_node.swarmLoad(definition, {}, "id name signals events { event parameters }")
    
    # ------------------------------------------------------------------------------------------------
    # Get the IDs of the loaded Sentants
    # ------------------------------------------------------------------------------------------------
    ids = R2.JSONPath(result, "swarmLoad.sentants.[].id")
    
    # ------------------------------------------------------------------------------------------------
    # Get the signals and events
    # ------------------------------------------------------------------------------------------------
    signals = list(zip(ids, R2.JSONPath(result, "swarmLoad.sentants.[].signals")))            
    events = [
        {**dict_element, 'id': id}
        for id, inner_array in zip(ids, R2.JSONPath(result, "swarmLoad.sentants.[].events"))
        for dict_element in inner_array
    ]

    # ------------------------------------------------------------------------------------------------
    # Start the subscriptions to the Sentants
    # ------------------------------------------------------------------------------------------------
    for id in ids:
        r2_node.awaitSignal(id, "debug", printout)
        
    for signal_tuple in signals:
        id, signals = signal_tuple
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
        key = getkey()
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

                    print("Sending event [", events[index]["event"], "]")
                    r2_node.sentantSend(events[index]["id"], events[index]["event"], parameters)
                else:
                    print("Please enter a number between 0 and", len(events) - 1, "inclusive.")
            else:
                print("Please enter a number, h for help, or q to quit.")

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
        print("Usage: python3 load_swarm.py <filename> <host>")
        sys.exit(1)

    main(sys.argv[1], sys.argv[2] if (len(sys.argv) > 2) else "localhost")
# ----------------------------------------------------------------------------------------------------