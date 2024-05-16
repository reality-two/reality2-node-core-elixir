# Plugins

One of the core features of Reality2 is to be able to add new features through plugins.  We expect over time that there will become a marketplace of plugins that you can use for your own Sentants.

There are two types of plugin - inbuilt and external.

Only external plugins are defined in the Sentant or Swarm definition files.

### Naming Convention

When defining plugins, both inbuilt and external, you can call them whatever you like, however it is wise to use a naming convention that will ensure there are no duplicate names globally.  We have decided that a reverse domain name convention is to be adopted, for example `ai.reality2.geospatial` is for the Reality Geospatial plugin.

### Inbuilt plugins

Inbuilt plugins are ones that are defined as part of the code that is running on the Node.  These are Elixir Apps with a predetermined interface and are using the resources of the Node.  Examples include many of the core features of the Reality2 node such as a Web interface, a Geospatial module, Authentication, Integration with IoT device hardware and the Pathing Name System.

The plugin is built in Elixir, and used in the Automations section.  If you want to learn how to create your own inbuilt plugins, [look here](Inbuilt%20plugin%20HOWTO.md).

### External plugins

External plugins are interfaces to capabilities that are external to the Node, accessible through an API.  The entire definition of the plugin is included in the definition file - lets take an example for [zenquote](https://zenquote.io).  You can read about their API definition [here](https://docs.zenquotes.io/zenquotes-documentation/).

```YAML
plugins:
  - name: io.zenquotes.api
    url: https://zenquotes.io/api/random
    method: GET
    headers:
      "Content-Type": "application/json"        
    output:
      key: answer
      value: "0.q"
      event: zenquote_response
```

```TOML
[[plugins]]
name = "io.zenquotes.api"
url = "https://zenquotes.io/api/random"
method = "GET"

  [plugins.headers]
  Content-Type = "application/json"

  [plugins.output]
  key = "answer"
  value = "0.q"
  event = "zenquote_response"
```

```JSON
{
  "plugins": [
    {
      "name": "io.zenquotes.api",
      "url": "https://zenquotes.io/api/random",
      "method": "GET",
      "headers": {
        "Content-Type": "application/json"
      },
      "output": {
        "key": "answer",
        "value": "0.q",
        "event": "zenquote_response"
      }
    }
  ]
}
```

As you can see, there are several key sections, namely:

- **name** - the reverse DNS notation name.  You will use that in the Automations section later.
- **url** - the URL of the API
- **method** - the method for the API - usually GET or POST
- **headers** - some relevant headers.  Quite often, you will need to include some form of authentication key.
- **body** - when using POST, what the body of the message looks like (see example below).
- **output** - what to do with the results that come back from the API call.  The result is sent as an event with parameters.

  - **event** - the event to send to the Automations on this Sentant
  - **key** - the name to use for the answer
  - **value** - a simplified JSON path.  Most often, the result returned will be in a JSON format, but may have several layers to get through before you find the actual data you want.  The simplified JSON path is a dot seperated string of words and numbers.  The words are the JSON keys, and the numbers are the index into an array.  So, in the example above, the quote we want is the first element of an array ie the '0' position, with a key name 'q'.


#### A more complex example

This example is taken from the python folder, and shows how you might create a plugin for ChatGPT.  To understand this, you need to look at the [ChatGPT API definition](https://openai.com/blog/introducing-chatgpt-and-whisper-apis).

```YAML
plugins:
  - name: com.openai.api # This is the name of the plugin, used in the Automation below
    url: https://api.openai.com/v1/chat/completions # This is the URL to the API endpoint
    method: POST # This is the HTTP method to use

    # These are the headers to send (see ChatGPT API documentation)
    headers:
      "Content-Type": "application/json"
      # This is a secret, so it is not shown here (replace before passing to Reality2)
      "Authorization": "Bearer __openai_api_key__"

    # This is the body to send (see ChatGPT API documentation).  Note the __message__ placeholder.
    body:
      model: "gpt-3.5-turbo-1106"
      messages:
        - role: "system"
          content: "You are a helpful assistant."
        - role: "user"
          content: __question__

    # How to process the output from the API.  The value is a simplified JSON path expression.
    output:
      key: answer
      value: "choices.0.message.content"
      event: chatgpt_response
```

```TOML
[[plugins]]
name = "com.openai.api"
url = "https://api.openai.com/v1/chat/completions"
method = "POST"

  [plugins.headers]
  Content-Type = "application/json"
  Authorization = "Bearer __openai_api_key__"

  [plugins.body]
  model = "gpt-3.5-turbo-1106"

    [[plugins.body.messages]]
    role = "system"
    content = "You are a helpful assistant."

    [[plugins.body.messages]]
    role = "user"
    content = "__question__"

  [plugins.output]
  key = "answer"
  value = "choices.0.message.content"
  event = "chatgpt_response"
```

```JSON
{
  "plugins": [
    {
      "name": "com.openai.api",
      "url": "https://api.openai.com/v1/chat/completions",
      "method": "POST",
      "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer __openai_api_key__"
      },
      "body": {
        "model": "gpt-3.5-turbo-1106",
        "messages": [
          {
            "role": "system",
            "content": "You are a helpful assistant."
          },
          {
            "role": "user",
            "content": "__question__"
          }
        ]
      },
      "output": {
        "key": "answer",
        "value": "choices.0.message.content",
        "event": "chatgpt_response"
      }
    }
  ]
}
```



