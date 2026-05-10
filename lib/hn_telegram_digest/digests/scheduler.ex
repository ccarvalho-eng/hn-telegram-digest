defmodule HnTelegramDigest.Digests.Scheduler do
  @moduledoc """
  Schedules and starts Hacker News digest workflows for active subscriptions.
  """

  import Ecto.Query

  alias HnTelegramDigest.Repo
  alias HnTelegramDigest.Telegram.Subscription
  alias HnTelegramDigest.Telegram.Subscriptions
  alias HnTelegramDigest.Workflows.DeliverHnDigest

  @type start_due_result :: %{
          required(:window_start_at) => String.t(),
          required(:active_subscription_count) => non_neg_integer(),
          required(:started_count) => non_neg_integer(),
          required(:errors) => [map()]
        }

  @type start_result :: %{
          required(:status) => String.t(),
          required(:chat_id) => integer(),
          required(:window_start_at) => String.t(),
          optional(:workflow_run_id) => String.t(),
          optional(:reason) => String.t()
        }

  @doc """
  Starts digest workflows for all active subscriptions due in the schedule window.
  """
  @spec start_due_digests(DateTime.t() | String.t(), module()) ::
          {:ok, start_due_result()} | {:error, start_due_result() | term()}
  def start_due_digests(window_start_at \\ DateTime.utc_now(:second), repo \\ Repo) do
    with {:ok, window} <- normalize_window_start_at(window_start_at) do
      window_iso = DateTime.to_iso8601(window)
      chat_ids = Subscriptions.list_active_chat_ids(repo)

      result =
        Enum.reduce(chat_ids, base_due_result(window_iso, length(chat_ids)), fn chat_id, acc ->
          merge_start_due_result(acc, start_scheduled_digest(chat_id, window_iso, repo))
        end)

      if result.errors == [] do
        {:ok, result}
      else
        {:error, result}
      end
    end
  end

  @doc """
  Starts one digest workflow for a chat and schedule window.
  """
  @spec start_scheduled_digest(integer(), DateTime.t() | String.t(), module()) ::
          {:ok, start_result()} | {:error, term()}
  def start_scheduled_digest(chat_id, window_start_at, repo \\ Repo)

  def start_scheduled_digest(chat_id, window_start_at, repo) when is_integer(chat_id) do
    with {:ok, window} <- normalize_window_start_at(window_start_at) do
      start_digest_for_active_subscription(repo, chat_id, window)
    end
  end

  def start_scheduled_digest(_chat_id, _window_start_at, _repo) do
    {:error, :invalid_chat_id}
  end

  @doc """
  Starts one on-demand digest workflow for a chat if the subscription is active.
  """
  @spec start_manual_digest(integer(), DateTime.t() | String.t(), module()) ::
          {:ok, start_result()} | {:error, term()}
  def start_manual_digest(chat_id, requested_at \\ DateTime.utc_now(:second), repo \\ Repo)

  def start_manual_digest(chat_id, requested_at, repo) when is_integer(chat_id) do
    with {:ok, window} <- normalize_window_start_at(requested_at) do
      start_digest_for_active_subscription(repo, chat_id, window)
    end
  end

  def start_manual_digest(_chat_id, _requested_at, _repo) do
    {:error, :invalid_chat_id}
  end

  defp merge_start_due_result(acc, {:ok, %{status: "started"}}) do
    %{acc | started_count: acc.started_count + 1}
  end

  defp merge_start_due_result(acc, {:ok, %{status: "skipped"}}) do
    acc
  end

  defp merge_start_due_result(acc, {:error, reason}) do
    %{acc | errors: [%{reason: inspect(reason)} | acc.errors]}
  end

  defp base_due_result(window_iso, active_subscription_count) do
    %{
      window_start_at: window_iso,
      active_subscription_count: active_subscription_count,
      started_count: 0,
      errors: []
    }
  end

  defp active_subscription_locked?(repo, chat_id) do
    Subscription
    |> where([subscription], subscription.chat_id == ^chat_id)
    |> where([subscription], subscription.status == "active")
    |> lock("FOR SHARE")
    |> select([subscription], true)
    |> repo.exists?()
  end

  defp start_digest_for_active_subscription(repo, chat_id, window) do
    window_iso = DateTime.to_iso8601(window)

    repo.transaction(fn ->
      with true <- active_subscription_locked?(repo, chat_id) || {:skip, :inactive_subscription},
           {:ok, result} <- start_digest_run(repo, chat_id, window_iso) do
        result
      else
        {:skip, :inactive_subscription} ->
          skipped_result(chat_id, window_iso)

        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
  end

  defp start_digest_run(repo, chat_id, window_iso) do
    payload = %{chat_id: chat_id, window_start_at: window_iso}

    with {:ok, run} <-
           SquidMesh.start_run(DeliverHnDigest, :digest_requested, payload, repo: repo) do
      {:ok,
       %{
         status: "started",
         chat_id: chat_id,
         window_start_at: window_iso,
         workflow_run_id: run.id
       }}
    end
  end

  defp skipped_result(chat_id, window_iso) do
    %{
      status: "skipped",
      reason: "inactive_subscription",
      chat_id: chat_id,
      window_start_at: window_iso
    }
  end

  defp normalize_window_start_at(%DateTime{} = datetime) do
    {:ok,
     datetime
     |> DateTime.shift_zone!("Etc/UTC")
     |> floor_to_minute()}
  end

  defp normalize_window_start_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_window_start_at(datetime)
      {:error, _reason} -> {:error, {:invalid_window_start_at, value}}
    end
  end

  defp normalize_window_start_at(value), do: {:error, {:invalid_window_start_at, value}}

  defp floor_to_minute(%DateTime{} = datetime) do
    %{datetime | second: 0, microsecond: {0, 0}}
  end
end
