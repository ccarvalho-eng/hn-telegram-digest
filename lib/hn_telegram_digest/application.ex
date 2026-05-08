defmodule HnTelegramDigest.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        HnTelegramDigest.Repo,
        {Oban, Application.fetch_env!(:hn_telegram_digest, Oban)}
      ] ++ telegram_children()

    opts = [strategy: :one_for_one, name: HnTelegramDigest.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp telegram_children do
    telegram_config = Application.fetch_env!(:hn_telegram_digest, :telegram)
    polling_config = Keyword.fetch!(telegram_config, :polling)

    if Keyword.get(polling_config, :enabled, false) do
      [{HnTelegramDigest.Telegram.Poller, telegram_config}]
    else
      []
    end
  end
end
