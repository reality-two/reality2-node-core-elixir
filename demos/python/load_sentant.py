# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2 as R2
import sys
import time
import json
from os.path import exists
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the help
# ----------------------------------------------------------------------------------------------------
def printhelp(events):
    print("---------- Send Events ----------")
    counter = 0
    for event in events:
        print(" Press", counter, "followed by the enter key for [", event["event"], event["parameters"], "]")
        counter = counter + 1

    print(" Press h, followed by the enter key for this help.")
    print(" Press q, followed by the enter key to quit.")
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

    # Connect to the Reality2 node
    r2_node = R2(host, 4001)

    # Read the definition file
    if (exists(filename)):
        with open(filename, 'r') as file:
            definition = file.read()
    else:
        print("The file", filename, "does not exist.")
        return

    # Read the variables file (if it exists)
    if exists('../../../variables.json'):
        with open('../../../variables.json', 'r') as file:
            variables_txt = file.read()
        
        # Convert the variables to a dictionary
        variables = json.loads(variables_txt)

        # Replace the variables in the definition file
        for key in variables:
            definition = definition.replace(key, variables[key])

    # Unload any existing Sentants named in the file
    sentant_name = R2.JSONPath(definition, "sentant.name")
    r2_node.sentantUnloadByName(sentant_name)

    # Load the Sentant
    result = r2_node.sentantLoad(definition, {}, "id name signals events { event parameters}")

    # Grab the ID of the Sentant
    id = R2.JSONPath(result, "sentantLoad.id")

    # Get the signals and events
    signals = R2.JSONPath(result, "sentantLoad.signals")
    events = R2.JSONPath(result, "sentantLoad.events")

    # Start the subscriptions to the Sentant
    r2_node.awaitSignal(id, "debug", printout)
    for signal in signals:
        r2_node.awaitSignal(id, signal, printout)

    # Wait 1 second to allow the subscriptions to catch up
    time.sleep(1)

    # Print out the help
    printhelp(events)

    # Wait for user input and send the events
    while (True):
        input_str = input()
        if (input_str == "q"):
            break
        elif (input_str == "h"):
            printhelp(events)
        else:
            if input_str.isdigit():
                index = int(input_str)
                if (index >= 0 and index < len(events)):
                    event = events[int(input_str)]
                    parameters = event["parameters"]

                    parameter_index = 0
                    for parameter in parameters:
                        print("Type in a", parameters[parameter], "for", parameter, end=" :")
                        parameter_str = input()
                        parameters[parameter] = parameter_str
    
                    print("Sending event [", event["event"], "]")
                    r2_node.sentantSend(id, event["event"], event["parameters"])
                else:
                    print("Please enter a number between 0 and", len(events) - 1, "inclusive.")
            else:
                print("Please enter a number or q to quit.")

    # Close the subscriptions
    print("Closing the subscriptions and quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# If this script is run from the command line then call the main function.
# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'):
    if (len(sys.argv) < 2):
        print("Usage: python3 load_sentant.py <filename> <host>")
        sys.exit(1)

    main(sys.argv[1], sys.argv[2] if (len(sys.argv) > 2) else "localhost")
# ----------------------------------------------------------------------------------------------------