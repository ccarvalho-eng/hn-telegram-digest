defmodule HnTelegramDigest.HackerNews.ClientTest do
  use ExUnit.Case, async: true

  alias HnTelegramDigest.HackerNews.Client

  test "fetch_frontpage returns raw XML from the canonical Hacker News RSS URL" do
    request = fn url, opts ->
      assert "https://news.ycombinator.com/rss" = url
      assert Keyword.fetch!(opts, :decode_body) == false
      assert 0 = Keyword.fetch!(opts, :max_retries)
      assert 5000 = Keyword.fetch!(opts, :receive_timeout)
      assert Keyword.fetch!(opts, :redirect) == false

      {:ok, %Req.Response{status: 200, body: "<rss></rss>"}}
    end

    assert {:ok, "<rss></rss>"} =
             Client.fetch_frontpage(
               feed_url: "https://news.ycombinator.com/rss",
               receive_timeout: 5000,
               request: request
             )
  end

  test "fetch_frontpage returns an error for non-200 responses" do
    request = fn _url, _opts ->
      {:ok, %Req.Response{status: 503, body: "unavailable"}}
    end

    assert {:error, {:unexpected_status, 503}} =
             Client.fetch_frontpage(
               feed_url: "https://news.ycombinator.com/rss",
               request: request
             )
  end

  test "fetch_frontpage rejects unexpectedly large bodies" do
    request = fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: "too large"}}
    end

    assert {:error, {:body_too_large, 9, 8}} =
             Client.fetch_frontpage(
               feed_url: "https://news.ycombinator.com/rss",
               max_body_bytes: 8,
               request: request
             )
  end

  test "fetch_frontpage returns transport errors" do
    request = fn _url, _opts -> {:error, :timeout} end

    assert {:error, :timeout} =
             Client.fetch_frontpage(
               feed_url: "https://news.ycombinator.com/rss",
               request: request
             )
  end

  test "rejects non-canonical Hacker News RSS URLs before sending a request" do
    assert_raise ArgumentError,
                 "Hacker News RSS URL must be https://news.ycombinator.com/rss",
                 fn ->
                   Client.fetch_frontpage(feed_url: "https://news.ycombinator.com/news")
                 end
  end
end
