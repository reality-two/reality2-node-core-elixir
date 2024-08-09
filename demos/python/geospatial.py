# ----------------------------------------------------------------------------------------------------
# This is a test program that connects to the Reality2 node and loads a ChatGPT Sentant.
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2 as R2
import json
import sys
# ----------------------------------------------------------------------------------------------------

positions = [
    {"name": "Auckland Museum", "latitude": -36.860426874915866, "longitude": 174.77767677926224}, 
    {"name": "Domain",          "latitude": -36.859847723179335, "longitude": 174.77773825999947},
    {"name": "Wintergarden",    "latitude": -36.860134176770515, "longitude": 174.77414433783238},
    {"name": "Britomart Train Station", "latitude": -36.84420, "longitude":174.76779},
    {"name": "Lynn mall",       "latitude": -36.906973021967296, "longitude": 174.68603476913333}
]

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
    r2_node = R2(host, 4005)

    # Unload the Sentants
    for position in positions:
        r2_node.sentantUnloadByName(position["name"])

    # Read the base definition file
    with open('geospatial.json', 'r') as file:
        definition = file.read()
        
    definition_json = json.loads(definition)
    
    for position in positions:
        definition_json["sentant"]["name"] = position["name"]
        definition_string = json.dumps(definition_json)
        result = r2_node.sentantLoad(definition_string)
        id = R2.JSONPath(result, "sentantLoad.id")
        if (id != None):
            position["id"] = id
            print("Sentant loaded with id: ", id)
            
            # Set the position of the Sentant
            r2_node.sentantSend(id, "set_position", position)

            # Start the subscriptions to the Sentant
            r2_node.awaitSignal(id, "get", printout)
            r2_node.awaitSignal(id, "set", printout)
            r2_node.awaitSignal(id, "hello", printout)
            r2_node.awaitSignal(id, "debug", printout)

    print("+---- Geospatial Swarm -------------------------------------------+")
    print("| Press g, followed by the enter key to get the positions.        |")
    print("| Press b, followed by the enter key broadcast to sentants nearby.|")
    print("| Press q, followed by the enter key to quit.                     |")    
    print("+-----------------------------------------------------------------+")
        
    while (True):
        input_str = input()
        if (input_str == "q"):
            break
        elif (input_str == "b"):
            # Send the event to the Sentant
            print ("Broadcasting from : ", R2.JSONPath(positions, "0.name"), " to nearby Sentants.")
            r2_node.sentantSend(R2.JSONPath(positions, "0.id"), "Broadcast to nearby", {"radius": 100, "message": "Hello World"}, {"Hello": "World"})
        elif (input_str == "g"):
            # Send the event to the Sentant
            print ("Getting the positions.")
            for position in positions:
                r2_node.sentantSend(position["id"], "get_position")

    # Close the subscriptions
    print("Closing the subscriptions and quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------
    


# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'):
    main(sys.argv[1] if (len(sys.argv) > 1) else "localhost")
# ----------------------------------------------------------------------------------------------------