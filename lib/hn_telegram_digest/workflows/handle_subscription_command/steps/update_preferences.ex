defmodule HnTelegramDigest.Workflows.HandleSubscriptionCommand.Steps.UpdatePreferences do
  @moduledoc false

  use Jido.Action,
    name: "update_subscription_preferences",
    description: "Applies Telegram chat subscription preferences",
    schema: [
      subscription_command: [type: :map, required: true]
    ]

  alias HnTelegramDigest.Telegram.Subscriptions

  @impl true
  def run(%{subscription_command: command}, _context) do
    Subscriptions.apply_subscription_command(command)
  end
end
