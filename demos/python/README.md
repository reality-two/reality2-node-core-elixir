# Python Demos

This folder contains some sentant and swarm definitions, as well as some code written in python to load them.

The library `reality2.py` manages the GraphQL API, and the python script `load_sentant.py` can used to load any sentant definition, and provide some basic command-line style interactivity.

## Prerequisites

To run these, use python3, and install the following libraries:

```bash
pip install gql
pip install requests
pip install websockets
pip install getkey
pip install ruamel.yaml
pip install toml
```

## Encryption keys and other private data

Some of the scripts require encryption / decryption keys, and API keys.  These may be stored in a file called `variables.json` at the level above the root directory for the node.

```json
{
    "__openai_api_key__": "YOUR OPENAI API KEY",
    "__encryption_key__": "Base64 encoded key",
    "__decryption_key__": "Base64 encoded key"
}
```

The encryption and decryption keys are used to protect data stored in the database using the `reality2_backup` plugin.  They can be created like this:

```python
key = os.random(32)
encryption_key = base64.b64encode(key).decode('utf-8')
decryption_key = base64.b64encode(key).decode('utf-8')
```

At present, the algorithm uses symmetric encryption so both the keys are the same.  These should be stored safely somewhere.

### Sentant-wide encryption keys

The encryption keys are placed at the top level of the Sentant, for example:

```yaml
sentant:
  name: Test Backup
  description: Test data storage and retrieval from the database
  keys:
    encryption_key: __encryption_key__
    decryption_key: __decryption_key__

  automations:
    ...
```

or

```json
{
    "sentant": {
        "name": "Test Parameters",
        "keys": {
            "encryption_key": "__encryption_key__",
            "decryption_key": "__decryption_key__"
        },
        "automations": [ ... ]
    }
}
```

## Load a Sentant or Swarm

For convenience, you can use the bash script `load` to load either a Sentant or a Swarm, with the following set of parameters.

```bash
./load sentant_or_swarm_definition node port
```

This calls one of the below Python functions.  If no node is given, then `localhost` is assumed.  If no port is given, `4005` is assumed.  For example:

```bash
./load swarm_light_and_switch.json localhost 4005
```

## Loading a Sentant

To load a sentant, the following may be used:

```bash
python3 load_sentant.py sentant_definition node port
```

Where `sentant_definition` is the name of the file to load that contains the sentant - this may be yaml, json or toml formatted, and `node` is either the IP address or domain name of the Reality2 node to load the sentant onto.  If no node is given, then `localhost` is assumed.  If no port is given, `4005` is assumed.

So, for example:
```bash
python3 load_sentant.py sentant_chatgpt.yaml localhost 4005
```

```text
Unloading existing Sentant named " Ask Question "
Joined: wss://localhost:4005/reality2/websocket
Subscribed to a0aad5dc-3437-11ef-9405-de59b61f7ba3|debug
Joined: wss://localhost:4005/reality2/websocket
Subscribed to a0aad5dc-3437-11ef-9405-de59b61f7ba3|ChatGPT Answer
---------- Send Events ----------
 Press [ 0 ] for { Ask ChatGPT {'question': 'string'} }
 Press [ h ] for help.
 Press [ q ] to quit.
---------------------------------
Type in a string for question : What is the meaning of life?
Sending event [ Ask ChatGPT ]
ChatGPT Answer  :  {'answer': "The meaning of life is a deeply philosophical question that has been debated throughout human history. Different people and cultures have different perspectives on the meaning of life. Some find meaning in religion, others in relationships and connections, and some in personal fulfillment or contribution to society. It's ultimately a subjective and personal question, and the answer can vary for each individual.", 'question': 'What is the meaning of life?'}  ::  {}
```

## Loading a Swarm

Similarly, to load a Swarm of Sentants, the following may be used:

```bash
python3 load_swarm.py swarm_definition node
```

Where `swarm_definition` is the name of the file to load that contains the swarm of sentants - this may be yaml, json or toml formatted, and `node` is either the IP address or domain name of the Reality2 node to load the sentant onto.  If no node is given, then `localhost` is assumed.  If no port is given, `4005` is assumed.

So, for example:
```bash
python3 load_swarm.py swarm_light_and_switch.json localhost
```

```text
Unloading existing Sentants named " ['Light Switch', 'Light Bulb'] "
Joined: wss://localhost:4005/reality2/websocket
Subscribed to afc0fae0-342a-11ef-ad8b-de59b61f7ba3|debug
Joined: wss://localhost:4005/reality2/websocket
Joined: wss://localhost:4005/reality2/websocket
Joined: wss://localhost:4005/reality2/websocket
Subscribed to afc121f0-342a-11ef-a798-de59b61f7ba3|debug
Subscribed to afc121f0-342a-11ef-a798-de59b61f7ba3|Light off
Subscribed to afc121f0-342a-11ef-a798-de59b61f7ba3|Light on
[{'event': 'Toggle Switch', 'parameters': {}, 'id': 'afc0fae0-342a-11ef-ad8b-de59b61f7ba3'}]
---------- Send Events ----------
 Press [ 0 ] for { Toggle Switch {} }
 Press [ h ] for help.
 Press [ q ] to quit.
---------------------------------
Sending event [ Toggle Switch ]
Light on  :  {'result': 'ok'}  ::  {}
Light off  :  {'result': 'ok'}  ::  {}
```
