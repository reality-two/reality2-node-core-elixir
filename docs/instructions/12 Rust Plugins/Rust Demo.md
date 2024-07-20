# Rust Plugin Demo

## Introduction

This section continues on from the Plugins section for adding a new Reality2 built-in plugin, so follow the steps there first to set up the Reality2 Plugin.

Note that the code described here is already available in the rustdemo plugin included with the repository, therefore you can use that as a guide.

## Steps

#### Install Rust

It hardly goes without saying that to be able to compile Rust code, you need to have installed Rust.  The best place to see how to do that is [here](https://www.rust-lang.org/tools/install).

#### Add rustler as a dependency

In the plugin's `mix.exs`, add the dependency:

```elixir
  defp deps do
    [
      {:reality2, in_umbrella: true},
      {:rustler, "~> 0.34.0"} # <---------- HERE
    ]
  end
  ```

and do `mix deps.get`.

#### Generate the NIF

Inside `apps/ai.reality2.rustdemo` (or whatever your plugin is called), do:

```bash
mix rustler.new
```

You will be asked for the Module Name `AiReality2Rustdemo` and the NIF name `aireality2rustdemo` (or whatever is appropriate for your plugin).

#### Write the Rust program

In the file `lib.rs` (in the `native/aireality2rustdemo/src` folder), add the required functionality, for example:

```rust
#[rustler::nif]
fn add(a: f64, b: f64) -> f64 {
    a + b
}

#[rustler::nif]
fn subtract(a: f64, b: f64) -> f64 {
    a - b
}

rustler::init!("Elixir.AiReality2Rustdemo.Action");
```

Note the line at the bottom that refers to the Elixir stub (defined below).

#### Create the Elixir stub

There needs to be the corresponsing Elixir code that then calls the Rust code, for example (in the `lib/ai_reality2_rustdemo` folder, in the file `action.ex`):

```elixir
defmodule AiReality2Rustdemo.Action do
  use Rustler, otp_app: :ai_reality2_rustdemo, crate: "aireality2rustdemo"

  # When your NIF is loaded, it will override these functions.
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def subtract(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
```

#### Make available as an action

In the `main.ex` file, you can now use the Rust functions as if they are Elixir functions.  For example:

```elixir
def sendto(_sentant_id, command_and_parameters) do
    command = R2Map.get(command_and_parameters, :command)
    parameters = R2Map.get(command_and_parameters, :parameters)
    value1 = R2Map.get(parameters, "value1") |> Convert.to_float()
    value2 = R2Map.get(parameters, "value2") |> Convert.to_float()

    case command do
    "add" ->
        {:ok, %{answer: AiReality2Rustdemo.Action.add(value1, value2)}}
    "subtract" ->
        {:ok, %{answer: AiReality2Rustdemo.Action.subtract(value1, value2)}}
    _ ->
        {:error, :unknown_command}
    end
end
```

#### Test

To test, you will find a Sentant definition in the python demos folder:

```json
{
    "sentant": {
        "name": "Test Rust Plugin",
        "automations": [
            {
                "name": "Automation1",
                "transitions": [
                    {
                        "public": true, "event": "add",
                        "parameters": { "value1": "number", "value2": "number" },
                        "actions": [
                            { "plugin": "ai.reality2.rustdemo", "command": "add" },
                            { "command": "signal", "parameters": { "event": "result", "public": true } }
                        ]
                    },
                    {
                        "public": true, "event": "subtract",
                        "parameters": { "value1": "number", "value2": "number" },
                        "actions": [
                            { "plugin": "ai.reality2.rustdemo", "command": "subtract" },
                            { "command": "signal", "parameters": { "event": "result", "public": true } }
                        ]
                    }
                ]
            }
        ]
    }
}
```

Running this, you should get ouput as follows:

```text
reality2-node-core-elixir/demos/python on  main [!?] via 🐍 v3.10.12 
❯ ./load sentant_rust_plugin_test.json 
Unloading existing Sentant named " Test Rust Plugin "
Joined: wss://localhost:4005/reality2/websocket
Joined: wss://localhost:4005/reality2/websocket
Subscribed to b376b78c-46e1-11ef-aaee-8ce9ee90fd85|debug
Subscribed to b376b78c-46e1-11ef-aaee-8ce9ee90fd85|result
---------- Send Events ----------
 Press [ 0 ] for { add {'value2': 'number', 'value1': 'number'} }
 Press [ 1 ] for { subtract {'value2': 'number', 'value1': 'number'} }
 Press [ h ] for help.
 Press [ q ] to quit.
---------------------------------
0 1 h q > 0

Type in a number for value2 : 10
Type in a number for value1 : 20
SEND   : [ add ]

SIGNAL : [ result ] : {'result': 'ok', 'answer': 30.0, 'value1': '20', 'value2': '10'} :: {}
0 1 h q > 1

Type in a number for value2 : 10
Type in a number for value1 : 20
SEND   : [ subtract ]

SIGNAL : [ result ] : {'result': 'ok', 'answer': 10.0, 'value1': '20', 'value2': '10'} :: {}
```