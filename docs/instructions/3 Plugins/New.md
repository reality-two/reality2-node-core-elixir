# Create a new Reality2 Builtin Plugin

__This is an advanced topic for programmers, particularly if you are familiar (or are wanting to learn) the Elixir language.__

A Reality2 built-in plugin is an umbrella App set up with a supervisor and implemented as a `GenServer`.  For example, below, we are setting up a new plugin called `ai_reality2_rustdemo`.

### Setup the Plugin

First, make sure you are in the `apps` folder.

```bash
cd apps
```

Then, use the command:

```bash
mix new ai_reality2_rustdemo --sup
```

The result should be something like below:

```bash
reality2-node-core-elixir/apps on  main [!] 
❯ mix new ai_reality2_rustdemo --sup
* creating README.md
* creating .formatter.exs
* creating .gitignore
* creating mix.exs
* creating lib
* creating lib/ai_reality2_rustdemo.ex
* creating lib/ai_reality2_rustdemo/application.ex
* creating test
* creating test/test_helper.exs
* creating test/ai_reality2_rustdemo_test.exs

Your Mix project was created successfully.
You can use "mix" to compile it, test it, and more:

    cd ai_reality2_rustdemo
    mix test

Run "mix help" for more commands.
```

### Add the Plugin into the main App

The main `mix.exs` file in the root directory needs to be tweaked as well so it knows about the new plugin; in the `project` and `releases` sections, as below.

```elixir
defmodule Reality2.Umbrella.MixProject do
    use Mix.Project

    def project do
        [
            apps_path: "apps",
            apps: [ :ai_reality2_vars, :reality2, :reality2_web, :ai_reality2_geospatial, :ai_reality2_pns, :ai_reality2_auth, :ai_reality2_backup, :ai_reality2_rustdemo], # <------------ HERE
            version: "0.1.8",
            start_permanent: Mix.env() == :prod,
            deps: deps(),
            aliases: aliases(),
            releases: releases()
        ]
    end


    def application do
        [
            extra_applications: [:logger, :runtime_tools, :os_mon, :mnesia]
        ]
    end

    # Dependencies can be Hex packages:
    #
    #   {:mydep, "~> 0.3.0"}
    #
    # Or git/path repositories:
    #
    #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
    #
    # Type "mix help deps" for more examples and options.
    #ssss
    # Dependencies listed here are available only for this project
    # and cannot be accessed from applications inside the apps/ folder.
    defp deps do
        [
        ]
    end

    # Aliases are shortcuts or tasks specific to the current project.
    # For example, to install project dependencies and perform other setup tasks, run:
    #
    #     $ mix setup
    #
    # See the documentation for `Mix` for more info on aliases.
    #
    # Aliases listed here are available only for this project
    # and cannot be accessed from applications inside the apps/ folder.
    defp aliases do
        [
            # run `mix setup` in all child apps
            setup: ["cmd mix setup"],
            # run `mix docs` in all child apps
            docs: ["cmd mix docs"],
            # run the tests in all child apps
            test: ["cmd mix test"]
        ]
    end

    defp releases do
        [
            reality2: [
                applications: [
                reality2: :permanent,
                reality2_web: :permanent,
                ai_reality2_geospatial: :permanent,
                ai_reality2_vars: :permanent,
                ai_reality2_pns: :permanent,
                ai_reality2_auth: :permanent,
                ai_reality2_backup: :permanent,
                ai_reality2_rustdemo: :permanent # <------------ HERE
                ]
            ]
        ]
    end
end
```

### Add the main App to the Plugin

In a similar way, the Plugin needs to be aware of the main Reality2 app if you are wishing to use any of the useful functions such as those in the `Reality2.Helpers` module.  In the `mix.exs` file of the Plugin, make sure the `deps` section has at least the following:

```elixir
defp deps do
    [
        {:reality2, in_umbrella: true}
    ]
end
```

You may also have other dependencies, depending on what your plugin does.

