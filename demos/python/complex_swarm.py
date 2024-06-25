# ----------------------------------------------------------------------------------------------------
# This is a test program that connects to the Reality2 node and loads a ChatGPT Sentant.
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2
import sys
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the result from an awaitSignal
# ----------------------------------------------------------------------------------------------------
def printout(data):
    if ("awaitSignal" in data):
        if (data["awaitSignal"]["event"] == "turn_on"):
            print("The light is on.")
        elif (data["awaitSignal"]["event"] == "turn_off"):
            print("The light is off.")
        else:
            print(data["awaitSignal"]["event"])
    else:
        print(data)
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Connect to the Reality2 node
    reality2_node = Reality2(host, 4001)

    # Unload the Sentants if they exist (only need this really if the yaml file has been changed, and we want to load the new version of the Sentant)
    reality2_node.sentantUnloadByName("Light Switch")
    reality2_node.sentantUnloadByName("Light Bulb")

    # Read the file
    with open('complex_swarm.yaml', 'r') as file:
        yamlDefinition = file.read()
    
    # Load the Sentants (Swarm)
    result = reality2_node.swarmLoad(yamlDefinition)

    # Get the resulting IDs
    id_switch = result["swarmLoad"]["sentants"][0]["id"]
    id_bulb = result["swarmLoad"]["sentants"][1]["id"]

    # Start the subscriptions to the Sentant
    reality2_node.awaitSignal(id_bulb, "turn_off", printout)
    reality2_node.awaitSignal(id_bulb, "turn_on", printout)

    print("+---- Complex Swarm --------------------------------------+")
    print("| Press 0, followed by the enter key for turn_off         |")
    print("| Press 1, followed by the enter key for turn_on          |")
    print("| Press q, followed by the enter key to quit.             |")
    print("+---------------------------------------------------------+")
    while (True):
        input_str = input()
        if (input_str == "q"):
            break
        elif (input_str == "1"):
            # Send the event to the Sentant
            print ("Turning on the light switch.")
            reality2_node.sentantSend(id_switch, "turn_on")
        else:
            # Send the event to the Sentant
            print ("Turning off the light switch.")
            reality2_node.sentantSend(id_switch, "turn_off")

    # Close the subscriptions
    print("Closing the subscriptions and quitting.")
    reality2_node.close()
# ----------------------------------------------------------------------------------------------------
    


# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'): 
    main(sys.argv[1] if (len(sys.argv) > 1) else "localhost")
# ----------------------------------------------------------------------------------------------------