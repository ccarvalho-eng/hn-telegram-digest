defmodule HnTelegramDigest.HackerNews.RssFeed do
  @moduledoc """
  Parses Hacker News RSS XML into normalized feed items.

  The parser is deliberately tolerant of individual malformed items: unusable
  entries are skipped, while malformed XML and entirely empty feeds return
  structured errors.
  """

  alias HnTelegramDigest.HackerNews.FeedItem

  @type parse_error :: :invalid_rss | :empty_hacker_news_feed

  @doc """
  Parses RSS XML and returns usable feed items in feed order.
  """
  @spec parse_items(String.t()) :: {:ok, [FeedItem.t()]} | {:error, parse_error()}
  def parse_items(xml) when is_binary(xml) do
    with {:ok, document} <- parse_document(xml),
         [_item | _items] = raw_items <- xpath(document, "/rss/channel/item"),
         [_feed_item | _feed_items] = feed_items <- normalize_items(raw_items) do
      {:ok, feed_items}
    else
      {:error, _reason} = error -> error
      [] -> {:error, :empty_hacker_news_feed}
    end
  end

  defp parse_document(xml) do
    xml
    |> :erlang.binary_to_list()
    |> scan_xml()
    |> then(fn {document, _rest} -> {:ok, document} end)
  rescue
    _exception -> {:error, :invalid_rss}
  catch
    _kind, _reason -> {:error, :invalid_rss}
  end

  defp normalize_items(raw_items) do
    raw_items
    |> Enum.map(&normalize_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_item(item) do
    with {:ok, title} <- text(item, "title"),
         {:ok, url} <- text(item, "link"),
         comments_url = optional_text(item, "comments"),
         {:ok, id} <- item_id(item, comments_url, url) do
      %FeedItem{
        id: id,
        title: title,
        url: url,
        comments_url: comments_url,
        published_at: published_at(item)
      }
    else
      {:error, _reason} -> nil
    end
  end

  defp item_id(item, comments_url, fallback_url) do
    guid = optional_text(item, "guid")

    {:ok, comments_url || guid || fallback_url}
  end

  defp published_at(item) do
    item
    |> optional_text("pubDate")
    |> parse_rfc1123_datetime()
  end

  defp parse_rfc1123_datetime(nil), do: nil

  defp parse_rfc1123_datetime(value) do
    value
    |> String.to_charlist()
    |> convert_request_date()
    |> datetime_from_request_date()
  end

  defp datetime_from_request_date({{year, month, day}, {hour, minute, second}}) do
    with {:ok, date} <- Date.new(year, month, day),
         {:ok, time} <- Time.new(hour, minute, second),
         {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
      datetime
    else
      _error -> nil
    end
  end

  defp datetime_from_request_date(_value), do: nil

  defp text(item, name) do
    case optional_text(item, name) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:error, {:missing_rss_field, name}}
    end
  end

  defp optional_text(item, name) do
    item
    |> xpath_string(name)
    |> blank_to_nil()
  end

  defp xpath(document, path) do
    apply(:xmerl_xpath, :string, [String.to_charlist(path), document])
  end

  defp xpath_string(item, name) do
    case xpath(item, "string(#{name})") do
      {:xmlObj, :string, value} -> value |> to_string() |> String.trim()
      _value -> ""
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp scan_xml(xml), do: apply(:xmerl_scan, :string, [xml, [quiet: true]])

  defp convert_request_date(value), do: apply(:httpd_util, :convert_request_date, [value])
end
