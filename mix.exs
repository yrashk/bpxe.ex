defmodule BPXE.MixProject do
  use Mix.Project

  def project do
    [
      app: :bpxe,
      description: "Business Process Execution Engine",
      version: "0.2.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "BPXE"
      ],
      elixirc_options: [warnings_as_errors: true],
      package: [
        licenses: ["Apache-2.0"],
        source_url: "https://github.com/bpxe/bpxe",
        links: %{"GitHub" => "https://github.com/bpxe/bpxe"},
        exclude_patterns: ~w(\.swp)
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BPXE.Application, []},
      env: [
        activation_id_generator: {XCUID, :generate, []},
        token_id_generator: {XCUID, :generate, []},
        spec_id_generator: {XCUID, :generate, []},
        default_expression_language: BPXE.Language.Lua,
        expression_languages: %{"lua" => BPXE.Language.Lua},
        extra_expression_languages: %{"lua" => BPXE.Language.Lua}
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
      {:luerl, "~> 0.4.0"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:ok, "~> 2.3.0"},
      {:map_diff, "~> 1.3.4"},
      {:exconstructor, "~> 1.1.0"},
      {:ex2ms, "~> 1.6.0"},
      {:xcuid, "~> 0.1.1"},
      {:versioce, "~> 0.2.1", only: [:dev, :test]},
      {:deep_merge, "~> 1.0.0"},
      {:jason, "~> 1.2.2"},
      {:jmes, "~> 0.4.1"}
    ]
  end
end
