defmodule HnTelegramDigest.Workflows.DeliverHnDigest.FormatTelegramDigest do
  @moduledoc """
  Formats deduplicated Hacker News items into Telegram transport data.

  The action delegates message construction to `HnTelegramDigest.HackerNews.DigestFormatter`
  and only adds workflow-specific idempotency metadata for the later send step.
  """

  use Jido.Action,
    name: "format_telegram_digest",
    description: "Formats deduplicated Hacker News items for Telegram delivery",
    schema: [
      chat_id: [type: :integer, required: true],
      new_items: [type: {:list, :map}, required: true]
    ]

  alias HnTelegramDigest.HackerNews.DigestFormatter

  @type result :: %{
          required(:chat_id) => integer(),
          required(:text) => String.t(),
          required(:item_count) => non_neg_integer(),
          required(:included_item_count) => non_neg_integer(),
          required(:omitted_item_count) => non_neg_integer(),
          required(:item_ids) => [String.t()],
          required(:included_item_ids) => [String.t()],
          required(:empty) => boolean(),
          required(:idempotency_key) => String.t()
        }

  @spec run(map(), map()) :: {:ok, result()} | {:error, term()}
  @impl Jido.Action
  def run(params, %{run_id: run_id}) when is_binary(run_id) do
    with {:ok, digest} <- DigestFormatter.format(params) do
      {:ok, Map.put(digest, :idempotency_key, "workflow/#{run_id}/send_digest")}
    end
  end
end
