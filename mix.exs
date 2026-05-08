defmodule HnTelegramDigest.MixProject do
  use Mix.Project

  def project do
    [
      app: :hn_telegram_digest,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:inets, :logger, :xmerl],
      mod: {HnTelegramDigest.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:mox, "~> 1.2", only: :test},
      {:oban, "~> 2.21"},
      {:postgrex, "~> 0.20"},
      {:req, "~> 0.5"},
      {:squid_mesh, "~> 0.1.0-alpha.3"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
