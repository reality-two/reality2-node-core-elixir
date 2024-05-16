# Queries

### sentantGet

- Get a specific Sentant by name or ID
- Returns a Sentant
- Example:

```graphql
query SentantGet($id: UUID4) {
    sentantGet(id: $id) {
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
```

```graphql
query SentantGet($name: String) {
    sentantGet(name: $name) {
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
```

Of course, you don't have to request all the information to be returned.  Perhaps you only want the Sentant ID, in which case you would send:

```graphql
query SentantGet($name: String) {
    sentantGet(name: $name) {
        id
    }
}
```

### sentantAll

- Get an array of all the Sentants on a Node
- Returns an array of Sentants
- Example:

```graphql
query SentantAll {
    sentantAll {
        name
        description
        events {
            event
            parameters
        }
        signals
    }
}
```

