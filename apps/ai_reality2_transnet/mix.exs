defmodule AiReality2Transnet.MixProject do
  use Mix.Project

  def project do
    [
      app: :ai_reality2_transnet,
      version: "0.1.13",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Reality2 Transient Networks Plugin",
      name: "Plugin: ai.reality2.transnet",
      source_url: "https://github.com/roycdavies/reality2",
      homepage_url: "https://reality2.ai",
      docs: [
        main: "AiReality2Transnet",
        output: "../../docs/ai_reality2_transnet",
        format: :html
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AiReality2Transnet.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:reality2, in_umbrella: true},
      # Note: ai_reality2_wfs is NOT a compile-time dependency
      # WFS integration uses runtime checks (Code.ensure_loaded?)
      # This prevents circular dependency (WFS depends on transnet)
      {:rustler, "~> 0.34.0"},
      {:plug_cowboy, "~> 2.0"},
      {:httpoison, "~> 2.0"},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
