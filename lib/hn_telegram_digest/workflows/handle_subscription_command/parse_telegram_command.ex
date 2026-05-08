defmodule HnTelegramDigest.Workflows.HandleSubscriptionCommand.ParseTelegramCommand do
  @moduledoc false

  use Jido.Action,
    name: "parse_telegram_command",
    description: "Parses a Telegram subscription command",
    schema: [
      subscription_command: [type: :map, required: true]
    ]

  @impl true
  def run(%{subscription_command: command}, _context) do
    with {:ok, action} <- fetch_action(command),
         {:ok, chat} <- fetch_chat(command) do
      {:ok, %{action: action, chat: chat}}
    end
  end

  defp fetch_action(command) do
    case Map.get(command, :action) do
      action when action in ["subscribe", "unsubscribe"] -> {:ok, action}
      _other -> {:error, :unsupported_subscription_action}
    end
  end

  defp fetch_chat(command) do
    case Map.get(command, :chat) do
      chat when is_map(chat) -> {:ok, chat}
      _other -> {:error, :missing_chat}
    end
  end
end
