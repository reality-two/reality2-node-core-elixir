# Subscriptions

Queries and Mutations are sent to the Reality2 Node using standard HTTP GET and POST respectively.  Subscriptions are a little more complicated in that they require the setting up of a WebSocket between the Reality2 Node and the receiving device.

In the reference implementation described here, we are using the Phoenix Framework server, with the Absinthe implementation of Websockets to communicate with Phoenix Channels.

Connecting to a Phoenix Channel is a multi-step process.  The libraries created for the various languages shown here automate and hide this process.

### Step 1 - open the websocket

Most languages require an initial command to open the websocket.  in python, using the websockets.sync.client, it looks like this:

```python
ssl_context = ssl.create_default_context() 
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
            
with connect(server, ssl_context=ssl_context) as websocket:
    # Rest of the code here
```

### Step 2 - send a join message

Once the websocket is open, you have to send a specific message as a request to join:

```json
{
    "topic": "__absinthe__:control",
    "event": "phx_join",
    "payload": {},
    "ref": 0
}
```

### Step 3 - subscribe to the channel

If that is successful, you then send the subscription request:

```json
{
    "topic": "__absinthe__:control",
    "event": "doc",
    "payload": {
        "query": subscription,
        "variables": {
            "id": sentantid,
            "signal": signal
        }
    },
    "ref": 0
}
```

where `subscription` is:

```graphql
subscription AwaitSignal($id: UUID4!, $signal: String!) {
    awaitSignal(id: $id, signal: $signal) {
       event
       parameters
       passthrough
       sentant {
            name
            id
            description
            events {
                event
                parameters
            }
            signals
       }
    }
}
```

Note here the parameters come from the action that sent the signal and the passthrough comes ultimately from the sentantSend call.

### Step 4 - set up a 'heartbeat'

Websockets will time-out after a while unles a message is sent at regular intervals.  Typically, this is every 30 seconds.  The message to send is:

```json
{
    "topic": "phoenix",
    "event": "heartbeat",
    "payload": {},
    "ref": 0
}
```

### Step 5 - Wait for a response

Once set up, the websocket will need to be monitored for data coming in, that then should be routed to the appropriate callback function that was sent through when the subscription was set up.