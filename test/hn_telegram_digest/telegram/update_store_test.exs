defmodule HnTelegramDigest.Telegram.UpdateStoreTest do
  use HnTelegramDigest.DataCase, async: true

  alias HnTelegramDigest.Telegram.Update
  alias HnTelegramDigest.Telegram.UpdateStore

  test "deduplicates updates by Telegram update_id" do
    update = %{"update_id" => 100, "message" => %{"text" => "/start"}}

    assert {:ok, 1} = UpdateStore.insert_new_updates(Repo, [update])
    assert {:ok, 0} = UpdateStore.insert_new_updates(Repo, [update])

    assert [%Update{update_id: 100, status: "received"}] = Repo.all(Update)
  end

  test "calculates the next polling offset from persisted updates" do
    assert is_nil(UpdateStore.next_offset(Repo))

    assert {:ok, 2} =
             UpdateStore.insert_new_updates(Repo, [
               %{"update_id" => 40},
               %{"update_id" => 42}
             ])

    assert UpdateStore.next_offset(Repo) == 43
  end

  test "claims updates before handler side effects" do
    assert {:ok, 2} =
             UpdateStore.insert_new_updates(Repo, [
               %{"update_id" => 10},
               %{"update_id" => 11}
             ])

    assert {:ok, [%Update{update_id: 10} = first, %Update{update_id: 11} = second]} =
             UpdateStore.claim_received(Repo)

    assert {:ok, []} = UpdateStore.claim_received(Repo)

    assert %Update{status: "processing", processing_token: token} =
             processing_update =
             Repo.get!(Update, 10)

    assert is_binary(token)
    assert %DateTime{} = processing_update.processing_started_at

    assert :ok = UpdateStore.mark_handled(Repo, 10, first.processing_token)

    assert :ok =
             UpdateStore.mark_failed(
               Repo,
               11,
               second.processing_token,
               {:bad_command, %{text: "/wat"}}
             )

    assert %Update{
             status: "handled",
             handled_at: %DateTime{},
             last_error: nil,
             processing_token: nil,
             processing_started_at: nil
           } = Repo.get!(Update, 10)

    assert %Update{
             status: "failed",
             last_error: %{"reason" => "bad_command"},
             processing_token: nil,
             processing_started_at: nil
           } = Repo.get!(Update, 11)
  end

  test "rejects stale claim transitions" do
    assert {:ok, 1} = UpdateStore.insert_new_updates(Repo, [%{"update_id" => 15}])

    assert {:ok, [%Update{update_id: 15, processing_token: token}]} =
             UpdateStore.claim_received(Repo)

    assert {:error, :stale_claim} = UpdateStore.mark_handled(Repo, 15, Ecto.UUID.generate())
    assert :ok = UpdateStore.mark_handled(Repo, 15, token)
  end

  test "requeues stale processing updates for recovery" do
    assert {:ok, 1} = UpdateStore.insert_new_updates(Repo, [%{"update_id" => 20}])
    assert {:ok, [%Update{update_id: 20}]} = UpdateStore.claim_received(Repo)

    stale_started_at = DateTime.utc_now(:microsecond) |> DateTime.add(-10, :minute)

    Repo.get!(Update, 20)
    |> Ecto.Changeset.change(processing_started_at: stale_started_at)
    |> Repo.update!()

    assert {1, nil} = UpdateStore.requeue_stale_processing(Repo, :timer.minutes(5))
    assert {:ok, [%Update{update_id: 20}]} = UpdateStore.claim_received(Repo)
  end
end
