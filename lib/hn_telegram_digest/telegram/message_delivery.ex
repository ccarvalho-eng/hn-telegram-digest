defmodule HnTelegramDigest.Telegram.MessageDelivery do
  @moduledoc """
  Persisted record for outbound Telegram message delivery.

  Delivery rows are keyed by an idempotency key chosen by the caller. The
  `status`, `processing_token`, and `processing_started_at` fields form a small
  claim protocol so retrying a workflow step can resume or skip delivery without
  sending duplicate Telegram messages after a successful send has been recorded.
  Stale in-flight sends move to `unknown` rather than retrying automatically,
  because Telegram may already have accepted the message.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          idempotency_key: String.t() | nil,
          chat_id: integer() | nil,
          text: String.t() | nil,
          status: String.t() | nil,
          telegram_message_id: integer() | nil,
          last_error: map() | nil,
          processing_token: String.t() | nil,
          processing_started_at: DateTime.t() | nil,
          sent_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "telegram_message_deliveries" do
    field(:idempotency_key, :string)
    field(:chat_id, :integer)
    field(:text, :string)
    field(:status, :string)
    field(:telegram_message_id, :integer)
    field(:last_error, :map)
    field(:processing_token, :string)
    field(:processing_started_at, :utc_datetime_usec)
    field(:sent_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end
end
