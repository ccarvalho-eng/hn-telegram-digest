defmodule HnTelegramDigest.Workflows.DeliverHnDigest.DedupeItems do
  @moduledoc """
  Reserves unseen Hacker News feed items for a subscribed Telegram chat.

  The action delegates all persistence and replay behavior to the Hacker News
  deduplication context and keeps workflow transport as plain maps.
  """

  use Jido.Action,
    name: "dedupe_hacker_news_items",
    description: "Deduplicates Hacker News feed items for a Telegram chat",
    schema: [
      chat_id: [type: :integer, required: true],
      feed_items: [type: {:list, :map}, required: true]
    ]

  alias HnTelegramDigest.HackerNews.Deduplication
  alias HnTelegramDigest.HackerNews.FeedItem

  @type result :: %{
          required(:new_items) => [FeedItem.workflow_map()],
          required(:duplicate_items) => [FeedItem.workflow_map()]
        }

  @spec run(map(), map()) :: {:ok, result()} | {:error, term()}
  @impl Jido.Action
  def run(params, %{run_id: run_id}) when is_binary(run_id) do
    params
    |> Map.put(:run_id, run_id)
    |> Deduplication.reserve_new_items()
  end
end
