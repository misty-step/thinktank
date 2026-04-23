defmodule Thinktank.MixProject do
  use Mix.Project

  @version "6.4.0"

  def project do
    [
      app: :thinktank,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      escript: escript(),
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [tool: ExCoveralls, summary: [threshold: 87]]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Thinktank.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.11"},
      {:muontrap, "~> 1.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp escript do
    [main_module: Thinktank.CLI]
  end
end
