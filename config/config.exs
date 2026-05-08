import Config

config :hn_telegram_digest,
  ecto_repos: [HnTelegramDigest.Repo]

config :hn_telegram_digest, :hacker_news,
  client: HnTelegramDigest.HackerNews.Client,
  feed_url: "https://news.ycombinator.com/rss",
  max_body_bytes: 1_000_000,
  receive_timeout: :timer.seconds(10)

config :squid_mesh,
  repo: HnTelegramDigest.Repo,
  execution: [
    name: Oban,
    queue: :squid_mesh,
    stale_step_timeout: :timer.minutes(5)
  ]

config :hn_telegram_digest, :telegram,
  api_base_url: "https://api.telegram.org",
  bot_token: nil,
  client: HnTelegramDigest.Telegram.Client,
  delivery_timeout_ms: :timer.minutes(5),
  update_handler: HnTelegramDigest.Telegram.CommandUpdateHandler,
  polling: [
    enabled: false,
    timeout_seconds: 30,
    limit: 100,
    allowed_updates: ["message"],
    processing_timeout_ms: :timer.minutes(5),
    error_backoff_ms: :timer.seconds(5)
  ]

import_config "#{config_env()}.exs"
