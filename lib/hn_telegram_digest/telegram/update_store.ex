defmodule HnTelegramDigest.Telegram.UpdateStore do
  @moduledoc false

  import Ecto.Query

  alias HnTelegramDigest.Telegram.Update

  def next_offset(repo) do
    case repo.aggregate(Update, :max, :update_id) do
      nil -> nil
      update_id -> update_id + 1
    end
  end

  def insert_new_updates(repo, updates) when is_list(updates) do
    now = DateTime.utc_now(:microsecond)

    rows =
      Enum.map(updates, fn update ->
        %{
          update_id: Map.fetch!(update, "update_id"),
          payload: update,
          status: "received",
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _updates} =
      repo.insert_all(Update, rows,
        on_conflict: :nothing,
        conflict_target: [:update_id],
        returning: false
      )

    {:ok, count}
  end

  def requeue_stale_processing(repo, timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    now = DateTime.utc_now(:microsecond)

    stale_before =
      DateTime.add(now, -timeout_ms, :millisecond)

    Update
    |> where([update], update.status == "processing")
    |> where([update], update.processing_started_at < ^stale_before)
    |> repo.update_all(
      set: [
        status: "received",
        processing_token: nil,
        processing_started_at: nil,
        updated_at: now
      ]
    )
  end

  def claim_received(repo) do
    repo.transaction(fn ->
      updates =
        Update
        |> where([update], update.status == "received")
        |> order_by([update], asc: update.update_id)
        |> lock("FOR UPDATE SKIP LOCKED")
        |> repo.all()

      update_ids = Enum.map(updates, & &1.update_id)
      now = DateTime.utc_now(:microsecond)
      processing_token = Ecto.UUID.generate()

      Update
      |> where([update], update.update_id in ^update_ids)
      |> repo.update_all(
        set: [
          status: "processing",
          processing_token: processing_token,
          processing_started_at: now,
          updated_at: now
        ]
      )

      Enum.map(updates, fn %Update{} = update ->
        %Update{
          update
          | status: "processing",
            processing_token: processing_token,
            processing_started_at: now
        }
      end)
    end)
  end

  def mark_handled(repo, update_id, processing_token) do
    now = DateTime.utc_now(:microsecond)

    count =
      Update
      |> where([update], update.update_id == ^update_id)
      |> where([update], update.status == "processing")
      |> where([update], update.processing_token == ^processing_token)
      |> repo.update_all(
        set: [
          status: "handled",
          last_error: nil,
          processing_token: nil,
          processing_started_at: nil,
          handled_at: now,
          updated_at: now
        ]
      )
      |> elem(0)

    transition_result(count)
  end

  def mark_failed(repo, update_id, processing_token, reason) do
    now = DateTime.utc_now(:microsecond)

    count =
      Update
      |> where([update], update.update_id == ^update_id)
      |> where([update], update.status == "processing")
      |> where([update], update.processing_token == ^processing_token)
      |> repo.update_all(
        set: [
          status: "failed",
          last_error: reason_to_error(reason),
          processing_token: nil,
          processing_started_at: nil,
          updated_at: now
        ]
      )
      |> elem(0)

    transition_result(count)
  end

  defp transition_result(1), do: :ok
  defp transition_result(0), do: {:error, :stale_claim}

  defp reason_to_error(reason) when is_atom(reason) do
    %{"reason" => Atom.to_string(reason)}
  end

  defp reason_to_error({reason, _details}) when is_atom(reason) do
    %{"reason" => Atom.to_string(reason)}
  end

  defp reason_to_error(%{__exception__: true} = exception) do
    %{"reason" => exception.__struct__ |> Module.split() |> Enum.join(".")}
  end

  defp reason_to_error(_reason), do: %{"reason" => "handler_error"}
end
