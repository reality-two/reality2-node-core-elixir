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


ids = {}


def make_name(index):
    return "device " + str(index).zfill(4)





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
                                    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "counter", "value": 0 } },
                                    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": 0 } }
                                ]
                            },
                            {
                                "event": "setsensor", "public": true, "parameters": { "sensor": "integer" },
                                "actions": [
                                    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": "__sensor__" } }
                                ]
                            },
                            {
                                "event": "count", "public": true,
                                "actions": [
                                    { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "counter" } },
                                    { "command": "set", "parameters": { "key": "counter", "value": { "expr": "counter 1 +"  } } },
                                    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "counter", "value": "__counter__"  } }
                                ]
                            },
                            {
                                "event": "update", "public": true,
                                "actions": [
                                    { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "counter" } },
                                    { "command": "get", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor" } },
                                    { "command": "signal", "public": true, "parameters": { "event": "update" } }
                                ]
                            }
                        ]
                    }
                ]
            }
        }
        """
        result = r2_node.sentantLoad(definition)
        id = R2.JSONPath(result, "sentantLoad.id")
        name = R2.JSONPath(result, "sentantLoad.name")
        ids[name] = id
        
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
# ----------------------------------------------------------------------------------------------------
def do_some_activities(r2_node, current_max):
    for count in range (0, 20):
        numbers = list(range(current_max))
        random.shuffle(numbers)
        for counter in numbers:
            id = ids[make_name(counter)]        
            r2_node.sentantSend(id, "setsensor", {"sensor": random.randint(0, 360)});
            r2_node.sentantSend(id, "count", {});
            r2_node.sentantSend(id, "update", {});  

        # time.sleep(1)

    return 0
# ----------------------------------------------------------------------------------------------------



def do_in_parallel(r2_node, ids, counter):
    for count in range(0, 20):
        id = ids[make_name(counter)]        
        r2_node.sentantSend(id, "setsensor", {"sensor": random.randint(0, 360)});
        time.sleep(random.uniform(0.05, 0.15))
        r2_node.sentantSend(id, "count", {});
        time.sleep(random.uniform(0.05, 0.15))
        r2_node.sentantSend(id, "update", {});  
        time.sleep(random.uniform(0.05, 0.15))

    

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
            # do_some_activities(r2_node, current_max)
            numbers = list(range(current_max))
            random.shuffle(numbers)
            for counter in numbers:
                multiprocessing.Process(target=do_in_parallel, args=(r2_node, ids, counter,)).start()
    # Close the subscriptions
    delete_all(r2_node, current_max)
    print("Quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'):
    main(sys.argv[1] if (len(sys.argv) > 1) else "localhost")
# ----------------------------------------------------------------------------------------------------