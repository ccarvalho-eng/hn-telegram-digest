defmodule HnTelegramDigest.Digests.SchedulerTest do
  use HnTelegramDigest.DataCase, async: false

  alias HnTelegramDigest.Digests.Scheduler
  alias HnTelegramDigest.Telegram.Subscriptions
  alias HnTelegramDigest.Workflows.DeliverHnDigest
  alias HnTelegramDigest.Workflows.ScheduleHnDigests

  @window_start_at "2026-05-09T12:00:00Z"

  test "start_due_digests starts one digest workflow for each active subscription" do
    assert {:ok, %{status: "active"}} = subscribe_chat(12_345)
    assert {:ok, %{status: "active"}} = subscribe_chat(67_890)
    assert {:ok, %{status: "inactive"}} = unsubscribe_chat(55_555)

    assert {:ok,
            %{
              window_start_at: @window_start_at,
              active_subscription_count: 2,
              started_count: 2,
              errors: []
            }} = Scheduler.start_due_digests(@window_start_at)

    assert {:ok, runs} = SquidMesh.list_runs([workflow: DeliverHnDigest], repo: Repo)

    assert [
             %{chat_id: 12_345, window_start_at: @window_start_at},
             %{chat_id: 67_890, window_start_at: @window_start_at}
           ] = runs |> Enum.map(& &1.payload) |> Enum.sort_by(& &1.chat_id)
  end

  test "start_due_digests leaves duplicate scheduled-start protection to Squid Mesh" do
    assert {:ok, %{status: "active"}} = subscribe_chat(12_345)

    assert {:ok, %{started_count: 1, errors: []}} =
             Scheduler.start_due_digests(@window_start_at)

    assert {:ok, %{started_count: 1, errors: []}} =
             Scheduler.start_due_digests(@window_start_at)

    assert {:ok, [_first_run, _second_run]} =
             SquidMesh.list_runs([workflow: DeliverHnDigest], repo: Repo)
  end

  test "start_due_digests returns structured errors for invalid windows" do
    assert {:error, {:invalid_window_start_at, "not-a-datetime"}} =
             Scheduler.start_due_digests("not-a-datetime")
  end

  test "start_scheduled_digest creates a digest workflow run for an active subscription" do
    assert {:ok, %{status: "active"}} = subscribe_chat(12_345)

    assert {:ok,
            %{
              status: "started",
              chat_id: 12_345,
              window_start_at: @window_start_at,
              workflow_run_id: workflow_run_id
            }} = Scheduler.start_scheduled_digest(12_345, @window_start_at)

    assert is_binary(workflow_run_id)

    assert {:ok, [run]} = SquidMesh.list_runs([workflow: DeliverHnDigest], repo: Repo)

    assert :digest_requested = run.trigger

    assert %{
             chat_id: 12_345,
             window_start_at: @window_start_at
           } = run.payload
  end

  test "start_scheduled_digest skips stale scheduler work for inactive subscriptions" do
    assert {:ok, %{status: "inactive"}} = unsubscribe_chat(12_345)

    assert {:ok,
            %{
              status: "skipped",
              reason: "inactive_subscription",
              chat_id: 12_345,
              window_start_at: @window_start_at
            }} = Scheduler.start_scheduled_digest(12_345, @window_start_at)

    assert {:ok, []} = SquidMesh.list_runs([workflow: DeliverHnDigest], repo: Repo)
  end

  test "Squid Mesh schedule workflow fans out without running downstream API steps" do
    assert {:ok, %{status: "active"}} = subscribe_chat(12_345)

    assert {:ok, _run} = SquidMesh.start_run(ScheduleHnDigests, :daily_digest_schedule, %{})

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(queue: :squid_mesh, with_limit: 1, with_safety: false)

    assert {:ok, [schedule_run]} = SquidMesh.list_runs([workflow: ScheduleHnDigests], repo: Repo)
    assert :completed = schedule_run.status

    assert {:ok, [digest_run]} = SquidMesh.list_runs([workflow: DeliverHnDigest], repo: Repo)
    assert :digest_requested = digest_run.trigger
    assert %{chat_id: 12_345, window_start_at: window_start_at} = digest_run.payload
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(window_start_at)
  end

  defp subscribe_chat(chat_id) do
    Subscriptions.apply_subscription_command(%{
      action: "subscribe",
      chat: chat(chat_id)
    })
  end

  defp unsubscribe_chat(chat_id) do
    Subscriptions.apply_subscription_command(%{
      action: "unsubscribe",
      chat: chat(chat_id)
    })
  end

  defp chat(chat_id) do
    %{
      id: chat_id,
      type: "private",
      username: "reader_#{chat_id}"
    }
  end
end
