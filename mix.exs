defmodule Chatto.MixProject do
  use Mix.Project

  def project do
    [
      aliases: aliases(),
      app: :chatto,
      deps: deps(),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
        plt_add_apps: [:ex_unit, :mix]
      ],
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Mix 1.20 dep compiles ignore their own --no-code-path-pruning flag, so dialyxir's PLT
      # check recompiling stale deps strips :dialyzer from the code path
      prune_code_paths: Mix.env() != :test,
      start_permanent: false,
      test_coverage: [tool: ExCoveralls],
      version: "0.1.0"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: ["coveralls.html": :test, ci: :test, coveralls: :test]]
  end

  # mix chatto.generate stays out of consumers' builds
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # Generated code only loads on the protox minor it was generated with. Stay on 2.0 until
      # Electric's pg_query_ex (pinned by acp-web) supports 2.1.
      {:protox, "~> 2.0.10"},
      {:req, "~> 0.7"},

      #
      # Development tools
      #

      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:jump_credo_checks, "~> 0.4", only: [:dev, :test], runtime: false},
      {:llamex, github: "dmitriid/llamex", only: [:dev, :test], depth: 1, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:oeditus_credo, "~> 0.11", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.0", only: :test}
    ]
  end

  defp aliases do
    [
      ci: [
        "hex.audit",
        "deps.audit",
        "format --check-formatted",
        "compile --all-warnings --warnings-as-errors",
        "credo",
        "dialyzer",
        "ex_dna --min-mass 40 --normalize-pipes",
        "test"
      ]
    ]
  end
end
