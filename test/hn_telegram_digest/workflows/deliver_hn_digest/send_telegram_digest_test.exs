defmodule HnTelegramDigest.Workflows.DeliverHnDigest.SendTelegramDigestTest do
  use HnTelegramDigest.DataCase, async: false

  import Mox

  alias HnTelegramDigest.Telegram.MessageDelivery
  alias HnTelegramDigest.Telegram.Subscriptions
  alias HnTelegramDigest.TelegramClientMock
  alias HnTelegramDigest.Workflows.DeliverHnDigest.SendTelegramDigest

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    telegram_config = Application.fetch_env!(:hn_telegram_digest, :telegram)
    delivery_agent = start_supervised!({Agent, fn -> [] end})

    assert {:ok, %{status: "active"}} =
             Subscriptions.apply_subscription_command(%{
               action: "subscribe",
               chat: %{
                 id: 12_345,
                 type: "private"
               }
             })

    Application.put_env(
      :hn_telegram_digest,
      :telegram,
      Keyword.merge(telegram_config,
        bot_token: "123:abc",
        client: TelegramClientMock
      )
    )

    on_exit(fn ->
      Application.put_env(:hn_telegram_digest, :telegram, telegram_config)
    end)

    {:ok, delivery_agent: delivery_agent}
  end

  test "run sends a formatted digest and records sent status", %{delivery_agent: delivery_agent} do
    digest = formatted_digest("run-1")

    expect(TelegramClientMock, :send_message, fn "123:abc", params, opts ->
      assert %{chat_id: 12_345, text: "Hacker News digest\n\n1. Story\nhttps://example.com"} =
               params

      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      Agent.update(delivery_agent, &[Map.take(params, [:chat_id, :text]) | &1])

      {:ok, %{"message_id" => 501}}
    end)

    assert {:ok,
            %{
              status: "sent",
              duplicate?: false,
              telegram_message_id: 501,
              chat_id: 12_345,
              empty: false,
              idempotency_key: "workflow/run-1/send_digest"
            }} = SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-1"})

    assert [
             %{
               chat_id: 12_345,
               text: "Hacker News digest\n\n1. Story\nhttps://example.com"
             }
           ] = delivered_messages(delivery_agent)

    assert %MessageDelivery{
             idempotency_key: "workflow/run-1/send_digest",
             chat_id: 12_345,
             text: "Hacker News digest\n\n1. Story\nhttps://example.com",
             status: "sent",
             telegram_message_id: 501,
             last_error: nil,
             sent_at: %DateTime{}
           } = Repo.get_by!(MessageDelivery, idempotency_key: "workflow/run-1/send_digest")
  end

  test "run retry after success returns a duplicate result without calling Telegram again" do
    digest = formatted_digest("run-2")

    expect(TelegramClientMock, :send_message, fn "123:abc", _params, _opts ->
      {:ok, %{"message_id" => 502}}
    end)

    assert {:ok, %{status: "sent", duplicate?: false}} =
             SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-2"})

    assert {:ok,
            %{
              status: "sent",
              duplicate?: true,
              telegram_message_id: 502,
              idempotency_key: "workflow/run-2/send_digest"
            }} = SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-2"})
  end

  test "run records API failures and allows a later retry", %{delivery_agent: delivery_agent} do
    digest = formatted_digest("run-3")

    Agent.update(delivery_agent, fn _messages -> :fail_once end)

    expect(TelegramClientMock, :send_message, 2, fn "123:abc", params, _opts ->
      Agent.get_and_update(delivery_agent, fn
        :fail_once ->
          {{:error, {:telegram_error, 429, %{"description" => "retry later"}}}, []}

        messages ->
          message = Map.take(params, [:chat_id, :text])
          {{:ok, %{"message_id" => 503}}, [message | messages]}
      end)
    end)

    assert {:error, {:telegram_error, 429, %{"description" => "retry later"}}} =
             SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-3"})

    assert %MessageDelivery{
             status: "failed",
             last_error: %{"kind" => "telegram_error", "status" => 429}
           } = Repo.get_by!(MessageDelivery, idempotency_key: "workflow/run-3/send_digest")

    assert {:ok,
            %{
              status: "sent",
              duplicate?: false,
              telegram_message_id: 503,
              idempotency_key: "workflow/run-3/send_digest"
            }} = SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-3"})
  end

  test "run returns structured configuration errors from the delivery boundary" do
    telegram_config = Application.fetch_env!(:hn_telegram_digest, :telegram)

    Application.put_env(
      :hn_telegram_digest,
      :telegram,
      Keyword.put(telegram_config, :bot_token, nil)
    )

    assert {:error, :missing_telegram_bot_token} =
             SendTelegramDigest.run(%{digest: formatted_digest("run-4")}, %{run_id: "run-4"})

    assert %MessageDelivery{
             status: "failed",
             last_error: %{"kind" => "missing_telegram_bot_token"}
           } = Repo.get_by!(MessageDelivery, idempotency_key: "workflow/run-4/send_digest")
  end

  test "run skips empty digests without creating a delivery row" do
    digest = %{
      formatted_digest("run-5")
      | empty: true,
        text: "Hacker News digest\n\nNo new stories."
    }

    assert {:ok,
            %{
              status: "skipped",
              reason: "empty_digest",
              duplicate?: false,
              chat_id: 12_345,
              empty: true,
              idempotency_key: "workflow/run-5/send_digest"
            }} = SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-5"})

    refute Repo.get_by(MessageDelivery, idempotency_key: "workflow/run-5/send_digest")
  end

  test "run skips delivery if the chat unsubscribed before the send step" do
    digest = formatted_digest("run-6")

    assert {:ok, %{status: "inactive"}} =
             Subscriptions.apply_subscription_command(%{
               action: "unsubscribe",
               chat: %{
                 id: 12_345,
                 type: "private"
               }
             })

    assert {:ok,
            %{
              status: "skipped",
              reason: "inactive_subscription",
              duplicate?: false,
              chat_id: 12_345,
              empty: false,
              idempotency_key: "workflow/run-6/send_digest"
            }} = SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-6"})

    refute Repo.get_by(MessageDelivery, idempotency_key: "workflow/run-6/send_digest")
  end

  test "run rejects stale formatted idempotency metadata" do
    digest = %{formatted_digest("run-7") | idempotency_key: "workflow/other-run/send_digest"}

    assert {:error, :digest_idempotency_key_mismatch} =
             SendTelegramDigest.run(%{digest: digest}, %{run_id: "run-7"})
  end

  defp formatted_digest(run_id) do
    %{
      chat_id: 12_345,
      text: "Hacker News digest\n\n1. Story\nhttps://example.com",
      item_count: 1,
      included_item_count: 1,
      omitted_item_count: 0,
      item_ids: ["https://news.ycombinator.com/item?id=44123461"],
      included_item_ids: ["https://news.ycombinator.com/item?id=44123461"],
      empty: false,
      idempotency_key: "workflow/#{run_id}/send_digest"
    }
  end

  defp delivered_messages(delivery_agent) do
    Agent.get(delivery_agent, fn
      :fail_once -> []
      messages -> Enum.reverse(messages)
    end)
  end
end
