defmodule HnTelegramDigest.Repo do
  use Ecto.Repo,
    otp_app: :hn_telegram_digest,
    adapter: Ecto.Adapters.Postgres
end
