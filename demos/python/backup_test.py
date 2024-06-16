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
    event = R2.JSONPath(data, "awaitSignal.event")
    
    if (event == "debug"):
        print("DEBUG\n", R2.JSONPath(data, "awaitSignal.parameters")) 
    else: 
        print(R2.JSONPath(data, "awaitSignal.event"), " : ", R2.JSONPath(data, "awaitSignal.parameters"), " :: ", R2.JSONPath(data, "awaitSignal.passthrough"))
# ----------------------------------------------------------------------------------------------------
    

# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Connect to the Reality2 node
    r2_node = R2(host, 4001)
    
    # Delete the Sentant if it exists (only need this really if the yaml file has been changed, and we want to load the new version of the Sentant)
    r2_node.sentantUnloadByName("Test Backup")

    # Read the file
    with open('backup_test.yaml', 'r') as file:
        definition = file.read()  
        
    # Load the Sentant
    result = r2_node.sentantLoad(definition)

    # Grab the ID of the Sentant
    id = R2.JSONPath(result, "sentantLoad.id")

    if (id != None):
        # Start the subscription to the Sentant
        # r2_node.awaitSignal(id, "Zenquote Response", printout)
        r2_node.awaitSignal(id, "debug", printout)

        print("+---- Test Backup ----------------------------------------+")
        print("| Press the enter key to backup the current data.         |")
        print("| Press s, followed by the enter key to store the data.   |")
        print("| Press r, followed by the enter key to retrieve the data.|")
        print("| Press d, followed by the enter key to delete the data.  |")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            input_str = input()
            if (input_str == "q"):
                break
            elif (input_str == "s"):
                # Send the event to the Sentant
                print("Sending store to database event.")
                r2_node.sentantSend(id, "Store to Database")
            elif (input_str == "r"):
                # Send the event to the Sentant
                print("Sending retreive from database event.")
                r2_node.sentantSend(id, "Retrieve from Database")
            elif (input_str == "d"):
                # Send the event to the Sentant
                print("Sending delete from database event.")
                r2_node.sentantSend(id, "Delete from Database")
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