# ------------------------------------------------------------------------------------------------------------------------------------------------------
# Reality2 class for connecting to a Reality2 Node
# Author: Roy Davies, 2024, roycdavies.github.io
# ------------------------------------------------------------------------------------------------------------------------------------------------------
import json
import time
import threading
from websockets.sync.client import connect, ssl

import requests

# Avoid errors with self-signed certificates.
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
# ------------------------------------------------------------------------------------------------------------------------------------------------------



# ------------------------------------------------------------------------------------------------------------------------------------------------------
# Reality2 class for connecting to a Reality2 Node
# ------------------------------------------------------------------------------------------------------------------------------------------------------
class Reality2:
    
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Private attributes
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    __graphql_http_url: str
    __graphql_webs_url: str
    __secure: True
    
    __events = []
    # --------------------------------------------------------------------------------------------------------------------------------------------------


    
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Constructor
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __init__ (self, domain_name, port, ssl = True):
        self.__secure = ssl
        if (ssl):
            self.__graphql_http_url = "https://" + domain_name + ":" + str(port) + "/reality2"
            self.__graphql_webs_url = "wss://" + domain_name + ":" + str(port) + "/reality2/websocket"
        else:
            self.__graphql_http_url = "http://" + domain_name + ":" + str(port) + "/reality2"
            self.__graphql_webs_url = "ws://" + domain_name + ":" + str(port) + "/reality2/websocket"
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    
    
    
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def close(self):
        for thread in self.__events:
            thread.set()
    # --------------------------------------------------------------------------------------------------------------------------------------------------

    
    
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Destructor - Close the connection(s)
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __del__ (self):
        pass
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    
    
    
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Public GraphQL methods
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Queries
    def sentantAll (self, passthrough = {}, details = "id name"):   
        return {**passthrough, **self.__graphql_post(self.__sentant_all(details), {})}

    
    def sentantGet (self, id="", passthrough = {}, details = "id name"):
        return {**passthrough, **self.__graphql_post(self.__sentant_get_by_id(details), {"id": id})}
        
    def sentantGetByName (self, name = "", passthrough = {}, details = "id name"):
        return {**passthrough, **self.__graphql_post(self.__sentant_get_by_name(details), {"name": name})}   
    
    # Mutations
    def sentantLoad (self, definition, passthrough = {}, details = "id name"):
        return {**passthrough, **self.__graphql_post(self.__sentant_load(details), {"definition": definition})}
    
    def swarmLoad (self, definition, passthrough = {}, details = "id name"):
        return {**passthrough, **self.__graphql_post(self.__swarm_load(details), {"definition": definition})}
    
    def sentantSend (self, id, event, parameters = {}, passthrough = {}, details = "id name"):
        return self.__graphql_post(self.__sentant_send(details), {"id": id, "event": event, "parameters": json.dumps(parameters), "passthrough": json.dumps(passthrough)})
    
    def sentantSendByName (self, name, event, parameters = {}, passthrough = {}, details = "id name"):
        response = self.sentantGetByName(name, {}, details="id")
        if ("sentantGet" in response):
            try:
                id = response["sentantGet"]["id"]
                return self.__graphql_post(self.__sentant_send(details), {"id": id, "event": event, "parameters": json.dumps(parameters), "passthrough": json.dumps(passthrough)})
            except:
                return {}
        else:
            return {}

    def sentantUnload (self, id, passthrough = {}, details = "id name"):
        return {**passthrough, **self.__graphql_post(self.__sentant_unload(details), {"id": id})}
    
    def sentantUnloadByName (self, name, passthrough = {}, details = "id name"):
        response = self.sentantGetByName(name, {}, details="id")
        if ("sentantGet" in response):
            try:
                return {**passthrough, **self.__graphql_post(self.__sentant_unload(details), {"id": response["sentantGet"]["id"]})}
            except:
                return {}
        else:
            return {}
    
    def sentantUnloadAll (self, passthrough = {}):
        try:
            sentants = self.sentantAll()
            for sentant in sentants["sentantAll"]:
                return self.sentantUnload(sentant["id"], passthrough)
        except:
            return None
    
    # Subscriptions
    def awaitSignal (self, id, signal, callback=None, details="event parameters passthrough sentant { id name description }"):
        newEvent = threading.Event()
        self.__events.append(newEvent)
        newThread = threading.Thread(target=self.__subscribe, args=(self.__graphql_webs_url, id, signal, callback, details, newEvent, ))
        newThread.start()
    # --------------------------------------------------------------------------------------------------------------------------------------------------


        
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Static methods
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    @staticmethod
    def JSONPath(data, path):
        paths = path.split(".")
        currentData = data
        for index, subpath in enumerate(paths):
            if subpath == "[]" and isinstance(currentData, list):
                newCurrentData = []
                remaining_path = "" if index == len(paths)-1 else ".".join(paths[index+1:])
                for item in currentData:
                    newCurrentData.append(Reality2.JSONPath(item, remaining_path))
                return newCurrentData
            elif isinstance(currentData, list) and subpath.isdigit():
                currentData = currentData[int(subpath)]
            elif isinstance(currentData, dict):
                if subpath in currentData:
                    currentData = currentData[subpath]
                else:
                    return None
            else:
                return None
        return currentData
    # --------------------------------------------------------------------------------------------------------------------------------------------------

        
    
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Private methods
    # --------------------------------------------------------------------------------------------------------------------------------------------------

    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # A POST for using with GraphQL
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __graphql_post(self, query, variables):
        try:
            body = {
                "query": query,
                "variables": json.dumps(variables)
            }
            answer = requests.post(self.__graphql_http_url, data = body, verify = False)
            response = answer.json()
            if answer.status_code == 200:
                if "errors" in response:
                    return(response["errors"][0])
                else:
                    return(response["data"])
            else:
                return {}
        except:
            return {}
    # --------------------------------------------------------------------------------------------------------------------------------------------------

        
        
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Check the status of the websocket
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __check_status (self, message):
        message_dict = json.loads(message)
        if "payload" in message_dict:
            if "status" in message_dict["payload"]:
                if message_dict["payload"]["status"] == "ok":
                    return True
                else:
                    return False
            else:
                return False
        else:
            return False
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Define the heartbeat thread that keeps the websocket connection alive (to be called in it's own a thread)
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __heartbeat_thread (self, websocket, running: threading.Event):
        heartbeat = {
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": {},
            "ref": 0
        }
        
        while not running.is_set():
            for i in range(30):
                time.sleep(1)
                if running.is_set(): break
            websocket.send(json.dumps(heartbeat))
    # --------------------------------------------------------------------------------------------------------------------------------------------------

 

    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Scubscribe to the Node channel representing the sentant and signal
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __subscribe (self, server, sentantid, signal, callback, details, running: threading.Event):
        join_message = {
            "topic": "__absinthe__:control",
            "event": "phx_join",
            "payload": {},
            "ref": 0
        }
        
        subscribe = {
            "topic": "__absinthe__:control",
            "event": "doc",
            "payload": {
                "query": self.__await_signal(details),
                "variables": {
                    "id": sentantid,
                    "signal": signal
                }
            },
            "ref": 0
        }
        
        # Connect to the server, join the channel and subscribe to the sentant event
        if (self.__secure):
            # Create the SSL context
            ssl_context = ssl.create_default_context() 
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            
            with connect(server, ssl_context=ssl_context) as websocket:
                self.__after_connect(websocket, join_message, subscribe, sentantid, signal, callback, server, running)
        else:
            with connect(server) as websocket:
                self.__after_connect(websocket, join_message, subscribe, sentantid, signal, callback, server, running)
            
            
    def __after_connect(self, websocket, join_message, subscribe, sentantid, signal, callback, server, running: threading.Event):
        # Join the channel
        websocket.send(json.dumps(join_message))
        message = websocket.recv()
        if (self.__check_status(message)): 
            print(f"Joined: {server}")
        else:
            print(f"Failed to join: {server}")
            return
            
        # Subscribe to the Sentant and event    
        websocket.send(json.dumps(subscribe))
        message = websocket.recv()
        if (self.__check_status(message)): 
            print(f"Subscribed to {sentantid}|{signal}")
        else:
            print(f"Failed to subscribe to {sentantid}|{signal}")
            return
                    
        # Start the heartbeat thread
        threading.Thread(target=self.__heartbeat_thread, args=(websocket, running, )).start()
        
        # Listen for messages
        while not running.is_set():
            message = websocket.recv()
            message_json = json.loads(message)
            payload = message_json["payload"]
            
            if self.__check_status(message):
                pass #print(f"heartbeat")
            else:       
                if "result" in payload:
                    data = payload["result"]["data"]
                    if callback:
                        callback(data)
                elif "errors" in payload:
                    if callback:
                        callback(payload["errors"])
                else:
                    print(f"Received: {payload}")
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Await Signal definition
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __await_signal (self, details):
        return (
        """
        subscription AwaitSignal($id: UUID4!, $signal: String!) {
            awaitSignal(id: $id, signal: $signal) {
                """ + details + """
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------




    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Load Swarm definition
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __swarm_load (self, details):
        return (
        """
        mutation SwarmLoad($definition: String!) {
            swarmLoad(definition: $definition) {
                description
                name
                sentants {
                    """ + details + """
                }
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Send Event definition
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __sentant_send (self, details):
        return (
        """
        mutation SentantSend($id: UUID4!, $event: String!, $parameters: Json, $passthrough: Json) {
            sentantSend(id: $id, event: $event, parameters: $parameters, passthrough: $passthrough) {
            """ + details + """
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Load a Sentant definition
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __sentant_load (self, details):
        return (
        """
        mutation SentantLoad($definition: String!) {
            sentantLoad(definition: $definition) {
                """ + details + """
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Unload a Sentant
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __sentant_unload (self, details):
        return (
        """
        mutation SentantUnload($id: UUID4!) {
            sentantUnload(id: $id) {
                """ + details + """
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Get a Sentant's details
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __sentant_get_by_id (self, details):
        return (
        """
        query SentantGet($id: UUID4) {
            sentantGet(id: $id) {
                """ + details + """
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Get a Sentant's details
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __sentant_get_by_name (self, details):
        return (
        """
        query SentantGet($name: String) {
            sentantGet(name: $name) {
                """ + details + """
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------



    # --------------------------------------------------------------------------------------------------------------------------------------------------
    # Get all Sentant's details
    # --------------------------------------------------------------------------------------------------------------------------------------------------
    def __sentant_all (self, details):
        return (
        """
        query SentantAll {
            sentantAll {
                """ + details + """
            }
        }
        """
    )
    # --------------------------------------------------------------------------------------------------------------------------------------------------

# ------------------------------------------------------------------------------------------------------------------------------------------------------
