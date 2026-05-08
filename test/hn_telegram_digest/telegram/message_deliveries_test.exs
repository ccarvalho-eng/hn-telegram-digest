defmodule HnTelegramDigest.Telegram.MessageDeliveriesTest do
  use HnTelegramDigest.DataCase, async: false

  import Mox

  alias HnTelegramDigest.Telegram.MessageDeliveries
  alias HnTelegramDigest.Telegram.MessageDelivery
  alias HnTelegramDigest.TelegramClientMock

  setup :verify_on_exit!

  setup do
    delivery_agent = start_supervised!({Agent, fn -> [] end})

    telegram_config = [
      api_base_url: "https://api.telegram.org",
      bot_token: "123:abc",
      client: TelegramClientMock
    ]

    {:ok, delivery_agent: delivery_agent, telegram_config: telegram_config}
  end

  test "deliver_once sends and records a Telegram message once", %{
    delivery_agent: delivery_agent,
    telegram_config: telegram_config
  } do
    attrs = %{
      idempotency_key: "workflow/run-1/confirm_change",
      chat_id: 12_345,
      text: "You are subscribed to Hacker News digests."
    }

    expect(TelegramClientMock, :send_message, fn "123:abc", params, opts ->
      assert %{chat_id: 12_345, text: "You are subscribed to Hacker News digests."} = params
      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      Agent.update(delivery_agent, &[Map.take(params, [:chat_id, :text]) | &1])

      {:ok, %{"message_id" => 1}}
    end)

    assert {:ok, %{status: "sent", duplicate?: false}} =
             MessageDeliveries.deliver_once(attrs, telegram_config)

    assert {:ok, %{status: "sent", duplicate?: true}} =
             MessageDeliveries.deliver_once(attrs, telegram_config)

    assert [
             %{
               chat_id: 12_345,
               text: "You are subscribed to Hacker News digests."
             }
           ] = delivered_messages(delivery_agent)

    assert %MessageDelivery{
             idempotency_key: "workflow/run-1/confirm_change",
             chat_id: 12_345,
             text: "You are subscribed to Hacker News digests.",
             status: "sent",
             telegram_message_id: 1,
             last_error: nil,
             sent_at: %DateTime{}
           } = Repo.get_by!(MessageDelivery, idempotency_key: "workflow/run-1/confirm_change")
  end

  test "deliver_once records failures and retries them", %{
    delivery_agent: delivery_agent,
    telegram_config: telegram_config
  } do
    attrs = %{
      idempotency_key: "workflow/run-2/confirm_change",
      chat_id: 12_345,
      text: "You are subscribed to Hacker News digests."
    }

    Agent.update(delivery_agent, fn _messages -> :fail_once end)

    expect(TelegramClientMock, :send_message, 2, fn "123:abc", params, opts ->
      assert %{chat_id: 12_345, text: "You are subscribed to Hacker News digests."} = params
      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      Agent.get_and_update(delivery_agent, fn
        :fail_once ->
          {{:error, {:telegram_error, 429, %{"description" => "retry later"}}}, []}

        messages ->
          message = Map.take(params, [:chat_id, :text])
          {{:ok, %{"message_id" => 1}}, [message | messages]}
      end)
    end)

    assert {:error, {:telegram_error, 429, %{"description" => "retry later"}}} =
             MessageDeliveries.deliver_once(attrs, telegram_config)

    assert %MessageDelivery{
             status: "failed",
             last_error: %{"kind" => "telegram_error", "status" => 429}
           } = Repo.get_by!(MessageDelivery, idempotency_key: "workflow/run-2/confirm_change")

    assert {:ok, %{status: "sent", duplicate?: false}} =
             MessageDeliveries.deliver_once(attrs, telegram_config)

    assert [
             %{
               chat_id: 12_345,
               text: "You are subscribed to Hacker News digests."
             }
           ] = delivered_messages(delivery_agent)
  end

  test "deliver_once records configuration failures after claiming a delivery", %{
    telegram_config: telegram_config
  } do
    attrs = %{
      idempotency_key: "workflow/run-3/confirm_change",
      chat_id: 12_345,
      text: "You are subscribed to Hacker News digests."
    }

    telegram_config = Keyword.put(telegram_config, :bot_token, nil)

    assert {:error, :missing_telegram_bot_token} =
             MessageDeliveries.deliver_once(attrs, telegram_config)

    assert %MessageDelivery{
             status: "failed",
             processing_token: nil,
             processing_started_at: nil,
             last_error: %{"kind" => "missing_telegram_bot_token"}
           } = Repo.get_by!(MessageDelivery, idempotency_key: "workflow/run-3/confirm_change")
  end

  test "deliver_once does not resend stale in-flight deliveries", %{
    telegram_config: telegram_config
  } do
    attrs = %{
      idempotency_key: "workflow/run-4/confirm_change",
      chat_id: 12_345,
      text: "You are subscribed to Hacker News digests."
    }

    now = DateTime.utc_now(:microsecond)
    stale_started_at = DateTime.add(now, -10, :minute)

    Repo.insert_all(MessageDelivery, [
      %{
        idempotency_key: "workflow/run-4/confirm_change",
        chat_id: 12_345,
        text: "You are subscribed to Hacker News digests.",
        status: "sending",
        processing_token: Ecto.UUID.generate(),
        processing_started_at: stale_started_at,
        inserted_at: now,
        updated_at: now
      }
    ])

    assert {:error, :telegram_message_delivery_requires_inspection} =
             MessageDeliveries.deliver_once(attrs, telegram_config)

    assert %MessageDelivery{
             status: "unknown",
             processing_token: nil,
             processing_started_at: nil,
             last_error: %{"kind" => "stale_delivery_claim"}
           } = Repo.get_by!(MessageDelivery, idempotency_key: "workflow/run-4/confirm_change")
  end

  defp delivered_messages(delivery_agent) do
    Agent.get(delivery_agent, fn
      :fail_once -> []
      messages -> Enum.reverse(messages)
    end)
  end
end
