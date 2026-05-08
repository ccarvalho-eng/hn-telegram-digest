defmodule HnTelegramDigest.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HnTelegramDigest.Repo,
      {Oban, Application.fetch_env!(:hn_telegram_digest, Oban)}
    ]

    opts = [strategy: :one_for_one, name: HnTelegramDigest.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
