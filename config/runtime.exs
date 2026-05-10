import Config

telegram_polling_enabled? =
  System.get_env("TELEGRAM_POLLING_ENABLED", "false") in ["1", "true", "TRUE"]

config :hn_telegram_digest, :telegram,
  bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
  polling: [
    enabled: telegram_polling_enabled?
  ]

if config_env() == :prod do
  database_url = System.fetch_env!("DATABASE_URL")
  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :hn_telegram_digest, HnTelegramDigest.Repo,
    url: database_url,
    pool_size: pool_size,
    ssl: System.get_env("ECTO_SSL", "true") != "false"

  config :hn_telegram_digest, Oban,
    repo: HnTelegramDigest.Repo,
    plugins: [
      {SquidMesh.Plugins.Cron, workflows: [HnTelegramDigest.Workflows.ScheduleHnDigests]}
    ],
    queues: [default: 10, squid_mesh: 5]
end
