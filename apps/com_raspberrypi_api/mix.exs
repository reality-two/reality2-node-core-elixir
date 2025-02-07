defmodule ComRaspberrypiApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :com_raspberrypi_api,
      version: "0.1.12",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      name: "Plugin: com.raspberrypi.api",
      source_url: "https://github.com/roycdavies/reality2",
      homepage_url: "https://reality2.ai",
      docs: [
        main: "ComRaspberrypiApi",
        output: "../../docs/com_raspberrypi_api",
        format: :html,
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ComRaspberrypiApi.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      # {:sibling_app_in_umbrella, in_umbrella: true}


    ]
  end
end
