# Sentants

As with Swarms, Sentants are defined through YAML, JSON or TOML files.  YAML and TOML are easier to read, and you can add comments, but JSON is more precise.

The python folder contains some examples.

Sentants have some basic features to define them.  At the moment, these are quite limited, but later we will be adding more.  Here is the core structure of a Sentant.  The Plugins and Automations Sections are detailed further in subsequent files.

Note that the name of a Sentant has to be unique on the node.

```JSON
{
    "sentant": {
        "name": "Test Parameters",
        "keys": {
            "encryption_key": "__encryption_key__",
            "decryption_key": "__decryption_key__"
        },
        "data": {
            "image": "file(reality2_bee.png)",

            "var1": "A String",
            "var2": 123,
            "var3": [1, 2, 3],
            "var4": { "key1": "value1", "key2": "value2" },
            "var5": { "key1": [ { "a": "value1", "b": "value2" }, { "a": "value3", "b": "value4" } ], "key2": "value2" }
        },
        "automations": [
            {
                "name": "Automation1",
                "transitions": [
                    {
                        "public": true, "event": "get_image",
                        "actions": [
                            { "command": "set",    "parameters": { "key": "image", "value": { "data": "image" } } },
                            { "command": "signal", "parameters": { "event": "image", "public": true } }
                        ]
                    },
                    {
                        "public": true, "event": "Event1",
                        "parameters": { "param1": "string", "param2": "number" },                        
                        "actions": [
                            { "command": "set",    "parameters": { "key": "var4", "value": { "data": "var4" } } },
                            { "command": "signal", "parameters": { "event": "response", "public": true } }
                        ]
                    },
                    {
                        "public": true, "event": "Event2",
                        "parameters": { "param1": "string", "param2": "number" },
                        "actions": [
                            { "command": "set",    "parameters": { "key": "var1", "value": { "data": "var1" } } },
                            { "command": "set",    "parameters": { "key": "new_param", "value": "A new order has arisen" } },
                            { "command": "set",    "parameters": { "key": "param1", "value": "overwritten value" } },
                            { "command": "set",    "parameters": { "key": "var5", "value": { "data": "var5" } } },
                            { "command": "set",    "parameters": { "key": "param2", "value": { "jsonpath": "var5.key1.[].a" } } },
                            { "command": "signal", "parameters": { "event": "response", "public": true } }
                        ]
                    }
                ]
            }
        ]
    }
}
```

```YAML
sentant:
  name: Test Parameters
  keys:
    encryption_key: __encryption_key__
    decryption_key: __decryption_key__
  data:
    image: file(reality2_bee.png)
    var1: A String
    var2: 123
    var3:
      - 1
      - 2
      - 3
    var4:
      key1: value1
      key2: value2
    var5:
      key1:
        - a: value1
          b: value2
        - a: value3
          b: value4
      key2: value2
  automations:
    - name: Automation1
      transitions:
        - public: true
          event: get_image
          actions:
            - command: set
              parameters:
                key: image
                value:
                  data: image
            - command: signal
              parameters:
                event: image
                public: true
        - public: true
          event: Event1
          parameters:
            param1: string
            param2: number
          actions:
            - command: set
              parameters:
                key: var4
                value:
                  data: var4
            - command: signal
              parameters:
                event: response
                public: true
        - public: true
          event: Event2
          parameters:
            param1: string
            param2: number
          actions:
            - command: set
              parameters:
                key: var1
                value:
                  data: var1
            - command: set
              parameters:
                key: new_param
                value: A new order has arisen
            - command: set
              parameters:
                key: param1
                value: overwritten value
            - command: set
              parameters:
                key: var5
                value:
                  data: var5
            - command: set
              parameters:
                key: param2
                value:
                  jsonpath: 'var5.key1.[].a'
            - command: signal
              parameters:
                event: response
                public: true
```

```TOML
[sentant]
name = "Test Parameters"

  [sentant.keys]
  encryption_key = "__encryption_key__"
  decryption_key = "__decryption_key__"

  [sentant.data]
  image = "file(reality2_bee.png)"
  var1 = "A String"
  var2 = 123
  var3 = [ 1, 2, 3 ]

    [sentant.data.var4]
    key1 = "value1"
    key2 = "value2"

    [sentant.data.var5]
    key2 = "value2"

      [[sentant.data.var5.key1]]
      a = "value1"
      b = "value2"

      [[sentant.data.var5.key1]]
      a = "value3"
      b = "value4"

  [[sentant.automations]]
  name = "Automation1"

    [[sentant.automations.transitions]]
    public = true
    event = "get_image"

      [[sentant.automations.transitions.actions]]
      command = "set"

        [sentant.automations.transitions.actions.parameters]
        key = "image"

          [sentant.automations.transitions.actions.parameters.value]
          data = "image"

      [[sentant.automations.transitions.actions]]
      command = "signal"

        [sentant.automations.transitions.actions.parameters]
        event = "image"
        public = true

    [[sentant.automations.transitions]]
    public = true
    event = "Event1"

      [sentant.automations.transitions.parameters]
      param1 = "string"
      param2 = "number"

      [[sentant.automations.transitions.actions]]
      command = "set"

        [sentant.automations.transitions.actions.parameters]
        key = "var4"

          [sentant.automations.transitions.actions.parameters.value]
          data = "var4"

      [[sentant.automations.transitions.actions]]
      command = "signal"

        [sentant.automations.transitions.actions.parameters]
        event = "response"
        public = true

    [[sentant.automations.transitions]]
    public = true
    event = "Event2"

      [sentant.automations.transitions.parameters]
      param1 = "string"
      param2 = "number"

      [[sentant.automations.transitions.actions]]
      command = "set"

        [sentant.automations.transitions.actions.parameters]
        key = "var1"

          [sentant.automations.transitions.actions.parameters.value]
          data = "var1"

      [[sentant.automations.transitions.actions]]
      command = "set"

        [sentant.automations.transitions.actions.parameters]
        key = "new_param"
        value = "A new order has arisen"

      [[sentant.automations.transitions.actions]]
      command = "set"

        [sentant.automations.transitions.actions.parameters]
        key = "param1"
        value = "overwritten value"

      [[sentant.automations.transitions.actions]]
      command = "set"

        [sentant.automations.transitions.actions.parameters]
        key = "var5"

          [sentant.automations.transitions.actions.parameters.value]
          data = "var5"

      [[sentant.automations.transitions.actions]]
      command = "set"

        [sentant.automations.transitions.actions.parameters]
        key = "param2"

          [sentant.automations.transitions.actions.parameters.value]
          jsonpath = "var5.key1.[].a"

      [[sentant.automations.transitions.actions]]
      command = "signal"

        [sentant.automations.transitions.actions.parameters]
        event = "response"
        public = true

```

