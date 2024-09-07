# Reality2

Reality2 is a distributed platform for 'sentient' digital agents.  We call them sentient because the digital agents can be aware of the network, physical and electronic environment they exist in.  These, we call 'Sentants' - and a group of Sentants is a Swarm.

Small devices running Linux 'run' the Digital Agents, and they are aware of the network and device they are running on.  These devices, or 'Nodes', can form 'Clusters' in what we call a Transient Network.

Users interact with the digital agents directly, so the focus of attention is at the Sentant level, not the device level.

That said, at least initially, internet connected devices such as browsers, which communicate using TCP-IP, work at the device level, so the interaction with the Sentants does have to go via the node.

More detailed documentation can be found [here](https://github.com/reality-two/reality2-documentation).

## GraphQL

Presently, we use a GraphQL API with queries, mutations and subscriptions.  I'll get a Postman definition file in here soon, though of course you can create your own using introspection.

## Sentant definition files

When a Node is started, it is empty of Sentants.  You load the Sentants from a text file (see the definitions folder) in YAML, TOML or JSON format.  This is somewhat equivalent to a webserver loading web-page definitions, except that Sentants can be loaded at any time.

## Clients

In the python folder is some example client code that uses the definitions in the definitions folder.

In the XR folder, there is some example client code and visualisation for godot, and soon also for unity, and perhaps later threejs.

In the node-red folder, there is some example setup for that graphical tool.  You will need to have node-red running first, of course.

## Plans

There are many plans for this platform which will be made public in due course.  For now, this is very early alpha stage.

## Some setup notes

1. In the layer above the main Reality2 folder, create a file called OPENAI_API_KEY.txt.  Put in there your OpenAPI key.  This is used by some of the python and node.red scripts to setup Sentants that use OpenAI.  It is not included directly in the code for security reasons.

2. If you want to generate new certificates for your node (recommended), then there is a convenient script in the `certs` folder called `generate_certificates`.  This creates new self-signed certificates for this instance of Reality2.  If you are wanting to run this on a named server, then you can create certificates in the usual way with your service provider.

    The Certificates (selfsigned.pem and selfsigned_key.pem) are created, and since this is a symbolically linked folder, they are in the correct place.  However, the intermediate certificates and private keys are packed into a zipped folder with a date and time.  You should copy this elsewhere (and not leave it where a hacker could find it).

4. Optional, but recommended: edit your /etc/hosts file to include the following line - it will allow you to use the domain name reality2 or reality2.local in the webbrowser.  Obviously, you will need admin privileges:
    ```
    127.0.0.1   reality2.local      reality2
    ```
