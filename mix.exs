defmodule MikaCredoRules.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/MikaAK/mika_credo_rules"

  def project do
    [
      app: :mika_credo_rules,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() === :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix, :credo],
        list_unused_filters: true,
        flags: [:unmatched_returns]
      ],
      preferred_cli_env: [
        credo: :test,
        dialyzer: :test,
        coveralls: :test,
        "coveralls.json": :test,
        "coveralls.html": :test
      ],
      description: "Custom Credo checks used across Mika's Elixir projects",
      package: package(),
      name: "MikaCredoRules",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: ["Mika Kalathil"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ["lib/", "mix.exs", "README.md", "CHANGELOG.md"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      canonical: "http://hexdocs.pm/mika_credo_rules",
      filter_prefix: "MikaCredoRules",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", runtime: false},
      {:dialyxir, "~> 1.4", only: :test, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
    ]
  end
end
