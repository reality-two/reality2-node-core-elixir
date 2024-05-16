# Swarms

Swarms are groups of Sentants, defined for convenience in one file.  Presently, the Reality2 Node doesn't store any Swarm information, but this will change soon.  Swarms don't have to be defined together in one file, and in fact the way a Swarm is defined is related more to how the various Sentants within the Swarm interact with each other.

Below are equivalent definitions of the Swarm layout in YAML, TOML and JSON showing the main categories.  Which one you prefer to use is a matter of personal preference.

```YAML
swarm:
  name: The name of your Swarm
  description: Some suitable description of what your Swarm does
  sentants: # The array of Sentants
    - name: Sentant1
      # More Sentant details
    - name: Sentant2
      # More Sentant details
```

```TOML
[swarm]
name = "The name of your Swarm"
description = "Some suitable description of what your Swarm does"

  [[swarm.sentants]]
  name = "Sentant1"

  [[swarm.sentants]]
  name = "Sentant2"

```

```JSON
{
  "swarm": {
    "name": "The name of your Swarm",
    "description": "Some suitable description of what your Swarm does",
    "sentants": [
      {
        "name": "Sentant1"
      },
      {
        "name": "Sentant2"
      }
    ]
  }
}
```