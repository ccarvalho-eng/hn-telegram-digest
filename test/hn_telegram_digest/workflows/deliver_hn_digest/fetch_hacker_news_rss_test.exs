defmodule HnTelegramDigest.Workflows.DeliverHnDigest.FetchHackerNewsRssTest do
  use ExUnit.Case, async: false

  import Mox

  alias HnTelegramDigest.HackerNewsClientMock
  alias HnTelegramDigest.Workflows.DeliverHnDigest.FetchHackerNewsRss

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    hacker_news_config = Application.fetch_env!(:hn_telegram_digest, :hacker_news)

    Application.put_env(
      :hn_telegram_digest,
      :hacker_news,
      Keyword.merge(hacker_news_config, client: HackerNewsClientMock)
    )

    on_exit(fn ->
      Application.put_env(:hn_telegram_digest, :hacker_news, hacker_news_config)
    end)
  end

  test "run fetches Hacker News RSS items for workflow transport" do
    expect(HackerNewsClientMock, :fetch_frontpage, fn opts ->
      assert "https://news.ycombinator.com/rss" = Keyword.fetch!(opts, :feed_url)

      {:ok, sample_rss()}
    end)

    assert {:ok,
            %{
              feed_items: [
                %{
                  id: "https://news.ycombinator.com/item?id=44123458",
                  title: "Durable workflows with Oban",
                  url: "https://example.com/durable-workflows",
                  comments_url: "https://news.ycombinator.com/item?id=44123458",
                  published_at: "2026-05-08T13:00:00Z"
                }
              ]
            }} = FetchHackerNewsRss.run(%{}, %{run_id: "run-1"})
  end

  defp sample_rss do
    """
    <rss version="2.0">
      <channel>
        <item>
          <title>Durable workflows with Oban</title>
          <link>https://example.com/durable-workflows</link>
          <guid>https://news.ycombinator.com/item?id=44123458</guid>
          <comments>https://news.ycombinator.com/item?id=44123458</comments>
          <pubDate>Fri, 08 May 2026 13:00:00 +0000</pubDate>
        </item>
      </channel>
    </rss>
    """
  end
end
