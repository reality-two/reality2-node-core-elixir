# ----------------------------------------------------------------------------------------------------
# This is a test program to test a simple GET request to the Zenquote API.
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2 as R2
import sys
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Print out the result from an awaitSignal
# ----------------------------------------------------------------------------------------------------
def printout(data):
    print(data)
# ----------------------------------------------------------------------------------------------------
    

# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Connect to the Reality2 node
    r2_node = R2(host, 4001)
    
    # Delete the Sentant if it exists (only need this really if the yaml file has been changed, and we want to load the new version of the Sentant)
    r2_node.sentantUnloadByName("Incorrect")

    # Read the file
    with open('incorrect_definition.yaml', 'r') as file:
        definition = file.read()  
        
    # Load the Sentant
    result = r2_node.sentantLoad(definition)
    
    print(result)

    # Grab the ID of the Sentant
    id = R2.JSONPath(result, "sentantLoad.id")

    if (id != None):
        r2_node.awaitSignal(id, "debug", printout)

        print("+---- Incorrect Definition Test --------------------------+")
        print("| If you got this far, then the definition file is correct|")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            input_str = input()
            if (input_str == "q"):
                break
    else:
        print("Failed to load the Sentant.")

    # Close the subscriptions
    print("Closing the subscriptions and quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------
    


# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'):
    main(sys.argv[1] if (len(sys.argv) > 1) else "localhost")
# ----------------------------------------------------------------------------------------------------