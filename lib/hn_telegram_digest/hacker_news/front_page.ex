defmodule HnTelegramDigest.HackerNews.FrontPage do
  @moduledoc """
  Fetches and parses the Hacker News front-page RSS feed.

  This module is the application boundary used by workflows. It composes the
  configured HTTP client with the RSS parser and returns domain structs.
  """

  alias HnTelegramDigest.HackerNews.Client
  alias HnTelegramDigest.HackerNews.FeedItem
  alias HnTelegramDigest.HackerNews.RssFeed

  @type config :: keyword()

  @doc """
  Fetches the configured Hacker News front-page feed.
  """
  @spec fetch(config()) :: {:ok, [FeedItem.t()]} | {:error, term()}
  def fetch(config \\ Application.fetch_env!(:hn_telegram_digest, :hacker_news)) do
    client = Keyword.get(config, :client, Client)

    with {:ok, xml} <- client.fetch_frontpage(config) do
      RssFeed.parse_items(xml)
    end
  end
end
