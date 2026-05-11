defmodule HnTelegramDigest.Workflows.DeliverHnDigest do
  @moduledoc """
  Squid Mesh workflow that fetches, deduplicates, formats, and sends one digest.
  """

  use SquidMesh.Workflow

  alias HnTelegramDigest.Workflows.DeliverHnDigest.DedupeItems
  alias HnTelegramDigest.Workflows.DeliverHnDigest.FetchHackerNewsRss
  alias HnTelegramDigest.Workflows.DeliverHnDigest.FormatTelegramDigest
  alias HnTelegramDigest.Workflows.DeliverHnDigest.SendTelegramDigest

  workflow do
    trigger :manual_digest do
      manual()

      payload do
        field(:chat_id, :integer)
        field(:window_start_at, :string)
      end
    end

    trigger :scheduled_digest do
      manual()

      payload do
        field(:chat_id, :integer)
        field(:window_start_at, :string)
      end
    end

    step(:fetch_feed, FetchHackerNewsRss)

    step(:dedupe_items, DedupeItems, input: [:chat_id, :feed_items])

    step(:format_message, FormatTelegramDigest,
      input: [:chat_id, :new_items],
      output: :digest
    )

    step(:send_digest, SendTelegramDigest,
      input: [:digest],
      output: :delivery
    )

    transition(:fetch_feed, on: :ok, to: :dedupe_items)
    transition(:dedupe_items, on: :ok, to: :format_message)
    transition(:format_message, on: :ok, to: :send_digest)
    transition(:send_digest, on: :ok, to: :complete)
  end
end
