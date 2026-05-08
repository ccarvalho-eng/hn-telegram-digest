defmodule HnTelegramDigest.Telegram.CommandUpdateHandler do
  @moduledoc false

  @behaviour HnTelegramDigest.Telegram.UpdateHandler

  require Logger

  alias HnTelegramDigest.Telegram.SubscriptionCommand
  alias HnTelegramDigest.Workflows.HandleSubscriptionCommand

  @impl true
  def handle_update(update) when is_map(update) do
    case SubscriptionCommand.from_update(update) do
      {:ok, command} ->
        start_subscription_workflow(command)

      :ignore ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
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
end
