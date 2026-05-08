defmodule HnTelegramDigest.HackerNews.Deduplication do
  @moduledoc """
  Reserves Hacker News feed items per Telegram chat.

  Deduplication is chat-scoped and replay-safe for a workflow run. The first run
  that reserves a chat/item pair owns that item; later runs receive it as a
  duplicate. Repeating the same run returns the same new items, which protects
  retries that happen before Squid Mesh persists the step output.
  """

  import Ecto.Query

  alias HnTelegramDigest.HackerNews.FeedItem
  alias HnTelegramDigest.HackerNews.SeenItem
  alias HnTelegramDigest.Repo
  alias HnTelegramDigest.Telegram.Chat

  @type reserve_attrs :: %{
          required(:chat_id) => integer(),
          required(:run_id) => String.t(),
          required(:feed_items) => [FeedItem.workflow_map() | map()]
        }

  @type reserve_result :: %{
          required(:new_items) => [FeedItem.workflow_map()],
          required(:duplicate_items) => [FeedItem.workflow_map()]
        }

  @doc """
  Reserves unseen feed items for a chat and classifies duplicates.
  """
  @spec reserve_new_items(reserve_attrs() | map(), module()) ::
          {:ok, reserve_result()} | {:error, term()}
  def reserve_new_items(attrs, repo \\ Repo) when is_map(attrs) do
    with {:ok, chat_id} <- fetch_integer(attrs, :chat_id),
         {:ok, run_id} <- fetch_non_empty_binary(attrs, :run_id),
         {:ok, feed_items} <- fetch_feed_items(attrs) do
      repo.transaction(fn ->
        with :ok <- ensure_chat_exists(repo, chat_id),
             unique_items = unique_feed_items(feed_items),
             :ok <- insert_seen_items(repo, chat_id, run_id, unique_items),
             {:ok, seen_items} <- seen_items_by_id(repo, chat_id, unique_items),
             {:ok, result} <- classify_items(unique_items, seen_items, run_id) do
          result
        else
          {:error, reason} -> repo.rollback(reason)
        end
      end)
    end
  end

  defp ensure_chat_exists(repo, chat_id) do
    Chat
    |> where([chat], chat.chat_id == ^chat_id)
    |> lock("FOR SHARE")
    |> select([chat], chat.chat_id)
    |> repo.one()
    |> case do
      ^chat_id -> :ok
      nil -> {:error, :telegram_chat_not_found}
    end
  end

  defp insert_seen_items(_repo, _chat_id, _run_id, []), do: :ok

  defp insert_seen_items(repo, chat_id, run_id, feed_items) do
    now = DateTime.utc_now(:microsecond)
    rows = Enum.map(feed_items, &seen_item_row(chat_id, run_id, &1, now))

    {_count, _rows} =
      repo.insert_all(SeenItem, rows,
        on_conflict: :nothing,
        conflict_target: [:chat_id, :item_id],
        returning: false
      )

    :ok
  end

  defp seen_item_row(chat_id, run_id, feed_item, now) do
    %{
      chat_id: chat_id,
      item_id: item_id(feed_item),
      first_seen_run_id: run_id,
      title: Map.fetch!(feed_item, :title),
      url: Map.fetch!(feed_item, :url),
      comments_url: Map.get(feed_item, :comments_url),
      published_at: parse_datetime(Map.get(feed_item, :published_at)),
      first_seen_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp seen_items_by_id(_repo, _chat_id, []), do: {:ok, %{}}

  defp seen_items_by_id(repo, chat_id, feed_items) do
    item_ids = Enum.map(feed_items, &item_id/1)

    seen_items =
      SeenItem
      |> where([item], item.chat_id == ^chat_id)
      |> where([item], item.item_id in ^item_ids)
      |> select([item], {item.item_id, item.first_seen_run_id})
      |> repo.all()
      |> Map.new()

    {:ok, seen_items}
  end

  defp classify_items(feed_items, seen_items, run_id) do
    Enum.reduce_while(feed_items, {:ok, %{new_items: [], duplicate_items: []}}, fn item,
                                                                                   {:ok, acc} ->
      id = item_id(item)

      case Map.fetch(seen_items, id) do
        {:ok, ^run_id} ->
          {:cont, {:ok, update_in(acc.new_items, &[item | &1])}}

        {:ok, _other_run_id} ->
          {:cont, {:ok, update_in(acc.duplicate_items, &[item | &1])}}

        :error ->
          {:halt, {:error, {:seen_item_not_found, id}}}
      end
    end)
    |> case do
      {:ok, acc} ->
        {:ok,
         %{
           new_items: Enum.reverse(acc.new_items),
           duplicate_items: Enum.reverse(acc.duplicate_items)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unique_feed_items(feed_items) do
    {_seen_ids, unique_items} =
      Enum.reduce(feed_items, {MapSet.new(), []}, fn item, {seen_ids, acc} ->
        id = item_id(item)

        if MapSet.member?(seen_ids, id) do
          {seen_ids, acc}
        else
          {MapSet.put(seen_ids, id), [item | acc]}
        end
      end)

    Enum.reverse(unique_items)
  end

  defp fetch_feed_items(attrs) do
    case value(attrs, :feed_items) do
      feed_items when is_list(feed_items) -> normalize_feed_items(feed_items)
      _value -> {:error, :missing_feed_items}
    end
  end

  defp normalize_feed_items(feed_items) do
    feed_items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case normalize_feed_item(item) do
        {:ok, feed_item} -> {:cont, {:ok, [feed_item | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_feed_item, reason}}}
      end
    end)
    |> case do
      {:ok, normalized_items} -> {:ok, Enum.reverse(normalized_items)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_feed_item(item) when is_map(item) do
    with {:ok, id} <- fetch_non_empty_binary(item, :id),
         {:ok, title} <- fetch_non_empty_binary(item, :title),
         {:ok, url} <- fetch_non_empty_binary(item, :url) do
      {:ok,
       %{
         id: id,
         title: title,
         url: url,
         comments_url: optional_binary(item, :comments_url),
         published_at: optional_binary(item, :published_at)
       }}
    end
  end

  defp normalize_feed_item(_item), do: {:error, :invalid_item}

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

  defp optional_binary(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      _value -> nil
    end
  end

  defp value(map, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.fetch!(map, key)
      Map.has_key?(map, string_key) -> Map.fetch!(map, string_key)
      true -> nil
    end
  end

  defp item_id(feed_item), do: Map.fetch!(feed_item, :id)

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> ensure_microsecond_precision(datetime)
      {:error, _reason} -> nil
    end
  end

  defp ensure_microsecond_precision(%DateTime{microsecond: {microsecond, _precision}} = datetime) do
    %{datetime | microsecond: {microsecond, 6}}
  end
end
