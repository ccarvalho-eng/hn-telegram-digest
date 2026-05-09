defmodule HnTelegramDigest.Workflows.DeliverHnDigest.FormatTelegramDigestTest do
  use ExUnit.Case, async: true

  alias HnTelegramDigest.Workflows.DeliverHnDigest.FormatTelegramDigest

  test "run returns Telegram transport data for the digest send step" do
    feed_item = %{
      id: "https://news.ycombinator.com/item?id=44123461",
      title: "Workflow formatted item",
      url: "https://example.com/workflow-formatted-item",
      comments_url: "https://news.ycombinator.com/item?id=44123461",
      published_at: "2026-05-08T12:00:00Z"
    }

    assert {:ok,
            %{
              chat_id: 12_345,
              text: text,
              item_count: 1,
              included_item_count: 1,
              omitted_item_count: 0,
              item_ids: ["https://news.ycombinator.com/item?id=44123461"],
              included_item_ids: ["https://news.ycombinator.com/item?id=44123461"],
              empty: false,
              idempotency_key: "workflow/run-1/send_digest"
            }} =
             FormatTelegramDigest.run(
               %{chat_id: 12_345, new_items: [feed_item]},
               %{run_id: "run-1"}
             )

    assert text =~ "1. Workflow formatted item"
    assert text =~ "https://example.com/workflow-formatted-item"
  end
end
