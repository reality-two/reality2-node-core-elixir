# ----------------------------------------------------------------------------------------------------
# This is a test program that connects to the Reality2 node and loads a ChatGPT Sentant.
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

    # Unload the Sentant if it exists (only need this really if the yaml file has been changed, and we want to load the new version of the Sentant)
    r2_node.sentantUnloadByName("Ask Question")
    
    # Read the files
    with open('../../OPENAI_API_KEY.txt', 'r') as file:
        OPENAI_API_KEY = file.read()
    with open('chatgpt_question.yaml', 'r') as file:
        definition = file.read()  
        
    # Replace the OPENAI_API_KEY in the YAML file
    definition = definition.replace("__openai_api_key__", OPENAI_API_KEY)

    # Load the Sentant
    result = r2_node.sentantLoad(definition)

    # Grab the ID of the Sentant
    id = R2.JSONPath(result, "sentantLoad.id")

    if (id != None):
        # Start the subscription to the Sentant
        r2_node.awaitSignal(id, "ChatGPT Answer", printout)

        print("+---- Text External Plugin (ChatGPT) ---------------------+")
        print("| Type a question and press enter to send to ChatGPT.     |")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            input_str = input()
            if (input_str == "q"):
                break
            else:
                # Send the event to the Sentant
                r2_node.sentantSend(id, "Ask ChatGPT", {"question": input_str})
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