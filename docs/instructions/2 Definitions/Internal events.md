# Internal Events

Sometimes, a client App wants to know that is going internally on the Reality2 Node, or a Sentant wants to take action when certain situations occur such as joining and leaving Transient Networks.

To catch these, there is an event called `__internal` that sends various details as its parameters.  If you want to make these events available outside the Node for example, for a WebApp, you need to pass these through as Signals.

```json
{
    "sentant": {
        "name": "monitor",
        "automations": [
            {
                "name": "Monitor",
                "transitions": [
                    {
                        "event": "__internal",
                        "actions": [
                            {
                                "command": "signal",
                                "parameters": {
                                    "public": true,
                                    "event": "internal"
                                }
                            }
                        ]
                    }
                ]
            }
        ]
    }
}
```

When awaiting the Signal `internal`, you would get the following when Sentants are created and deleted:

```json
{'id': '8195efdc-f87e-11ee-9a01-18c04dee389e', 'name': 'Light Switch', 'event': 'deleted'}
{'id': '81961d36-f87e-11ee-93e6-18c04dee389e', 'name': 'Light Bulb', 'event': 'deleted'}
{'id': 'ad7d5e5a-f87e-11ee-b612-18c04dee389e', 'name': 'Light Switch', 'event': 'created'}
{'id': 'ad7d8272-f87e-11ee-b007-18c04dee389e', 'name': 'Light Bulb', 'event': 'created'}
```

Unlike the other GraphQL commands, you only get the `id` and `name` of the Sentant involved.  If you need to know more, the `sentantGet` command will need to be invoked.  This is to ensure privacy.

### Events

#### deleted

When a sentant is deleted.

### created

When a sentant is created.



