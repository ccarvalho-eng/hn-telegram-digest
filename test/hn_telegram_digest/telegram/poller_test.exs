defmodule HnTelegramDigest.Telegram.PollerTest do
  use HnTelegramDigest.DataCase, async: true

  import ExUnit.CaptureLog

  alias HnTelegramDigest.Telegram.Poller
  alias HnTelegramDigest.Telegram.Update
  alias HnTelegramDigest.Telegram.UpdateStore

  defmodule StaticClient do
    @behaviour HnTelegramDigest.Telegram.Client

    @impl HnTelegramDigest.Telegram.Client
    def get_updates(_token, _opts) do
      {:ok, [%{"update_id" => 500, "message" => %{"text" => "/start"}}]}
    end

    @impl HnTelegramDigest.Telegram.Client
    def send_message(_token, _params, _opts), do: {:ok, %{}}
  end

  defmodule ReclaimingHandler do
    @behaviour HnTelegramDigest.Telegram.UpdateHandler

    @impl true
    def handle_update(%{"update_id" => update_id}) do
      stale_started_at =
        DateTime.utc_now(:microsecond)
        |> DateTime.add(-10, :minute)

      HnTelegramDigest.Repo.get!(Update, update_id)
      |> Ecto.Changeset.change(processing_started_at: stale_started_at)
      |> HnTelegramDigest.Repo.update!()

      assert {1, nil} =
               UpdateStore.requeue_stale_processing(HnTelegramDigest.Repo, :timer.minutes(5))

      assert {:ok, [%Update{} = reclaimed_update]} =
               UpdateStore.claim_received(HnTelegramDigest.Repo)

      assert :ok =
               UpdateStore.mark_handled(
                 HnTelegramDigest.Repo,
                 reclaimed_update.update_id,
                 reclaimed_update.processing_token
               )

      :ok
    end
  end

  test "does not crash when a handler finishes after its processing claim expired" do
    {:ok, state} =
      Poller.init(
        api_base_url: "https://api.telegram.org",
        bot_token: "123:abc",
        client: StaticClient,
        repo: Repo,
        update_handler: ReclaimingHandler,
        polling: [
          timeout_seconds: 1,
          limit: 100,
          allowed_updates: ["message"],
          processing_timeout_ms: :timer.minutes(5),
          error_backoff_ms: :timer.seconds(5)
        ]
      )

    flush_poll_message()

    log =
      capture_log(fn ->
        assert {:noreply, ^state} = Poller.handle_info(:poll, state)
      end)

    assert log =~ "Telegram update claim expired before terminal transition"
    assert %Update{status: "handled"} = Repo.get!(Update, 500)

    flush_poll_message()
  end

  defp flush_poll_message do
    receive do
      :poll -> :ok
    after
      0 -> :ok
    end
  end
end
