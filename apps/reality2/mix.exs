defmodule Reality2.MixProject do
  use Mix.Project

  def project do
    [
      app: :reality2,
      version: "0.1.8",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: "Reality2 Sentient Agent (Sentant) Platform",

      name: "Reality2.AI",
      source_url: "https://github.com/roycdavies/reality2/tree/main/apps/reality2",
      homepage_url: "https://reality2.ai",
      docs: [
        main: "Reality2.AI", output: "../../docs/reality2", format: :html,
        extras: ["README.md"]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Reality2.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon, :geohash, :mnesia, :crypto] #, :gun]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:dns_cluster, "~> 0.1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:yaml_elixir, "~> 2.9"},
      {:makeup_elixir, ">= 0.0.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:uuid, "~> 1.1"},
      {:toml, "~> 0.7"},
      {:finch, "~> 0.16"},
      {:validate, "~> 1.3"},
      {:geohash, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
