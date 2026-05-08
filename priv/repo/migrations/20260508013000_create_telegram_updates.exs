defmodule HnTelegramDigest.Repo.Migrations.CreateTelegramUpdates do
  use Ecto.Migration

  def change do
    create table(:telegram_updates, primary_key: false) do
      add :update_id, :bigint, primary_key: true
      add :payload, :map, null: false
      add :status, :string, null: false, default: "received"
      add :last_error, :map
      add :processing_token, :string
      add :processing_started_at, :utc_datetime_usec
      add :handled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:telegram_updates, [:status])
    create index(:telegram_updates, [:inserted_at])
  end
end
