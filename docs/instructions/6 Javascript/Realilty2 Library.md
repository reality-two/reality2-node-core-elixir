# Reality2 Library

For your convenience, there is a Reality2 library for working with the GraphQL interface called `reality2.ts`.  Many parameters have default values as detailed below.

## Functions

#### `constructor (domain_name, port, ssl = true)`

- When the Reality2 GraphQL Object is created, the domain name, port and whether to use SSL is established.

#### `sentantAll (passthrough = {}, details = "id name")`

- Return all the Sentants on the Reality2 Node.  Details is a string for the details to be returned by the command.  Passthrough is an object that comes through to the output unchanged.

#### `sentantGet (id, passthrough = {}, details = "id name")`

- Return a given Sentant given the ID.  Details is a string for the details to be returned by the command.  Passthrough is an object that comes through to the output unchanged.

#### `sentantGetByName(name passthrough = {}, details = "id name")`

- Return a given Sentant given the Name.  Details is a string for the details to be returned by the command.  Passthrough is an object that comes through to the output unchanged.

#### `sentantLoad (definition, passthrough = {}, details = "id name")`

- Load a Sentant from a definition string.  Returns the new Sentant.  Details is a string for the details to be returned by the command.  Passthrough is an object that comes through to the output unchanged.

#### `swarmLoad (definition, passthrough = {}, details = "id name")`

- Load a Swarm from a definition String.  Returns an Array of the new Sentants.  Details is a string for the details to be returned by the command.  Passthrough is an object that comes through to the output unchanged.

#### `sentantSend (id, event, parameters, passthrough = {}, details = "id name")`

- Send an event and parameters to a Sentant.  Event is a string, Parameters is JSON. Returns the Sentant.  Details is a string for the details to be returned by the command.  Passthrough is an object that is sent along with the parameters, and might eventually come out as passthrough parameters from a signal.

#### `sentantUnload (id, passthrough = {}, details = "id name")`

- Unload a Sentant, and return the details.  Details is a string for the details to be returned by the command.  Passthrough is an object that comes through to the output unchanged.

#### `awaitSignal (id, signal, callback)`

- Sets up an await Signal Subscription using WebSockets.  The function referred to in callback is called when new data comes from that Sentant for that Signal.  Parameters and Passthrough come from the action that initiated the signal.  Details in this case defines what will be returned along with the signal, not what returns directly from the awaitSignal call.

#### `JSONPath (data, path)`

- A Static method for extracting data from a complex JSON object.  The path is a dot-separated series of string and numbers - the strings represent the keys, and numbers the positions in arrays.  So, "sentantAll.0.id" would return the id of the first element of the sentantAll array.  If at any point in the path, there is no match, the result returned is None.

## Usage

#### Step 1 - Import the Reality2 GraphQL Library

```javascript
import R2 from "./lib/reality2";
```

#### Step 2 - Create a connection

```javascript
let r2_node = new R2(window.location.hostname, 4005);
```

#### Step 3 - Load a Sentant (or a Swarm)

```javascript
let result = r2_node.sentantLoad(definition)
id = R2.JSONPath(result, "sentantLoad.id")
```

#### Step 4 - Subscribe to a signal

```javascript
r2_node.awaitSignal(id, "Zenquote Response", printout);
```

#### Step 5 - Send an event

```javascript
r2_node.sentantSend(id, "Get Zenquote")
```

#### Step 6 - Close the connection

```javascript
r2_node.close()
```

## 