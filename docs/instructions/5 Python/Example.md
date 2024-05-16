# Example

```python
# ----------------------------------------------------------------------------------------------------
# This is a test program to test a simple GET request to the Zenquote API.
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2 as R2
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
def main():
    # Connect to the Reality2 node
    r2_node = R2("localhost", 4001)
    
    # Delete the Sentant if it exists (only need this really if the yaml file has been changed, and we want to load the new version of the Sentant)
    r2_node.sentantUnloadByName("Zen Quote")

    # Read the file
    with open('zenquote.yaml', 'r') as file:
        definition = file.read()  
        
    # Load the Sentant
    result = r2_node.sentantLoad(definition)

    # Grab the ID of the Sentant
    id = R2.JSONPath(result, "sentantLoad.id")

    if (id != None):
        # Start the subscription to the Sentant
        r2_node.awaitSignal(id, "Zenquote Response", printout)

        print("+---- Zen Quote ------------------------------------------+")
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
if (__name__ == '__main__'): main()
# ----------------------------------------------------------------------------------------------------
```

And the Sentant definition file is:

```yaml
sentant:
  name: Zen Quote
  description: Get a quote for the day
  plugins:
    - name: io.zenquotes.api
      url: https://zenquotes.io/api/random
      method: GET
      headers:
        "Content-Type": "application/json"        
      output:
        key: answer
        value: "0.q"
        event: zenquote_response

  automations:
    - name: Zen Quote
      description: Get quote
      transitions:
        - from: start
          event: init
          to: ready
        - from: "*"
          public: true
          event: "Get Zenquote"
          to: ready
          actions:
            - plugin: io.zenquotes.api
              command: send
        - from: ready
          event: zenquote_response
          to: ready
          actions:
            - command: signal
              parameters:
                public: true
                event: "Zenquote Response"
 
```

