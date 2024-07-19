# Example

```yaml
# ------------------------------------------------------------------------------------------------------
# A Sentant to illustrate how a plugin to an external API can be used.
#
# Author: Dr. Roy C. Davies
# Date: 2024-01-13
# Contant: http://roycdavies.github.io
# ------------------------------------------------------------------------------------------------------

sentant:
  # ----------------------------------------------------------------------------------------------------
  # Sentant details
  # ----------------------------------------------------------------------------------------------------
  name: Ask Question
  description: Ask ChatGPT a question.

  # ----------------------------------------------------------------------------------------------------
  # Plugins (A list, so begin with a dash)
  # ----------------------------------------------------------------------------------------------------
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
  # ----------------------------------------------------------------------------------------------------

  # ----------------------------------------------------------------------------------------------------
  # Automations (Also a list, so begin with a dash)
  # ----------------------------------------------------------------------------------------------------
  automations:
    - name: ChatGPT # This is the name of the automation.
      description: This is a test automation. # This is the description of the automation.
      transitions: # This is a list of transitions, so begin with a dash.

          # Send a message (question) to ChatGPT, initiated from an event.
        - event: "Ask ChatGPT"
          parameters: 
            question: string
          public: true
          actions:
            - plugin: com.openai.api
              command: send

          # Get the answer from ChatGPT and send out as a signal.
        - event: chatgpt_response
          actions:
            - command: set
              parameters:
                key: question
            - command: signal # sends a signal to subscribed clients
              public: true
              parameters:
                event: "ChatGPT Answer"
  # ----------------------------------------------------------------------------------------------------
```

