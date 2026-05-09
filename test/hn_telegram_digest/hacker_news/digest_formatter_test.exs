defmodule HnTelegramDigest.HackerNews.DigestFormatterTest do
  use ExUnit.Case, async: true

  alias HnTelegramDigest.HackerNews.DigestFormatter

  test "formats multiple items in rank order" do
    first = feed_item("44123461", "First ranked story", "https://example.com/first")
    second = feed_item("44123462", "Second ranked story", "https://example.com/second")

    assert {:ok,
            %{
              chat_id: 12_345,
              item_count: 2,
              included_item_count: 2,
              omitted_item_count: 0,
              item_ids: [
                "https://news.ycombinator.com/item?id=44123461",
                "https://news.ycombinator.com/item?id=44123462"
              ],
              included_item_ids: [
                "https://news.ycombinator.com/item?id=44123461",
                "https://news.ycombinator.com/item?id=44123462"
              ],
              empty: false,
              text: text
            }} = DigestFormatter.format(%{chat_id: 12_345, new_items: [first, second]})

    assert text == """
           Hacker News digest

           1. First ranked story
           https://example.com/first
           Comments: https://news.ycombinator.com/item?id=44123461

           2. Second ranked story
           https://example.com/second
           Comments: https://news.ycombinator.com/item?id=44123462\
           """
  end

  test "formats an explicit empty digest" do
    assert {:ok,
            %{
              chat_id: 12_345,
              empty: true,
              item_count: 0,
              included_item_count: 0,
              omitted_item_count: 0,
              item_ids: [],
              included_item_ids: [],
              text: "Hacker News digest\n\nNo new stories since your last digest."
            }} = DigestFormatter.format(%{chat_id: 12_345, new_items: []})
  end

  test "keeps long plain-text digests within Telegram message limits" do
    long_title = String.duplicate("A very long title ", 80)
    long_url = "https://example.com/" <> String.duplicate("long-path/", 120)

    items =
      Enum.map(1..30, fn index ->
        feed_item("44123#{index}", "#{long_title}#{index}", "#{long_url}#{index}")
      end)

    assert {:ok,
            %{
              empty: false,
              item_count: 30,
              included_item_count: included_item_count,
              omitted_item_count: omitted_item_count,
              text: text
            }} = DigestFormatter.format(%{chat_id: 12_345, new_items: items})

    assert included_item_count > 0
    assert omitted_item_count == 30 - included_item_count
    assert String.length(text) <= DigestFormatter.telegram_text_limit()
    assert text =~ "URL omitted because it is too long for a Telegram digest."
    assert text =~ "more stories omitted to fit Telegram's message limit."
  end

  defp feed_item(item_id, title, url) do
    %{
      id: "https://news.ycombinator.com/item?id=#{item_id}",
      title: title,
      url: url,
      comments_url: "https://news.ycombinator.com/item?id=#{item_id}",
      published_at: "2026-05-08T12:00:00Z"
    }
  end
end
