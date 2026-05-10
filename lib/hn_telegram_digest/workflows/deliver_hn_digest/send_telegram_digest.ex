defmodule HnTelegramDigest.Workflows.DeliverHnDigest.SendTelegramDigest do
  @moduledoc """
  Sends a formatted Hacker News digest through Telegram.

  The action validates the formatter's workflow idempotency metadata before
  delegating durable delivery and retry behavior to the Telegram context.
  """

  use Jido.Action,
    name: "send_telegram_digest",
    description: "Sends a formatted Hacker News digest to Telegram",
    schema: [
      digest: [type: :map, required: true]
    ]

  alias HnTelegramDigest.Telegram.MessageDeliveries
  alias HnTelegramDigest.Telegram.Subscriptions

  @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
  @impl Jido.Action
  def run(%{digest: digest}, %{run_id: run_id}) when is_map(digest) and is_binary(run_id) do
    idempotency_key = "workflow/#{run_id}/send_digest"

    with :ok <- validate_digest_idempotency_key(digest, idempotency_key),
         {:ok, chat_id} <- fetch_integer(digest, :chat_id),
         {:ok, empty?} <- fetch_boolean(digest, :empty),
         {:ok, text} <- fetch_non_empty_binary(digest, :text) do
      cond do
        not Subscriptions.active?(chat_id) ->
          {:ok, inactive_subscription_result(chat_id, empty?, idempotency_key)}

        empty? ->
          {:ok, skipped_result(chat_id, idempotency_key)}

        true ->
          deliver_digest(chat_id, text, idempotency_key)
      end
    end
  end

  defp deliver_digest(chat_id, text, idempotency_key) do
    attrs = %{
      idempotency_key: idempotency_key,
      chat_id: chat_id,
      text: text
    }

    with {:ok, delivery_result} <-
           :hn_telegram_digest
           |> Application.fetch_env!(:telegram)
           |> then(&MessageDeliveries.deliver_once(attrs, &1)) do
      {:ok,
       delivery_result
       |> Map.put(:chat_id, chat_id)
       |> Map.put(:empty, false)
       |> Map.put(:idempotency_key, idempotency_key)}
    end
  end

  defp validate_digest_idempotency_key(digest, expected_key) do
    case value(digest, :idempotency_key) do
      ^expected_key -> :ok
      _key -> {:error, :digest_idempotency_key_mismatch}
    end
  end

  defp skipped_result(chat_id, idempotency_key) do
    %{
      status: "skipped",
      reason: "empty_digest",
      duplicate?: false,
      chat_id: chat_id,
      empty: true,
      idempotency_key: idempotency_key
    }
  end

  defp inactive_subscription_result(chat_id, empty?, idempotency_key) do
    %{
      status: "skipped",
      reason: "inactive_subscription",
      duplicate?: false,
      chat_id: chat_id,
      empty: empty?,
      idempotency_key: idempotency_key
    }
  end

  defp fetch_integer(map, key) do
    case value(map, key) do
      value when is_integer(value) -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp fetch_boolean(map, key) do
    case value(map, key) do
      value when is_boolean(value) -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp fetch_non_empty_binary(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp value(map, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.fetch!(map, key)
      Map.has_key?(map, string_key) -> Map.fetch!(map, string_key)
      true -> nil
    end
  end
end
