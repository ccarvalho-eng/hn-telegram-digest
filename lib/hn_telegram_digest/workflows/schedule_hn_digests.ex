defmodule HnTelegramDigest.Workflows.ScheduleHnDigests do
  @moduledoc """
  Squid Mesh workflow that expands the configured digest schedule.
  """

  use SquidMesh.Workflow

  alias HnTelegramDigest.Workflows.ScheduleHnDigests.StartDueDigests

  @schedule_config Application.compile_env!(:hn_telegram_digest, :digest_schedule)
  @cron_expression Keyword.fetch!(@schedule_config, :cron_expression)
  @timezone Keyword.fetch!(@schedule_config, :timezone)

  workflow do
    trigger :daily_digest_schedule do
      cron(@cron_expression, timezone: @timezone)
    end

    step(:start_due_digests, StartDueDigests, output: :schedule)

    transition(:start_due_digests, on: :ok, to: :complete)
  end
end
