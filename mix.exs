defmodule BotArmyGraphifyCache.MixProject do
  use Mix.Project

  def project do
    [
      app: :bot_army_graphify_cache,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        graphify_cache_bot: [
          applications: [bot_army_graphify_cache: :permanent]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BotArmyGraphifyCache.Application, []}
    ]
  end

  defp deps do
    [
      {:bot_army_core, path: "../bot_army_core"},
      {:bot_army_runtime, path: "../bot_army_runtime", override: true},
      {:jason, "~> 1.4"}
    ]
  end
end
