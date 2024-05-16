# ----------------------------------------------------------------------------------------------------
# This is a test program to monitor events on the Reality2 Node.
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
    result = R2.JSONPath(data, "awaitSignal.parameters")
    if (result != None):
        print(result)
    else:
        print(data)
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Connect to the Reality2 node
    r2_node = R2(host, 4001)

    definition = """
    {
        "sentant": 
        { 
            "name": "monitor", 
            "automations": [
                { 
                    "name": "Monitor", 
                    "transitions": [ 
                        { 
                            "event": "__internal", 
                            "actions": [ 
                                { 
                                    "command": "signal", 
                                    "parameters": 
                                    { 
                                        "public": true, 
                                        "event": "internal" 
                                    }
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    }
    """

    # Load a monitor sentant only if one doesn't already exist
    result = r2_node.sentantGet("monitor")
    id = R2.JSONPath(result, "sentantGet.id")
    if (id == None):
        result = r2_node.sentantLoad(definition)
        id = R2.JSONPath(result, "sentantLoad.id")

    if (id != None):
        # Start the subscriptions to the Sentant
        r2_node.awaitSignal(id, "internal", printout)

        print("+---- Monitor Reality2 Node ------------------------------+")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            if (input() == "q"):
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