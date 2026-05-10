defmodule Mix.Tasks.HnTelegramDigest.ExplainRun do
  @moduledoc """
  Prints a Squid Mesh workflow run explanation.
  """

  use Mix.Task

  alias HnTelegramDigest.Operators.RunDiagnostics

  @shortdoc "Prints a Squid Mesh workflow run explanation"

  @impl true
  def run([run_id]) do
    Mix.Task.run("app.start")

    case RunDiagnostics.explain_run(run_id) do
      {:ok, output} -> Mix.shell().info(output)
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix hn_telegram_digest.explain_run RUN_ID")
  end
end
