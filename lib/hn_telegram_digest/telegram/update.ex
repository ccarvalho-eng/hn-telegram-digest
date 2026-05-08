defmodule HnTelegramDigest.Telegram.Update do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:update_id, :integer, autogenerate: false}

  schema "telegram_updates" do
    field(:payload, :map)
    field(:status, :string, default: "received")
    field(:last_error, :map)
    field(:processing_token, :string)
    field(:processing_started_at, :utc_datetime_usec)
    field(:handled_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end
end
