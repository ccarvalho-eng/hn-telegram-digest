defmodule HnTelegramDigest.HackerNews.Client do
  @moduledoc """
  HTTP boundary for the Hacker News RSS feed.

  The client is intentionally narrow: it only fetches the canonical front-page
  RSS URL and returns the raw XML body. Parsing belongs to `RssFeed`.
  """

  @doc """
  Fetches the configured Hacker News front-page RSS feed as raw XML.
  """
  @callback fetch_frontpage(keyword()) :: {:ok, String.t()} | {:error, term()}

  @behaviour __MODULE__

  @canonical_feed_url "https://news.ycombinator.com/rss"
  @default_receive_timeout :timer.seconds(10)
  @default_max_body_bytes 1_000_000

  @impl __MODULE__
  def fetch_frontpage(opts) when is_list(opts) do
    feed_url = Keyword.get(opts, :feed_url, @canonical_feed_url)
    request = Keyword.get(opts, :request, &Req.get/2)
    :ok = validate_feed_url(feed_url)

    request.(feed_url, request_options(opts))
    |> parse_response(opts)
  end

  defp validate_feed_url(feed_url) do
    uri = URI.parse(feed_url)

    if uri.scheme == "https" and uri.host == "news.ycombinator.com" and uri.port in [nil, 443] and
         uri.path == "/rss" and is_nil(uri.query) and is_nil(uri.fragment) and
         is_nil(uri.userinfo) do
      :ok
    else
      raise ArgumentError, "Hacker News RSS URL must be #{@canonical_feed_url}"
    end
  end

  defp request_options(opts) do
    [
      decode_body: false,
      max_retries: 0,
      receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
      redirect: false
    ]
  end

  defp parse_response({:ok, %Req.Response{status: 200, body: body}}, opts) when is_binary(body) do
    max_body_bytes = Keyword.get(opts, :max_body_bytes, @default_max_body_bytes)

    if byte_size(body) <= max_body_bytes do
      {:ok, body}
    else
      {:error, {:body_too_large, byte_size(body), max_body_bytes}}
    end
  end

  defp parse_response({:ok, %Req.Response{status: 200, body: body}}, _opts) do
    {:error, {:unexpected_body, body}}
  end

  defp parse_response({:ok, %Req.Response{status: status}}, _opts) do
    {:error, {:unexpected_status, status}}
  end

  defp parse_response({:error, reason}, _opts), do: {:error, reason}
end
