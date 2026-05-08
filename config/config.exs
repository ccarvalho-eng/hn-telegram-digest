import Config

config :hn_telegram_digest,
  ecto_repos: [HnTelegramDigest.Repo]

config :squid_mesh,
  repo: HnTelegramDigest.Repo,
  execution: [
    name: Oban,
    queue: :squid_mesh,
    stale_step_timeout: :timer.minutes(5)
  ]

import_config "#{config_env()}.exs"
