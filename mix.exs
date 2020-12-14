defmodule BPEXE.MixProject do
  use Mix.Project

  def project do
    [
      app: :bpexe,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "BPEXE"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BPEXE.Application, []},
      env: [
        default_expression_language: BPEXE.Language.Lua,
        expression_languages: %{"lua" => BPEXE.Language.Lua},
        extra_expression_languages: %{"lua" => BPEXE.Language.Lua}
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:saxy, "~> 1.3"},
      {:ets, "~> 0.8.1"},
      {:result, "~> 1.6.0"},
      {:syn, "~> 2.1.1"},
      # for timer-based events
      {:timex, "~> 3.6.2"},
      # Lua scripting (Luerl)
      {:luerl, github: "rvirding/luerl", ref: "1b0699c"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false}
    ]
  end
end
