import Config

pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")
test_partition = System.get_env("MIX_TEST_PARTITION")

config :hn_telegram_digest, HnTelegramDigest.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "hn_telegram_digest_test#{test_partition}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: pool_size

config :hn_telegram_digest, Oban,
  repo: HnTelegramDigest.Repo,
  testing: :manual,
  plugins: [],
  queues: [default: 10, squid_mesh: 5]

config :logger, level: :warning
