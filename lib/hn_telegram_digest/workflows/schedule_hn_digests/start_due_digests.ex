defmodule HnTelegramDigest.Workflows.ScheduleHnDigests.StartDueDigests do
  @moduledoc """
  Starts due digest workflows for the current scheduler window.
  """

  use Jido.Action,
    name: "start_due_hn_digests",
    description: "Starts Hacker News digest workflows for active subscriptions",
    schema: []

  alias HnTelegramDigest.Digests.Scheduler

  @spec run(map(), map()) :: {:ok, Scheduler.start_due_result()} | {:error, term()}
  @impl Jido.Action
  def run(_params, _context) do
    Scheduler.start_due_digests()
  end
end
