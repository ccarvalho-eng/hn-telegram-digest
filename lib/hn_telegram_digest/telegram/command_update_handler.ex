defmodule HnTelegramDigest.Telegram.CommandUpdateHandler do
  @moduledoc false

  @behaviour HnTelegramDigest.Telegram.UpdateHandler

  require Logger

  alias HnTelegramDigest.Digests.Scheduler
  alias HnTelegramDigest.Telegram.Command
  alias HnTelegramDigest.Telegram.MessageDeliveries
  alias HnTelegramDigest.Workflows.HandleSubscriptionCommand

  @digest_inactive_text "Subscribe with /start before requesting a Hacker News digest."
  @unsupported_command_text "That command is not supported yet. Available commands: /start, /stop, /digest."

  @impl true
  def handle_update(update) when is_map(update) do
    case Command.from_update(update) do
      {:ok, command} ->
        handle_command(command)

      :ignore ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_command(%{action: action} = command) when action in ["subscribe", "unsubscribe"] do
    start_subscription_workflow(command)
  end

  defp handle_command(%{action: "digest", chat: %{id: chat_id}} = command) do
    case Scheduler.start_manual_digest(chat_id) do
      {:ok, %{status: "started", workflow_run_id: run_id}} ->
        Logger.info("Started manual Hacker News digest workflow run=#{run_id}")
        :ok

      {:ok, %{status: "skipped", reason: "inactive_subscription"}} ->
        deliver_command_reply(command, @digest_inactive_text, "digest_inactive_subscription")

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_command(%{action: "unsupported"} = command) do
    deliver_command_reply(command, @unsupported_command_text, "unsupported_command")
  end

  defp start_subscription_workflow(command) do
    case SquidMesh.start_run(HandleSubscriptionCommand, %{subscription_command: command}) do
      {:ok, run} ->
        Logger.info("Started Telegram subscription command workflow run=#{run.id}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deliver_command_reply(%{chat: %{id: chat_id}, update_id: update_id}, text, reason) do
    attrs = %{
      idempotency_key: "telegram_update/#{update_id}/#{reason}",
      chat_id: chat_id,
      text: text
    }

    with {:ok, _delivery} <-
           :hn_telegram_digest
           |> Application.fetch_env!(:telegram)
           |> then(&MessageDeliveries.deliver_once(attrs, &1)) do
      :ok
    end
  end
end
