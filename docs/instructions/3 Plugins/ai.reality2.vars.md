# Reality2 Variables Plugin

### Description

The Variables plugin allows you to create kay/value pairs in memory that are remembered from one event to the next.  This might be useful, for example, for a counter that is activated each time the event fires.


### Definition

The core variable functions, presently, are set, get, all, delete and clear.

#### set

Sets the variable.

```yaml
- command: set
  plugin: ai.reality2.vars
  parameters: 
    key: "The Answer"
    value: 42
```

#### get

Gets the variable, and inserts the key/value into the data stream.

```yaml
- command: get
  plugin: ai.reality2.vars
  parameters: 
    key: "The Answer"
```

#### all

Gets all the currently stored variables.

```yaml
- command: all
  plugin: ai.reality2.vars
```

#### delete

Deletes the key/value pair.

```yaml
- command: delete
  plugin: ai.reality2.vars
  parameters: 
    key: "The Answer"
```

#### clear

Clears (deletes) all the variables for this Sentant.

```yaml
- command: clear
  plugin: ai.reality2.vars
```
