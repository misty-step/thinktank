defmodule Thinktank.MixProject do
  use Mix.Project

  @version "5.0.0-dev"

  def project do
    [
      app: :thinktank,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Thinktank.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:muontrap, "~> 1.6"},
      {:plug, "~> 1.16", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp escript do
    [main_module: Thinktank.CLI]
  end
end
