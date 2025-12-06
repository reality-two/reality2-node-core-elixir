defmodule AiReality2Transnet.MixProject do
  use Mix.Project

  def project do
    [
      app: :ai_reality2_transnet,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      name: "Plugin: ai.reality2.transnet",
      source_url: "https://github.com/roycdavies/reality2",
      homepage_url: "https://reality2.ai",
      docs: [
        main: "AiReality2Transnet",
        output: "../../docs/ai_reality2_transnet",
        format: :html,
      ]
    ]
  end

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
      {:rustler, "~> 0.34.0"}
    ]
  end
end