### Internal API

Generally, a Reality2 built-in Plugin creates a process for each Sentant that uses that plugin, and then receives events from the Sentant when being called from an `action`.  This is an excellent way to ensure robustness as each Sentant's plugin process is completely independent of all others, and thus if there is some problem, won't affect other Sentants.  This good OTP practice.  Sometimes, however, this is a bit overkill, and you only really need the one process for the plugin.

An example of a Reality2 plugin that uses a process for each Sentant is the `ai_reality2_vars` plugin.  An example of a Reality2 plugin that has only one process for all Sentants is the `ai_reality2_backup` plugin.

Regardless of the type of plugin, it has a consistant interface towards the rest of the Reality2 Node.  This interface is created through static functions in a file called `main.ex` located in the lib folder of the plugin.  The `main` file must be defined as a module with the name: `[your plugin name in camelcase].Main`, for example `AiReality2Backup.Main`.

The module needs to be a `GenServer`, so this line is required near the top:

```elixir
@doc false
use GenServer, restart: :transient
```

In addition to the functions normally required of a `GenServer` such as `init`, `start_link` `handle_cast` and `handle_call`, there are four functions that must be defined:

#### create

```elixir
@spec create(String.t()) ::
    {:ok}
    | {:error, :existance}
```

Is called when a Sentant is loaded.  The single parameter is the Sentant ID.  This should create any processes that might be required for the Sentant.

#### delete

```elixir
@spec delete(String.t()) ::
    {:ok}
    | {:error, :existance}
```

Is called when a Sentant is unloaded.  The single parameter is the Sentant ID.  This should remove any processes that were setup for the Sentant.

#### whereis

```elixir
@spec whereis(String.t() | pid()) ::
    pid()
    | String.t()
    | nil
```

The single parameter is the Sentant ID.  Returns a `PID` if a process that represents that Sentant exists.  This might be the individual processes created for each, or the main GenServer.  From the point of view of the calling process, it will make no difference.

The `whereis` static function is used internally, and whilst it is technically possible to send events directly to the plugin process for a specific Sentant in other code outside of this plugin, it is highly recommended not to do so.  Use instead the `sendto` function.

#### sendto
```elixir
@spec sendto(String.t(), map()) ::
    :ok
    | {:error, :command}
    | {:ok, any()}
    | {:error, :key}
```

This function is used when an action is being activated, and the parameters are being sent to the plugin.  The first parameter is the Sentant ID, and the second parameter is the Map of data that comes under the `action` with typically the following layout (though you can set it up however you wish):

```elixir
%{
    command: "the_command",
    parameters: %{
        # Whatever parameters you require.
    }
}
```

Sometimes, there may be other data at the root level of the parameters, for example the `ai_reality_backup` plugin needs a `keys` parameter that holds the encryption and decryption keys.  Essentially, whatever is included in the json object, except the key `plugin` is passed along.

Note, however, that the `keys` parameter is a special case, and is included at the root level of the Sentant definition, and then passed along as required.

So, for example, if the following actions are defined:

```json
"actions": [
    { "command": "set", "plugin": "ai.reality2.vars", "parameters": { "key": "sensor", "value": "__sensor__" } }
]
```

Then, the data that is received might be:

```elixir
%{
    command: "set",
    parameters: %{
        key: "sensor",
        value: 193
    }
}
```

Note that the map has been pre-processed before being sent so that, for example as in this case, the variable substituion for \_\_sensor\_\_ has been made.

Similarly, an action such as:

```json
{ "command": "set", "parameters": { "key": "param2", "value": { "jsonpath": "var5.key1.[].a" } } },
```

Would have had the `jsonpath` value replaced by the actual data to be stored by the time it reaches the plugin.

### application.ex

The `application.ex` file must start any processes required, particularly at least `main.ex`.  For example, the `ai_reality2_backup` file is:

