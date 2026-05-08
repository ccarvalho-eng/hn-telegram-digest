defmodule HnTelegramDigest.Repo.Migrations.CreateTelegramChatsAndSubscriptions do
  use Ecto.Migration

  def change do
    create table(:telegram_chats, primary_key: false) do
      add :chat_id, :bigint, primary_key: true
      add :type, :string, null: false
      add :username, :string
      add :first_name, :string
      add :last_name, :string
      add :title, :string
      add :payload, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:telegram_subscriptions) do
      add :chat_id, references(:telegram_chats, column: :chat_id, type: :bigint), null: false
      add :status, :string, null: false
      add :subscribed_at, :utc_datetime_usec
      add :unsubscribed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:telegram_subscriptions, [:chat_id])
    create index(:telegram_subscriptions, [:status])
  end
end
