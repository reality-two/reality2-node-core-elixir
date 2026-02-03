defmodule Reality2Wfs.MixProject do
  use Mix.Project

  def project do
    [
      app: :reality2_wfs,
      version: "0.1.14",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Reality2 Waggle Finding Service (WFS) Plugin"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Reality2Wfs.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:reality2, in_umbrella: true},
      {:reality2_transnet, in_umbrella: true},
      {:phoenix_pubsub, "~> 2.0"},
      {:uuid, "~> 1.1"}
    ]
  end
end
