defmodule AiReality2Rustdemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :ai_reality2_rustdemo,
      version: "0.1.8",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      name: "Plugin: ai.reality2.rustdemo",
      source_url: "https://github.com/roycdavies/reality2",
      homepage_url: "https://reality2.ai",
      docs: [
        main: "AiReality2Rustdemo",
        output: "../../docs/ai_reality2_rustdemo",
        format: :html,
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AiReality2Rustdemo.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:reality2, in_umbrella: true}
    ]
  end
end
