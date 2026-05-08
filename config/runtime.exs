import Config

if config_env() == :prod do
  database_url = System.fetch_env!("DATABASE_URL")
  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :hn_telegram_digest, HnTelegramDigest.Repo,
    url: database_url,
    pool_size: pool_size,
    ssl: System.get_env("ECTO_SSL", "true") != "false"

  config :hn_telegram_digest, Oban,
    repo: HnTelegramDigest.Repo,
    plugins: [],
    queues: [default: 10, squid_mesh: 5]
end
