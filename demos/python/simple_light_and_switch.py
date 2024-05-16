# ----------------------------------------------------------------------------------------------------
# This is a test program that loads a Swarm of Sentants that represent a light switch and light bulb.
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2 as R2
import json
import sys
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the result from an awaitSignal
# ----------------------------------------------------------------------------------------------------
def printout(data):
    event = R2.JSONPath(data, "awaitSignal.event")
    
    if (event == "Light on"):
        print("The light is on.")
    elif (event == "Light off"):
        print("The light is off.")
    else:
        print("Data : " + json.dumps(R2.JSONPath(data, "awaitSignal")))
# ----------------------------------------------------------------------------------------------------
        


# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Connect to the Reality2 node
    r2_node = R2(host, 4001)

    # Unload the Sentants if they exist (only need this really if the yaml file has been changed, and we want to load the new versions of the Sentants)
    r2_node.sentantUnloadByName("Light Switch")
    r2_node.sentantUnloadByName("Light Bulb")

    # Read the file
    with open('simple_light_and_switch.json', 'r') as file:
        definition = file.read()
        
    # Load the Swarm
    result = r2_node.swarmLoad(definition)

    # Get the resulting IDs
    id_switch = R2.JSONPath(result, "swarmLoad.sentants.0.id")
    id_bulb = R2.JSONPath(result, "swarmLoad.sentants.1.id")

    if (id_switch != None and id_bulb != None):
        # Start the subscriptions to the Sentant
        r2_node.awaitSignal(id_bulb, "Light off", printout)
        r2_node.awaitSignal(id_bulb, "Light on", printout)

        print("+---- Light Switch and Bulb ------------------------------+")
        print("| Press the enter key to toggle the light switch.         |")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            input_str = input()
            if (input_str == "q"):
                break
            else:
                # Send the event to the Sentant
                print ("Toggling the light switch.")
                r2_node.sentantSend(id_switch, "Toggle Switch")
    else:
        print("Failed to load the Sentants.")

    # Close the subscriptions
    print("Closing the subscriptions and quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------
    


# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'): 
    main(sys.argv[1] if (len(sys.argv) > 1) else "localhost")
# ----------------------------------------------------------------------------------------------------
