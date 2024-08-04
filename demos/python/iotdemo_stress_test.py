# ----------------------------------------------------------------------------------------------------
# This is a test program to monitor events on the Reality2 Node.
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
# Import the Reality2 module
# ----------------------------------------------------------------------------------------------------
from reality2 import Reality2 as R2
import sys
from getkey import getkey
import multiprocessing
import random
import time
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Local Variables
# ----------------------------------------------------------------------------------------------------
ids = {}    # The Sentant IDS stored by Sentant Name
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Create a name from a number for the Sentant
# ----------------------------------------------------------------------------------------------------
def make_name(index):
    return "device " + str(index).zfill(4)
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Create a given number of Sentants
# ----------------------------------------------------------------------------------------------------
def create(r2_node, number_of_sentants, current_max):
    print ("Creating {} Sentants.".format(number_of_sentants))
    for counter in range(0, number_of_sentants):
        definition = """
        {
            "sentant": {
                "name": \"""" + make_name(current_max + counter) + """\",
                "automations": [
                    {
                        "name": "counter",
                        "transitions": [
                            {
                                "event": "init",
                                "actions": [
                                    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "name", "value": \"""" + make_name(current_max + counter) + """\" } },
                                    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": 0 } }
                                ]
                            },
                            {
                                "event": "set_sensor", "public": true, "parameters": { "sensor": "integer" },
                                "actions": [
                                    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": "__sensor__" } }
                                ]
                            },
                            {
                                "event": "update", "public": true,
                                "actions": [
                                    { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor" } },
                                    { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "name" } },
                                    { "command": "send", "parameters": { "event": "update", "to": "view" } },
                                    { "command": "signal", "public": true, "parameters": { "event": "update" } }
                                ]
                            }
                        ]
                    }
                ]
            }
        }
        """

        # Create the new Sentant
        result = r2_node.sentantLoad(definition)

        # Get the ID and Name
        id = R2.JSONPath(result, "sentantLoad.id")
        name = R2.JSONPath(result, "sentantLoad.name")

        # Store these for later use
        ids[name] = id

        # A random sensor position to start from
        sensor = random.randint(0, 360)

        # Set the initial sensor value
        r2_node.sentantSend(id, "set_sensor", {"sensor": sensor})

        
    print("There are now {} Sentants.".format(current_max + number_of_sentants))
    return current_max + number_of_sentants
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Delete all the previously created Sentants
# ----------------------------------------------------------------------------------------------------
def delete_all(r2_node, current_max):
    print ("Deleting {} Sentants.".format(current_max))
    for counter in range(0, current_max):
        r2_node.sentantUnloadByName(make_name(counter))
    return 0
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Do some semi-random interaction with the Sentant specified
# ----------------------------------------------------------------------------------------------------
def do_in_parallel(r2_node, ids, device_num):
    # Choose a 'speed', so that all Sentants don't finish at the same time
    speed = random.randint(1, 5)
    
    # Get the Sentant ID for this device number
    id = ids[make_name(device_num)]

    # Choose a colour to move towards
    start_colour = random.randint(0, 360)

    # Choose a start colour
    colour = random.randint(0, 360)

    # Move towards that colour, from the start colour, in a number of steps, as if someone is turning their device.
    for count in range(0, 20):
        # Set the sensor colour on the Sentant
        if (count == 19):
            r2_node.sentantSend(id, "set_sensor", {"sensor": colour})
        else:
            r2_node.sentantSend(id, "set_sensor", {"sensor": start_colour + (count * (colour - start_colour) / 20)})

        # Send an update command to ensure all viewers are updated
        r2_node.sentantSend(id, "update", {});

        # Sleep a somewhat variable amount of time, to give some randomness
        time.sleep(random.uniform(0.3, 0.3*speed))
# ----------------------------------------------------------------------------------------------------

    

# ----------------------------------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------------------------------
def main(host):
    # Counter of how many created so far
    current_max = 0
    
    # Connect to the Reality2 node
    r2_node = R2(host, 4005)
    
    print("+---- Create many Sentants -------------------------------+")
    print("| Type c to create Sentants.                              |")
    print("| Type d to delete previously created Sentants.           |")
    print("| Type t to run 20 seconds of testing                     |")
    print("| Type q, followed by the enter key to quit.              |")
    print("+---------------------------------------------------------+")
    while (True):
        key = getkey()
        
        if (key == "q"):
            break
        elif (key == "d"):
            current_max = delete_all(r2_node, current_max)
        elif (key == "c"):
            print("Type in the number of devices to add", end=" : ")
            count = input()
            current_max = create(r2_node, int(count), current_max)
        elif (key == "t"):
            print("Testing...")

            # Randomise the order that the processes are started in
            numbers = list(range(current_max))
            random.shuffle(numbers)

            # Start a parallel process for each Sentant
            for counter in numbers:
                multiprocessing.Process(target=do_in_parallel, args=(r2_node, ids, counter,)).start()
        else:
            print("Please press c to create, d to delete, t to test, or q to quit.")

    # Close the subscriptions and delete all the Sentants
    delete_all(r2_node, current_max)
    print("Quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Main function.  Note the single parameter to speciy a different Reality2 Node.
# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'):
    main(sys.argv[1] if (len(sys.argv) > 1) else "localhost")
# ----------------------------------------------------------------------------------------------------