defmodule HnTelegramDigest.HackerNews.DeduplicationTest do
  use HnTelegramDigest.DataCase, async: false

  alias HnTelegramDigest.HackerNews.Deduplication
  alias HnTelegramDigest.HackerNews.SeenItem
  alias HnTelegramDigest.Telegram.Subscriptions

  setup do
    assert {:ok, %{status: "active"}} =
             Subscriptions.apply_subscription_command(%{
               action: "subscribe",
               chat: %{id: 12_345, type: "private", username: "hn_reader"}
             })

    :ok
  end

  test "reserve_new_items returns only feed items not seen by the chat" do
    assert {:ok, %{new_items: [first_item], duplicate_items: []}} =
             Deduplication.reserve_new_items(%{
               chat_id: 12_345,
               run_id: "run-1",
               feed_items: [feed_item("44123456")]
             })

    assert {:ok, %{new_items: [second_item], duplicate_items: [^first_item]}} =
             Deduplication.reserve_new_items(%{
               chat_id: 12_345,
               run_id: "run-2",
               feed_items: [feed_item("44123456"), feed_item("44123457")]
             })

    assert %{id: "https://news.ycombinator.com/item?id=44123456"} = first_item
    assert %{id: "https://news.ycombinator.com/item?id=44123457"} = second_item
  end

  test "reserve_new_items replays the same new items for the same workflow run" do
    attrs = %{
      chat_id: 12_345,
      run_id: "run-retry",
      feed_items: [feed_item("44123458")]
    }

    assert {:ok, %{new_items: [item], duplicate_items: []}} =
             Deduplication.reserve_new_items(attrs)

    assert {:ok, %{new_items: [^item], duplicate_items: []}} =
             Deduplication.reserve_new_items(attrs)

    assert [
             %SeenItem{
               chat_id: 12_345,
               item_id: "https://news.ycombinator.com/item?id=44123458",
               first_seen_run_id: "run-retry"
             }
           ] = Repo.all(SeenItem)
  end

  test "reserve_new_items lets only the first competing run reserve an item" do
    feed_items = [feed_item("44123459")]

    assert {:ok, %{new_items: [item], duplicate_items: []}} =
             Deduplication.reserve_new_items(%{
               chat_id: 12_345,
               run_id: "run-winner",
               feed_items: feed_items
             })

    assert {:ok, %{new_items: [], duplicate_items: [^item]}} =
             Deduplication.reserve_new_items(%{
               chat_id: 12_345,
               run_id: "run-loser",
               feed_items: feed_items
             })
  end

  test "reserve_new_items collapses duplicate feed entries before reserving" do
    item = feed_item("44123460")

    assert {:ok, %{new_items: [^item], duplicate_items: []}} =
             Deduplication.reserve_new_items(%{
               chat_id: 12_345,
               run_id: "run-duplicates",
               feed_items: [item, item]
             })

    assert 1 = Repo.aggregate(SeenItem, :count)
  end

  test "reserve_new_items accepts string-key workflow payloads" do
    item = string_key_feed_item("44123462")

    assert {:ok,
            %{
              new_items: [
                %{
                  id: "https://news.ycombinator.com/item?id=44123462",
                  title: "HN story 44123462"
                }
              ],
              duplicate_items: []
            }} =
             Deduplication.reserve_new_items(%{
               "chat_id" => 12_345,
               "run_id" => "run-string-keys",
               "feed_items" => [item]
             })
  end

  test "reserve_new_items validates workflow input" do
    assert {:error, :missing_chat_id} =
             Deduplication.reserve_new_items(%{run_id: "run-1", feed_items: []})

    assert {:error, :missing_run_id} =
             Deduplication.reserve_new_items(%{chat_id: 12_345, feed_items: []})

    assert {:error, :missing_feed_items} =
             Deduplication.reserve_new_items(%{chat_id: 12_345, run_id: "run-1"})

    assert {:error, {:invalid_feed_item, :missing_id}} =
             Deduplication.reserve_new_items(%{
               chat_id: 12_345,
               run_id: "run-1",
               feed_items: [%{title: "Missing id"}]
             })
  end

  test "reserve_new_items returns a structured error for missing chats" do
    assert {:error, :telegram_chat_not_found} =
             Deduplication.reserve_new_items(%{
               chat_id: 99_999,
               run_id: "run-missing-chat",
               feed_items: [feed_item("44123463")]
             })
  end

  defp feed_item(id) do
    item_id = "https://news.ycombinator.com/item?id=#{id}"

    %{
      id: item_id,
      title: "HN story #{id}",
      url: "https://example.com/#{id}",
      comments_url: item_id,
      published_at: "2026-05-08T12:00:00Z"
    }
  end

  defp string_key_feed_item(id) do
    id
    |> feed_item()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
