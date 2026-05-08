defmodule HnTelegramDigest.Telegram.Chat do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:chat_id, :integer, autogenerate: false}

  schema "telegram_chats" do
    field(:type, :string)
    field(:username, :string)
    field(:first_name, :string)
    field(:last_name, :string)
    field(:title, :string)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end
end
