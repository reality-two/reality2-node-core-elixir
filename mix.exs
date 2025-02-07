defmodule Reality2.Umbrella.MixProject do
  use Mix.Project

  def project do

    env_plugins = case System.get_env("PLUGINS") do
      nil -> []
      value ->
        String.split(value, ",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.replace(&1, ".", "_"))
        |> Enum.map(&String.to_atom/1)
    end

    plugins = [:reality2, :reality2_web] ++ env_plugins

    [
      apps_path: "apps",
      apps: plugins,
      version: "0.1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases(plugins)
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

  defp releases(plugins) do
    [
      reality2: [
        applications: Enum.map(plugins, fn app -> {app, :permanent} end)
      ]
    ]
  end
end
