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
# Create a given number of Sentants
# ----------------------------------------------------------------------------------------------------
def create(r2_node, number_of_sentants, current_max):
    print ("Creating {} Sentants.".format(number_of_sentants))
    for counter in range(0, number_of_sentants):
        definition = """
    sentant:
        name: Repeater""" + str(current_max + counter) + """
        """
        r2_node.sentantLoad(definition)
        
    print("There are now {} Sentants.".format(current_max + number_of_sentants))
    return current_max + number_of_sentants
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Delete all the previously created Sentants
# ----------------------------------------------------------------------------------------------------
def delete_all(r2_node, current_max):
    print ("Deleting {} Sentants.".format(current_max))
    for counter in range(0, current_max):
        r2_node.sentantUnloadByName("Repeater" + str(counter))
    return 0
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
    print("| Type a number followed by the enter key to create that  |")
    print("|   many Sentants.                                        |")
    print("| Press d followed by the enter key to delete all the     |")
    print("|   previously created Sentants.                          |")
    print("| Press q, followed by the enter key to quit.             |")
    print("+---------------------------------------------------------+")
    while (True):
        input_str = input()
        if (input_str == "q"):
            break
        elif (input_str == "d"):
            current_max = delete_all(r2_node, current_max)
        else:
            current_max = create(r2_node, int(input_str), current_max)

    # Close the subscriptions
    delete_all(r2_node, current_max)
    print("Quitting.")
    r2_node.close()
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
if (__name__ == '__main__'):
    main(sys.argv[1] if (len(sys.argv) > 1) else "localhost")
# ----------------------------------------------------------------------------------------------------