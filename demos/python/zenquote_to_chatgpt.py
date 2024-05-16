# ----------------------------------------------------------------------------------------------------
# This is a test program to connect two APIs: Zenquote, to ChatGPT via a Sentant.
# The Zenquote API will send a quote to the ChatGPT API, and the ChatGPT API will respond with an
# explanation.
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
    answer = R2.JSONPath(data, "awaitSignal.parameters.answer")
    question = R2.JSONPath(data, "awaitSignal.parameters.question")
    event = R2.JSONPath(data, "awaitSignal.event")
    
    if (event == "debug"):
        print("DEBUG\n", R2.JSONPath(data, "awaitSignal.parameters"))    
    elif (answer != None):
        print("CHATGPT\n", answer)
    elif (question != None):
        print("ZENQUOTE\n", question)
    else:
        print(R2.JSONPath(data, "awaitSignal"))
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Connect to the Reality2 node
    r2_node = R2(host, 4001)
    
    # Delete the Sentant if it exists (only need this really if the yaml file has been changed, and we want to load the new version of the Sentant)
    r2_node.sentantUnloadByName("Zen ChatGPT")

    # Read the files
    with open('../../../OPENAI_API_KEY.txt', 'r') as file:
        OPENAI_API_KEY = file.read()
    with open('zenquote_to_chatgpt.yaml', 'r') as file:
        definition = file.read()
        
    # Replace the OPENAI_API_KEY in the YAML file
    definition = definition.replace("__openai_api_key__", OPENAI_API_KEY)
        
    # Load the Sentant
    result = r2_node.sentantLoad(definition)

    # Grab the ID of the Sentant
    id = R2.JSONPath(result, "sentantLoad.id")

    if (id != None):
        # Start the subscriptions to the Sentant
        r2_node.awaitSignal(id, "Zenquote", printout)
        r2_node.awaitSignal(id, "Explanation", printout)
        r2_node.awaitSignal(id, "debug", printout)

        print("+---- Zen Quote to ChatGPT -------------------------------+")
        print("| Press the enter key to send an event to the Sentant.    |")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            input_str = input()
            if (input_str == "q"):
                break
            else:
                # Send the event to the Sentant
                r2_node.sentantSend(id, "Get Zenquote")
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