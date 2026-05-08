defmodule HnTelegramDigest.Workflows.HandleSubscriptionCommand.Steps.ConfirmChange do
  @moduledoc """
  Sends the Telegram confirmation produced by the subscription command workflow.

  The step derives its idempotency key from the Squid Mesh run id so a retry of
  this step does not send the same confirmation twice after a successful send is
  recorded.
  """

  use Jido.Action,
    name: "confirm_subscription_change",
    description: "Sends Telegram confirmation for subscription preference changes",
    schema: [
      subscription_change: [type: :map, required: true]
    ]

  alias HnTelegramDigest.Telegram.MessageDeliveries

  @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
  @impl Jido.Action
  def run(%{subscription_change: subscription_change}, %{run_id: run_id})
      when is_binary(run_id) do
    with {:ok, chat_id} <- fetch_integer(subscription_change, :chat_id),
         {:ok, text} <- fetch_non_empty_binary(subscription_change, :confirmation_text) do
      attrs = %{
        idempotency_key: "workflow/#{run_id}/confirm_change",
        chat_id: chat_id,
        text: text
      }

      :hn_telegram_digest
      |> Application.fetch_env!(:telegram)
      |> then(&MessageDeliveries.deliver_once(attrs, &1))
    end
  end

  defp fetch_integer(map, key) do
    case value(map, key) do
      value when is_integer(value) -> {:ok, value}
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
