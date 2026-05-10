import Config

pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

config :hn_telegram_digest, HnTelegramDigest.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "hn_telegram_digest_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: pool_size

config :hn_telegram_digest, Oban,
  repo: HnTelegramDigest.Repo,
  plugins: [
    {SquidMesh.Plugins.Cron, workflows: [HnTelegramDigest.Workflows.ScheduleHnDigests]}
  ],
  queues: [default: 10, squid_mesh: 5]
