defmodule HnTelegramDigest.Repo.Migrations.CreateTelegramMessageDeliveries do
  use Ecto.Migration

  def change do
    create table(:telegram_message_deliveries) do
      add :idempotency_key, :string, null: false
      add :chat_id, :bigint, null: false
      add :text, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :telegram_message_id, :bigint
      add :last_error, :map
      add :processing_token, :string
      add :processing_started_at, :utc_datetime_usec
      add :sent_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:telegram_message_deliveries, [:idempotency_key])
    create index(:telegram_message_deliveries, [:chat_id])
    create index(:telegram_message_deliveries, [:status])
  end
end
