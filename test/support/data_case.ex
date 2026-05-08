defmodule HnTelegramDigest.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias HnTelegramDigest.Repo
    end
  end

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(HnTelegramDigest.Repo)
    :ok
  end
end
