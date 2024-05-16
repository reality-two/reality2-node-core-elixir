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
    answer = R2.JSONPath(data, "awaitSignal.parameters")
    if (answer == None):
        print(data)
    else:
        print(answer)
# ----------------------------------------------------------------------------------------------------
    

# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Connect to the Reality2 node
    r2_node = R2(host, 4001)
    
    # Delete the Sentant if it exists (only need this really if the yaml file has been changed, and we want to load the new version of the Sentant)
    r2_node.sentantUnloadByName("Test Parameters")

    # Read the file
    with open('test_parameters.json', 'r') as file:
        definition = file.read()  
        
    # Load the Sentant
    result = r2_node.sentantLoad(definition)

    # Grab the ID of the Sentant
    id = R2.JSONPath(result, "sentantLoad.id")
    
    parameters = {
        "param1": "Hello World", 
        "param2": True, 
        "param3": 42, 
        "param4": 3.14159, 
        "param5": [1, 2, 3], 
        "param6": {"key1": [{"a":0, "b":1}, {"a": 2, "b": 3}, "hello"], "key2": "value2"}
    }


    if (id != None):
        # Start the subscription to the Sentant
        r2_node.awaitSignal(id, "Response", printout)

        print("+---- Test Parameters ------------------------------------+")
        print("| Press the 1 key to send Event1 to the Sentant           |")
        print("| Press the 2 key to send Event2 to the Sentant           |")
        print("| ...                                                     |")
        print("| Press the 9 key to send Event9 to the Sentant           |")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            input_str = input()
            if (input_str == "q"):
                break
            else:
                # Send the event and parameters to the Sentant
                r2_node.sentantSend(id, "Event" + input_str, parameters)
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