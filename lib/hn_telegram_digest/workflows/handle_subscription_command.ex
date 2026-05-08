defmodule HnTelegramDigest.Workflows.HandleSubscriptionCommand do
  @moduledoc false

  use SquidMesh.Workflow

  alias HnTelegramDigest.Workflows.HandleSubscriptionCommand.ConfirmChange
  alias HnTelegramDigest.Workflows.HandleSubscriptionCommand.ParseTelegramCommand
  alias HnTelegramDigest.Workflows.HandleSubscriptionCommand.UpdatePreferences

  workflow do
    trigger :telegram_update do
      manual()

      payload do
        field(:subscription_command, :map)
      end
    end

    step(:parse_command, ParseTelegramCommand,
      input: [:subscription_command],
      output: :subscription_command
    )

    step(:update_preferences, UpdatePreferences,
      input: [:subscription_command],
      output: :subscription_change
    )

    step(:confirm_change, ConfirmChange,
      input: [:subscription_change],
      output: :confirmation_delivery
    )

    transition(:parse_command, on: :ok, to: :update_preferences)
    transition(:update_preferences, on: :ok, to: :confirm_change)
    transition(:confirm_change, on: :ok, to: :complete)
  end
end
