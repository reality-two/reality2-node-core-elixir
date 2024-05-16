# Inbuilt plugin HOWTO

For this section, you need to be an Elixir programming guru, and fully understand how to build apps in umbrella projects using mix.

If that sentence made no sense, back slowly away, and close the door again...

***

### Naming conventions

The names for plugins use the [reverse domain name](https://en.wikipedia.org/wiki/Reverse_domain_name_notation) notation to help ensure uniqueness globally.  However, within the file structure, periods are not advised, so we use underscores instead.  Therefore, when creating the App, use underscores instead of the periods, for example for an app that will be referred to as `ai.reality2.vars` in the Swarm and Sentant definition files, use the app name `ai_reality2_vars`.

Internally to Elixir, the App will then be named using camel case, ie `AiReality2Vars`.

Here is a convenient function to get the current app name in reverse domain name notation from the camel case module name (defined in the `AiReality2Vars.Main` module):

```elixir
defp app_name() do
    Atom.to_string(__MODULE__)
    |> String.replace_prefix("Elixir.", "")
    |> String.replace(~r/([A-Z])/u, ".\\1")
    |> String.downcase()
    |> String.replace_suffix(".main", "")
    |> String.trim(".")
end
```

### Setting up

A good introduction to Umbrella Projects can be found [here](https://elixirschool.com/en/lessons/advanced/umbrella_projects).

In a reality2 Node, an internal plugin corresponds to an Umbrella App with a supervision tree.  To create a new one, go into the apps folder and use mix to create an app with a supervision tree, for example.

```bash
cd apps
mix new ai_reality2_vars --sup
```

That sets up the core structure.  Now, you need to modify the mix.exs in the app folder, like this:

```elixir
defmodule AiReality2Vars.MixProject do
  use Mix.Project

  def project do
    [
      app: :ai_reality2_vars,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      name: "Plugin: ai.reality2.vars",
      description: "Reality2 Vars Plugin",
      source_url: "https://github.com/roycdavies/reality2",
      homepage_url: "https://reality2.ai",
      docs: [
        main: "AiReality2Vars",
        output: "../../docs/ai_reality2_vars",
        format: :html,
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools, :os_mon],
      mod: {AiReality2Vars.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      # {:sibling_app_in_umbrella, in_umbrella: true}
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
```

The key points to note are the additional lines in the project section (with description, name, source_url etc), and some modifications to the application and deps section, depending on what your plugin is going to require.  The ex_doc dependency is used to allow documentation to be created by mix.

### Starting the Application

In the lib folder, by default, you get an application.ex file.  We now need to add definitions for the children the supervisor will be managing.  Exactly how this may look and work is entirely dependent on what your App does.  In some cases, you might want separate proceses for each Sentant using the plugin, in other cases, you might just have a single process.

For the above example, the application.ex file looks like this:

```elixir
defmodule AiReality2Vars.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{id: AiReality2Vars.Main, start: {AiReality2Vars.Main, :start_link, [AiReality2Vars.Main]}}
    ]

    opts = [strategy: :one_for_one, name: AiReality2Vars.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Note in particular the line in the children section that references the child definition in a file with a module Main.

in this example, we are creating an in-memory data store for key/value pairs.  We want to ensure that each Sentant that needs this plugin gets its own process so that if one crashes, the others don't lose their data.  This is good Erlang / Elixir thinking.

### The Main module

The main module, usually put into a file called main.ex in the `lib/[app name]` folder, defines a dynamic supervisor, and has specific functions: `create`, `delete`, `whereis` and `sendto`, in addition to the `start_link` and `init` functions required for a DynamicSupervisor.  Below is the standard DynamicSupervisor layout.

```elixir
defmodule AiReality2Vars.Main do
  @doc false
  
  use DynamicSupervisor, restart: :transient

  @doc false
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    DynamicSupervisor.init( strategy: :one_for_one, extra_arguments: [init_arg] )
  end
  
  ### REST OF FILE ###
  
end
```

And the following fuctions are also required:

#### create

The create function is called when a Sentant uses a plugin for the first time.  It returns either `{:ok}` or `{:error, :some_error}`.

```elixir
def create(sentant_id) do
    # Do something to create the plugin entry for the given sentant.
    # Return {:ok} or {:error, :some_error}
    
    name = sentant_id <> "|" <> app_name()
    case Process.whereis(String.to_atom(name)) do
      nil->
        case DynamicSupervisor.start_child(__MODULE__, AiReality2Vars.Data.child_spec(String.to_atom(name))) do
          {:ok, _pid} ->
            {:ok}
          error -> error
        end
      pid ->
        # Clear the data store so there is no old data that hackers might be able to access in the case this was a reused ID
        GenServer.call(pid, %{command: "clear"})
        {:ok}
    end
end
```

In the above example, a child process is created for each Sentant that uses a data store which in turn stores the data in memory.

#### delete

The delete function is called when a Sentant is deleted (usually), or when a Sentant decides it no longer needs the plugin.  Again return either `{:ok}` or `{:error, :some_error}`.

```elixir
def delete(sentant_id) do
    # Do something to delete the plugin entry for the given sentant.
    # Return {:ok} or {:error, :some_error}
    
    name = sentant_id <> "|" <> app_name()
    case Process.whereis(String.to_atom(name)) do
      nil->
        # It is not an error if the child does not exist
        {:ok}
      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
end
```

In the example above, the child of the DynamicSupervisor that was created is subsequently deleted, if it existed.

#### whereis

Returns a process ID that can be used for communication with the plugin for the Sentant, or nil if there is no plugin process for that Sentant.  Depending on the plugin, this might be to one process that is storing data for all Sentants, or seperate processes, one for each Sentant.

```elixir
def whereis(sendant_id) do
    # Get the Process ID or return nil if one doesn't exist.
    sentant_id <> "|" <> app_name() |> String.to_atom() |> Process.whereis()
end
```

#### sendto

Send a command and associated parameters to the plugin for this Sentant.  Depending on the nature of the plugin, these may directly return a value (`GenServer.call`), or start a process that does something but returns no value (`GenServer.cast`).

```elixir
def sendto(sentant_id, command_and_parameters) do
    case whereis(sentant_id) do
      nil ->
        {:error, :existence}
      pid ->
        case get(command_and_parameters, :command) do
          "set" ->
            GenServer.cast(pid, command_and_parameters)
          "delete" ->
            GenServer.cast(pid, command_and_parameters)
          "get" ->
             case GenServer.call(pid, command_and_parameters) do
                nil ->
                  {:error, :key}
                result ->
                  result
             end
          "all" ->
            GenServer.call(pid, command_and_parameters)
          "clear" ->
            GenServer.cast(pid, command_and_parameters)
          _ ->
            {:error, :command}
        end
    end
end
```

The exact nature of the commands is determined by the definition of what your plugin will do, and will be used in the definition of the actions in transitions for automations.

In the example above, there are several commands to manage data on the data store, which in turn call or cast to the child of the GenServer.

A useful function to get values from a map regardless of whether the key is a string or an atom is defined below:

```elixir
def get(map, key, default \\ nil)
def get(map, key, default) when is_binary(key) do
    case Elixir.Map.get(map, key) do
      nil ->
        case Elixir.Map.get(map, String.to_atom(key)) do
          nil -> default
          value -> value
        end
      value -> value
    end
end

def get(map, key, default) when is_atom(key) do
    case Elixir.Map.get(map, key) do
      nil ->
        case Elixir.Map.get(map, Atom.to_string(key)) do
          nil -> default
          value -> value
        end
      value -> value
    end
end

def get(map, key, default), do: Elixir.Map.get(map, key, default)
```

This is used in the sendto function.

### The Data module

In the data store example, there is a file called data.ex which handles the data store for each Sentant in its own process.  This is unique to this plugin - your plugin may will likely do something completely different, but for completeness, here is that file:

```elixir
defmodule AiReality2Vars.Data do
    @doc false
    use GenServer, restart: :transient
    
    @doc false
    def start_link(_, name),                              do: GenServer.start_link(__MODULE__, %{}, name: name)
    
    @doc false
    def init(state),                                      do: {:ok, state}
    
    @doc false
    def handle_call(%{command: "get", parameters: %{key: key}}, _from, state),                        do: {:reply, {:ok, AiReality2Vars.Main.get(state, key, nil)}, state}
    def handle_call(%{command: "get", parameters: %{"key" => key}}, _from, state),                    do: {:reply, {:ok, AiReality2Vars.Main.get(state, key, nil)}, state}
    def handle_call(%{command: "all"}, _from, state),                                                 do: {:reply, {:ok, state}, state}
    def handle_call(_, _from, state),                                                                 do: {:reply, {:error, :unknown_command}, state}
    
    
    @doc false
    def handle_cast(%{command: "set", parameters: %{key: key, value: value}}, state),                 do: {:noreply, Map.put(state, key, value)}
    def handle_cast(%{command: "set", parameters: %{"key" => key, "value" => value}}, state),         do: {:noreply, Map.put(state, key, value)}
    def handle_cast(%{command: "delete", parameters: %{key: key}}, state),                            do: {:noreply, Map.delete(state, key)}
    def handle_cast(%{command: "delete", parameters: %{"key" => key}}, state),                        do: {:noreply, Map.delete(state, key)}
    def handle_cast(%{command: "clear"}, _state),                                                     do: {:noreply, %{}}
    def handle_cast(_, state),                                                                        do: {:noreply, state}
end

```

