defmodule HnTelegramDigest.Workflows.DeliverHnDigest.DedupeItemsTest do
  use HnTelegramDigest.DataCase, async: false

  alias HnTelegramDigest.Telegram.Subscriptions
  alias HnTelegramDigest.Workflows.DeliverHnDigest.DedupeItems

  setup do
    assert {:ok, %{status: "active"}} =
             Subscriptions.apply_subscription_command(%{
               action: "subscribe",
               chat: %{id: 12_345, type: "private", username: "hn_reader"}
             })

    :ok
  end

  test "run reserves new Hacker News items for workflow transport" do
    feed_item = %{
      id: "https://news.ycombinator.com/item?id=44123461",
      title: "Workflow item",
      url: "https://example.com/workflow-item",
      comments_url: "https://news.ycombinator.com/item?id=44123461",
      published_at: "2026-05-08T12:00:00Z"
    }

    assert {:ok, %{new_items: [^feed_item], duplicate_items: []}} =
             DedupeItems.run(
               %{chat_id: 12_345, feed_items: [feed_item]},
               %{run_id: "workflow-run-1"}
             )
  end
end
