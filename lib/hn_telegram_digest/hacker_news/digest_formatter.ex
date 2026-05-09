defmodule HnTelegramDigest.HackerNews.DigestFormatter do
  @moduledoc """
  Formats deduplicated Hacker News feed items for Telegram delivery.

  The formatter emits plain text without a Telegram parse mode. That keeps the
  message deterministic and avoids markup escaping rules in the workflow layer.
  """

  alias HnTelegramDigest.HackerNews.FeedItem

  @telegram_text_limit 4096
  @title_limit 180
  @url_text_limit 600
  @header "Hacker News digest"
  @empty_text "#{@header}\n\nNo new stories since your last digest."

  @type format_attrs :: %{
          required(:chat_id) => integer(),
          required(:new_items) => [FeedItem.workflow_map() | map()]
        }

  @type digest :: %{
          required(:chat_id) => integer(),
          required(:text) => String.t(),
          required(:item_count) => non_neg_integer(),
          required(:included_item_count) => non_neg_integer(),
          required(:omitted_item_count) => non_neg_integer(),
          required(:item_ids) => [String.t()],
          required(:included_item_ids) => [String.t()],
          required(:empty) => boolean()
        }

  @doc """
  Returns Telegram-ready digest text and workflow-safe metadata.
  """
  @spec format(format_attrs() | map()) :: {:ok, digest()} | {:error, term()}
  def format(attrs) when is_map(attrs) do
    with {:ok, chat_id} <- fetch_integer(attrs, :chat_id),
         {:ok, new_items} <- fetch_items(attrs, :new_items) do
      {:ok, build_digest(chat_id, new_items)}
    end
  end

  @doc """
  Returns the Telegram Bot API text limit used by the formatter.
  """
  @spec telegram_text_limit() :: pos_integer()
  def telegram_text_limit, do: @telegram_text_limit

  defp build_digest(chat_id, []) do
    %{
      chat_id: chat_id,
      text: @empty_text,
      item_count: 0,
      included_item_count: 0,
      omitted_item_count: 0,
      item_ids: [],
      included_item_ids: [],
      empty: true
    }
  end

  defp build_digest(chat_id, items) do
    {included_items, text} = format_non_empty_items(items)

    %{
      chat_id: chat_id,
      text: text,
      item_count: length(items),
      included_item_count: length(included_items),
      omitted_item_count: length(items) - length(included_items),
      item_ids: Enum.map(items, &Map.fetch!(&1, :id)),
      included_item_ids: Enum.map(included_items, &Map.fetch!(&1, :id)),
      empty: false
    }
  end

  defp format_non_empty_items(items) do
    entries =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, rank} -> {item, entry_text(item, rank)} end)

    {included_entries, _count} =
      Enum.reduce_while(entries, {[], 0}, fn {item, entry_text}, {included, included_count} ->
        candidate = included ++ [{item, entry_text}]
        omitted_count = length(items) - (included_count + 1)
        candidate_text = render_text(candidate, omitted_count)

        if String.length(candidate_text) <= @telegram_text_limit do
          {:cont, {candidate, included_count + 1}}
        else
          {:halt, {included, included_count}}
        end
      end)

    omitted_count = length(items) - length(included_entries)
    included_items = Enum.map(included_entries, fn {item, _entry_text} -> item end)

    {included_items, render_text(included_entries, omitted_count)}
  end

  defp render_text(entries, omitted_count) do
    body =
      entries
      |> Enum.map(fn {_item, entry_text} -> entry_text end)
      |> Enum.join("\n\n")

    [@header, body, omitted_footer(omitted_count)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp omitted_footer(0), do: ""

  defp omitted_footer(1), do: "1 more story omitted to fit Telegram's message limit."

  defp omitted_footer(count), do: "#{count} more stories omitted to fit Telegram's message limit."

  defp entry_text(item, rank) do
    comments_url = optional_text(Map.get(item, :comments_url))

    [
      "#{rank}. #{item |> Map.fetch!(:title) |> one_line() |> truncate(@title_limit)}",
      url_line(Map.fetch!(item, :url)),
      comments_line(comments_url)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp comments_line(nil), do: nil

  defp comments_line(comments_url) do
    comments_url = one_line(comments_url)

    if String.length(comments_url) <= @url_text_limit do
      "Comments: #{comments_url}"
    else
      nil
    end
  end

  defp url_line(url) do
    url = one_line(url)

    if String.length(url) <= @url_text_limit do
      url
    else
      "URL omitted because it is too long for a Telegram digest."
    end
  end

  defp fetch_items(attrs, key) do
    case value(attrs, key) do
      items when is_list(items) -> normalize_items(items)
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp normalize_items(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case normalize_item(item) do
        {:ok, normalized_item} -> {:cont, {:ok, [normalized_item | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_digest_item, reason}}}
      end
    end)
    |> case do
      {:ok, normalized_items} -> {:ok, Enum.reverse(normalized_items)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_item(item) when is_map(item) do
    with {:ok, id} <- fetch_non_empty_binary(item, :id),
         {:ok, title} <- fetch_non_empty_binary(item, :title),
         {:ok, url} <- fetch_non_empty_binary(item, :url) do
      {:ok,
       %{
         id: id,
         title: title,
         url: url,
         comments_url: optional_text(value(item, :comments_url)),
         published_at: optional_text(value(item, :published_at))
       }}
    end
  end

  defp normalize_item(_item), do: {:error, :invalid_item}

  defp fetch_integer(map, key) do
    case value(map, key) do
      value when is_integer(value) -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp fetch_non_empty_binary(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp optional_text(value) when is_binary(value) and value != "", do: value
  defp optional_text(_value), do: nil

  defp value(map, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.fetch!(map, key)
      Map.has_key?(map, string_key) -> Map.fetch!(map, string_key)
      true -> nil
    end
  end

  defp one_line(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp truncate(value, limit) do
    if String.length(value) <= limit do
      value
    else
      value
      |> String.slice(0, limit - 3)
      |> Kernel.<>("...")
    end
  end
end
