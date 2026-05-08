defmodule HnTelegramDigest.HackerNews.RssFeedTest do
  use ExUnit.Case, async: true

  alias HnTelegramDigest.HackerNews.FeedItem
  alias HnTelegramDigest.HackerNews.RssFeed

  test "parse_items returns normalized Hacker News feed items" do
    assert {:ok,
            [
              %FeedItem{
                id: "https://news.ycombinator.com/item?id=44123456",
                title: "SQLite on the server",
                url: "https://example.com/sqlite-on-the-server",
                comments_url: "https://news.ycombinator.com/item?id=44123456",
                published_at: ~U[2026-05-08 12:00:00Z]
              }
            ]} = RssFeed.parse_items(sample_rss())
  end

  test "parse_items prefers Hacker News comments URLs as stable item ids" do
    assert {:ok,
            [
              %FeedItem{
                id: "https://news.ycombinator.com/item?id=44123460",
                url: "https://example.com/external-story"
              }
            ]} =
             RssFeed.parse_items("""
             <rss version="2.0">
               <channel>
                 <item>
                   <title>External story</title>
                   <link>https://example.com/external-story</link>
                   <guid>https://example.com/external-story</guid>
                   <comments>https://news.ycombinator.com/item?id=44123460</comments>
                 </item>
               </channel>
             </rss>
             """)
  end

  test "parse_items returns an error for malformed XML" do
    assert {:error, :invalid_rss} = RssFeed.parse_items("<rss><channel>")
  end

  test "parse_items accepts UTF-8 characters from the real feed" do
    assert {:ok,
            [
              %FeedItem{
                id: "https://news.ycombinator.com/item?id=44123459",
                title: "Maybe you shouldn’t install new software"
              }
            ]} =
             RssFeed.parse_items("""
             <rss version="2.0">
               <channel>
                 <item>
                   <title>Maybe you shouldn’t install new software</title>
                   <link>https://example.com/software</link>
                   <comments>https://news.ycombinator.com/item?id=44123459</comments>
                 </item>
               </channel>
             </rss>
             """)
  end

  test "parse_items returns an error when no usable items are present" do
    assert {:error, :empty_hacker_news_feed} =
             RssFeed.parse_items("""
             <rss>
               <channel>
                 <item>
                   <title></title>
                 </item>
               </channel>
             </rss>
             """)
  end

  defp sample_rss do
    """
    <rss version="2.0">
      <channel>
        <title>Hacker News</title>
        <item>
          <title>SQLite on the server</title>
          <link>https://example.com/sqlite-on-the-server</link>
          <guid isPermaLink="false">https://news.ycombinator.com/item?id=44123456</guid>
          <comments>https://news.ycombinator.com/item?id=44123456</comments>
          <pubDate>Fri, 08 May 2026 12:00:00 +0000</pubDate>
        </item>
      </channel>
    </rss>
    """
  end
end
