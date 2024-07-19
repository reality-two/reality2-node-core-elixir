defmodule AiReality2Geospatial.MixProject do
  use Mix.Project

  def project do
    [
      app: :ai_reality2_geospatial,
      version: "0.1.8",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Reality2 Geospatial Plugin",

      name: "Plugin: ai.reality2.geospatial",
      source_url: "https://github.com/roycdavies/reality2",
      homepage_url: "https://reality2.ai",
      docs: [
        main: "AiReality2Geospatial",
        output: "../../docs/ai_reality2_geospatial",
        format: :html,
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :geohash],
      mod: {AiReality2Geospatial.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:geohash, "~> 1.0"},
      {:reality2, in_umbrella: true}
    ]
  end
end
