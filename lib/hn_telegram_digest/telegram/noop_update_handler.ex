defmodule HnTelegramDigest.Telegram.NoopUpdateHandler do
  @moduledoc false

  @behaviour HnTelegramDigest.Telegram.UpdateHandler

  @impl true
  def handle_update(_update), do: :ok
end
