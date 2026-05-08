defmodule HnTelegramDigest.Repo.Migrations.CreateHackerNewsSeenItems do
  use Ecto.Migration

  def change do
    create table(:hacker_news_seen_items) do
      add :chat_id, references(:telegram_chats, column: :chat_id, type: :bigint), null: false
      add :item_id, :text, null: false
      add :first_seen_run_id, :string, null: false
      add :title, :text, null: false
      add :url, :text, null: false
      add :comments_url, :text
      add :published_at, :utc_datetime_usec
      add :first_seen_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hacker_news_seen_items, [:chat_id, :item_id])
    create index(:hacker_news_seen_items, [:chat_id])
    create index(:hacker_news_seen_items, [:first_seen_run_id])
  end
end
