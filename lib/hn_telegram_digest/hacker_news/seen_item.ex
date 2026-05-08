defmodule HnTelegramDigest.HackerNews.SeenItem do
  @moduledoc """
  A Hacker News item reserved for a Telegram chat digest.

  `first_seen_run_id` records the workflow run that first claimed the item. That
  lets the same run replay after a crash without losing its selected items,
  while later runs still treat the item as a duplicate for that chat.
  """

  use Ecto.Schema

  schema "hacker_news_seen_items" do
    field(:chat_id, :integer)
    field(:item_id, :string)
    field(:first_seen_run_id, :string)
    field(:title, :string)
    field(:url, :string)
    field(:comments_url, :string)
    field(:published_at, :utc_datetime_usec)
    field(:first_seen_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          chat_id: integer(),
          item_id: String.t(),
          first_seen_run_id: String.t(),
          title: String.t(),
          url: String.t(),
          comments_url: String.t() | nil,
          published_at: DateTime.t() | nil,
          first_seen_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
