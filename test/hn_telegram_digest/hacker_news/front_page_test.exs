defmodule HnTelegramDigest.HackerNews.FrontPageTest do
  use ExUnit.Case, async: true

  import Mox

  alias HnTelegramDigest.HackerNews.FeedItem
  alias HnTelegramDigest.HackerNews.FrontPage
  alias HnTelegramDigest.HackerNewsClientMock

  setup :verify_on_exit!

  test "fetch asks the configured client for the RSS feed and parses items" do
    config = [
      client: HackerNewsClientMock,
      feed_url: "https://news.ycombinator.com/rss",
      receive_timeout: 5000
    ]

    expect(HackerNewsClientMock, :fetch_frontpage, fn opts ->
      assert "https://news.ycombinator.com/rss" = Keyword.fetch!(opts, :feed_url)
      assert 5000 = Keyword.fetch!(opts, :receive_timeout)

      {:ok, sample_rss()}
    end)

    assert {:ok,
            [
              %FeedItem{
                title: "Show HN: Tiny workflow runtime",
                url: "https://example.com/tiny-workflow-runtime"
              }
            ]} = FrontPage.fetch(config)
  end

  test "fetch returns client errors without parsing" do
    expect(HackerNewsClientMock, :fetch_frontpage, fn _opts ->
      {:error, {:unexpected_status, 503}}
    end)

    assert {:error, {:unexpected_status, 503}} =
             FrontPage.fetch(
               client: HackerNewsClientMock,
               feed_url: "https://news.ycombinator.com/rss"
             )
  end

  defp sample_rss do
    """
    <rss version="2.0">
      <channel>
        <item>
          <title>Show HN: Tiny workflow runtime</title>
          <link>https://example.com/tiny-workflow-runtime</link>
          <guid>https://news.ycombinator.com/item?id=44123457</guid>
          <comments>https://news.ycombinator.com/item?id=44123457</comments>
          <pubDate>Fri, 08 May 2026 12:30:00 +0000</pubDate>
        </item>
      </channel>
    </rss>
    """
  end
end