```elixir
defmodule AiReality2Backup.Application do
    @moduledoc false

    use Application

    @impl true
    def start(_type, _args) do
        children = [
            %{id: AiReality2Backup.Main, start: {AiReality2Backup.Main, :start_link, [AiReality2Backup.Main]}}
        ]

        opts = [strategy: :one_for_one, name: AiReality2Backup.Supervisor]
        Supervisor.start_link(children, opts)
    end
end
```

The one for `ai_reality2_vars` is a little more complicated:

```elixir
defmodule AiReality2Vars.Application do
    @moduledoc false

    use Application

    @impl true
    def start(_type, _args) do
        children = [
            %{id: AiReality2Vars.Processes, start: {Reality2.Helpers.R2Process, :start_link, [AiReality2Vars.Processes]}},
            %{id: AiReality2Vars.Main, start: {AiReality2Vars.Main, :start_link, [AiReality2Vars.Main]}}
        ]

        opts = [strategy: :one_for_one, name: AiReality2Vars.Supervisor]
        Supervisor.start_link(children, opts)
    end
end
```

In this case, we need an additional process provided by the `Reality2.Helpers.R2Process` module that can be used to keep track of Process IDs without having to use atoms (an important consideration when using the BEAM engine).

The `main.ex` code in turn creates a new process whenever the `create` static function is called, for example:

```elixir
def create(sentant_id) do
    case whereis(sentant_id) do
        nil->
            case DynamicSupervisor.start_child(__MODULE__, AiReality2Vars.Data.child_spec({})) do
            {:ok, pid} ->
                R2Process.register(sentant_id, pid, AiReality2Vars.Processes)
                {:ok}
            error -> error
            end
        pid ->
            # Clear the data store so there is no old data that hackers might be able to access in the case this was a reused ID
            R2Process.register(sentant_id, pid, AiReality2Vars.Processes)
            GenServer.call(pid, %{command: "clear"})
            {:ok}
    end
end
```

The `whereis` static function then is able to return a Process ID like this:

```elixir
def whereis(sentant_id) do
    R2Process.whereis(sentant_id, AiReality2Vars.Processes)
end
```

For comparison, the `whereis` static function for `ai_reality2_backup` only returns itself.

```elixir
def whereis(_sentant_id) do
    self()
end
```

And the `create` function is similarly simpler (ie it doesn't have to do anything):

```elixir
def create(_sentant_id) do
    {:ok}
end
```

### A main.ex template

The bare minimum `main.ex` file could be as follows:

```elixir
defmodule AiReality2Rustdemo.Main do
    # *******************************************************************************************************************************************
    @moduledoc """
      Module for testing and experimenting with Rust NIFs in Elixir inside a Reality2 Node.

      In this instance, the main supervisor is a DynamicSupervisor, but we don't need a new process for each Sentant.

      **Author**
      - Dr. Roy C. Davies
      - [roycdavies.github.io](https://roycdavies.github.io/)
    """
    # *******************************************************************************************************************************************
    
    use GenServer, restart: :transient

    def start_link(name), do: GenServer.start_link(__MODULE__, %{}, name: name)

    def init(state) do 
        IO.puts("[ai.reality2.rustdemo] started successfully.")
        {:ok, state}
    end

    def create(_sentant_id), do: {:ok}

    def delete(_sentant_id), do: {:ok}

    def whereis(_sentant_id), do: self()
    
    def sendto(_sentant_id, command_and_parameters) do
        IO.puts("Received command: #{inspect(command_and_parameters)}")
        {:ok}
    end
end
```

  The corresponding `application.ex` is:

```elixir
defmodule AiReality2Rustdemo.Application do
    use Application

    @impl true
    def start(_type, _args) do
        children = [
            %{id: AiReality2Rustdemo.Main, start: {AiReality2Rustdemo.Main, :start_link, [AiReality2Rustdemo.Main]}}
        ]

        opts = [strategy: :one_for_one, name: AiReality2Rustdemo.Supervisor]
        Supervisor.start_link(children, opts)
    end
end
```