# Terminology

#### Reality2

- The name for the overall platform.

#### Node

- A piece of hardware that runs the Reality2 client.  In the reference implementation, this is a unix based tool (usually Linux), using the Erlang BEAM engine.

#### Sentant

- A Sentant is a Sentient Digital Agent, the core unit of the Reality2 platform.  It has many properties - see the section on Sentants for more details.

#### Swarm

- Groups of Sentants work together in Swarms.  Swarms typically belong to a single user, and may encompass Sentants across several Nodes.  Swarms use the Transient Networks to find other Swarms and to initiate interaction with other Nodes.

#### Transient Network

- Each node interacts with other nodes through the networks it connects to, in particular wireless networks such as Bluetooth and Wifi.  Sentants are aware of the networks they are on, and actively use them to establish connections for their users.