# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module and other modules
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2 as R2
import json
import sys
from gpiozero import LED, Button
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------------------------------------------
pins = {}
r2_node = None
id = ""
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Do Stuff
# ----------------------------------------------------------------------------------------------------
def dostuff(data):
    global pins, r2_node
    
    # Get the event from the awaitSignal
    event = R2.JSONPath(data, "awaitSignal.event")

    # Get the parameters from the awaitSignal
    parameters = R2.JSONPath(data, "awaitSignal.parameters")

    # Get the pin number
    pin = R2.JSONPath(parameters, "pin")

    if (pin != None):
        # Decide what to do
        if (event == "setup"):
            # Setting up
            type = R2.JSONPath(parameters, "type")

            if (type != None):
                if type.lower() == "led":
                    # Set to LED
                    pins[str(pin)] = LED(pin)

                    print("Pin: " + str(pin) + " is set to output.")
                elif type.lower() == "button":
                    # Set to Button
                    pins[str(pin)] = Button(pin)

                    send = R2.JSONPath(parameters, "send")
                    ev_name = R2.JSONPath(parameters, "name")
                    pins[str(pin)].when_pressed = lambda: r2_node.sentantSendByName(ev_name, send)

                    print("Pin: " + str(pin) + " is set to input.")
                else:
                    print("Unknown type: " + type)

        elif (event == "set_pin"):
            # Setting an output pin
            state = R2.JSONPath(parameters, "state")
            print("Setting pin: " + str(pin) + " to state: " + str(state))
            
            if state == "on":
                pins[str(pin)].on()     # Turn on the LED
            else:
                pins[str(pin)].off()    # Turn off the LED
        else:
            print("Data : " + json.dumps(R2.JSONPath(data, "awaitSignal")))
    else:
        print("Data : " + json.dumps(R2.JSONPath(data, "awaitSignal")))
# ----------------------------------------------------------------------------------------------------

        


# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    global r2_node, id

    # Connect to the Reality2 node
    r2_node = R2(host, 4005)
    
    # Unload the Sentant if it exists
    r2_node.sentantUnloadByName(".raspberry_pi")

    # Read the file
    with open('../controller.json', 'r') as file:
        definition = file.read()
        
    # Load the Swarm
    result = r2_node.sentantLoad(definition)

    # Get the resulting ID
    id = R2.JSONPath(result, "sentantLoad.id")

    if (id != None):
        # Start the subscriptions to the Sentant
        r2_node.awaitSignal(id, "setup", dostuff)
        r2_node.awaitSignal(id, "set_pin", dostuff)

        print("+---- Light Bulb Controller for Raspberry PI -------------+")
        print("| Press q, followed by the enter key to quit.             |")
        print("+---------------------------------------------------------+")
        while (True):
            input_str = input()
            if (input_str == "q"):
                break
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
