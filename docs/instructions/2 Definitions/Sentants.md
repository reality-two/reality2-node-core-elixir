# Sentants

As with Swarms, Sentants are defined through YAML, JSON or TOML files.  YAML and TOML are easier to read, and you can add comments, but JSON is more precise.

The python folder contains some examples.

Sentants have some basic features to define them.  At the moment, these are quite limited, but later we will be adding more.  Here is the core structure of a Sentant.  The Plugins and Automations Sections are detailed further in subsequent files.

Note that the name of a Sentant has to be unique on the node.

```YAML
sentant:
  name: The unique Sentant name
  description: The Sentant description
  plugins:
    # plugin details
  automations:
    # automations details
  data:
    # JSON data object.
```

```TOML
[sentant]
name = "The unique Sentant name"
description = "The Sentant description"

    # Plugin details
    [[sentant.plugins]]

    # Automation details
    [[sentant.automations]]

    # Data
    [[sentant.data]]
```

```JSON
{
  "sentant": {
    "name": "The unique Sentant name",
    "description": "The Sentant description",
    "plugins": [ ],
    "automations": [ ],
    "data": { }
  }
}
```

