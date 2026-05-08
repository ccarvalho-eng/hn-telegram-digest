defmodule HnTelegramDigest.Telegram.UpdateHandler do
  @moduledoc false

  @callback handle_update(map()) :: :ok | {:error, term()}
end
