defmodule HnTelegramDigest.Telegram.Subscription do
  @moduledoc false

  use Ecto.Schema

  schema "telegram_subscriptions" do
    field(:chat_id, :integer)
    field(:status, :string)
    field(:subscribed_at, :utc_datetime_usec)
    field(:unsubscribed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end
end
