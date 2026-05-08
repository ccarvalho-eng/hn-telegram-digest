defmodule HnTelegramDigest.Workflows.DeliverHnDigest.FetchHackerNewsRss do
  @moduledoc """
  Fetches Hacker News RSS items for the digest workflow.

  The action returns plain maps so downstream workflow steps can persist,
  inspect, and transform item data without depending on parser structs.
  """

  use Jido.Action,
    name: "fetch_hacker_news_rss",
    description: "Fetches Hacker News RSS feed items",
    schema: []

  alias HnTelegramDigest.HackerNews.FeedItem
  alias HnTelegramDigest.HackerNews.FrontPage

  @spec run(map(), map()) :: {:ok, %{feed_items: [FeedItem.workflow_map()]}} | {:error, term()}
  @impl Jido.Action
  def run(_params, _context) do
    with {:ok, items} <- FrontPage.fetch() do
      {:ok, %{feed_items: Enum.map(items, &FeedItem.to_workflow_map/1)}}
    end
  end
end
