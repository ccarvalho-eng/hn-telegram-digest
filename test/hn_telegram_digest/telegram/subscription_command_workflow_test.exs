defmodule HnTelegramDigest.Telegram.SubscriptionCommandWorkflowTest do
  use HnTelegramDigest.DataCase, async: false

  import Mox

  alias HnTelegramDigest.Telegram.Chat
  alias HnTelegramDigest.Telegram.CommandUpdateHandler
  alias HnTelegramDigest.Telegram.MessageDelivery
  alias HnTelegramDigest.Telegram.Subscription
  alias HnTelegramDigest.Telegram.Subscriptions
  alias HnTelegramDigest.TelegramClientMock
  alias HnTelegramDigest.Workflows.DeliverHnDigest
  alias HnTelegramDigest.Workflows.HandleSubscriptionCommand

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    telegram_config = Application.fetch_env!(:hn_telegram_digest, :telegram)
    delivery_agent = start_supervised!({Agent, fn -> [] end})

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

  test "/start launches a workflow that stores an active chat subscription", %{
    delivery_agent: delivery_agent
  } do
    update =
      telegram_update(701,
        text: "/start",
        chat: %{
          "id" => 12_345,
          "type" => "private",
          "username" => "hn_reader",
          "first_name" => "Hn",
          "last_name" => "Reader"
        }
      )

    expect(TelegramClientMock, :send_message, fn "123:abc", params, opts ->
      assert %{chat_id: 12_345, text: "You are subscribed to Hacker News digests."} = params
      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      Agent.update(delivery_agent, &[Map.take(params, [:chat_id, :text]) | &1])

      {:ok, %{"message_id" => 101}}
    end)

    assert :ok = CommandUpdateHandler.handle_update(update)

    assert {:ok, [run]} = SquidMesh.list_runs([workflow: HandleSubscriptionCommand], repo: Repo)

    assert %{subscription_command: %{"action" => "subscribe", "chat" => %{"id" => 12_345}}} =
             run.payload

    refute Map.has_key?(run.payload, :update)

    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :squid_mesh, with_recursion: true)

    assert %Chat{
             chat_id: 12_345,
             type: "private",
             username: "hn_reader",
             first_name: "Hn",
             last_name: "Reader"
           } = Repo.get!(Chat, 12_345)

    assert %Subscription{
             chat_id: 12_345,
             status: "active",
             subscribed_at: %DateTime{},
             unsubscribed_at: nil
           } = Repo.get_by!(Subscription, chat_id: 12_345)

    assert [
             %{
               chat_id: 12_345,
               text: "You are subscribed to Hacker News digests."
             }
           ] = delivered_messages(delivery_agent)
  end

  test "/stop launches a workflow that stores an inactive chat subscription", %{
    delivery_agent: delivery_agent
  } do
    assert {:ok, %{status: "active"}} =
             Subscriptions.apply_subscription_command(%{
               action: "subscribe",
               chat: %{
                 id: 98_765,
                 type: "private",
                 username: "past_reader"
               }
             })

    update =
      telegram_update(702,
        text: "/stop",
        chat: %{
          "id" => 98_765,
          "type" => "private",
          "username" => "past_reader"
        }
      )

    expect(TelegramClientMock, :send_message, fn "123:abc", params, opts ->
      assert %{chat_id: 98_765, text: "You are unsubscribed from Hacker News digests."} = params
      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      Agent.update(delivery_agent, &[Map.take(params, [:chat_id, :text]) | &1])

      {:ok, %{"message_id" => 102}}
    end)

    assert :ok = CommandUpdateHandler.handle_update(update)
    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :squid_mesh, with_recursion: true)

    assert %Subscription{
             chat_id: 98_765,
             status: "inactive",
             subscribed_at: %DateTime{},
             unsubscribed_at: %DateTime{}
           } = Repo.get_by!(Subscription, chat_id: 98_765)

    assert [
             %{
               chat_id: 98_765,
               text: "You are unsubscribed from Hacker News digests."
             }
           ] = delivered_messages(delivery_agent)
  end

  test "duplicate /start deliveries keep one active subscription" do
    update = telegram_update(704, text: "/start")

    expect(TelegramClientMock, :send_message, 2, fn "123:abc", params, opts ->
      assert %{chat_id: 12_345, text: "You are subscribed to Hacker News digests."} = params
      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      {:ok, %{"message_id" => System.unique_integer([:positive])}}
    end)

    assert :ok = CommandUpdateHandler.handle_update(update)
    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :squid_mesh, with_recursion: true)

    assert %Subscription{subscribed_at: subscribed_at} =
             Repo.get_by!(Subscription, chat_id: 12_345)

    assert :ok = CommandUpdateHandler.handle_update(update)
    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :squid_mesh, with_recursion: true)

    assert %DateTime{} = subscribed_at

    assert [
             %Subscription{
               chat_id: 12_345,
               status: "active",
               subscribed_at: ^subscribed_at,
               unsubscribed_at: nil
             }
           ] = Repo.all(Subscription)
  end

  test "/digest launches a digest workflow for an active subscription" do
    assert {:ok, %{status: "active"}} =
             Subscriptions.apply_subscription_command(%{
               action: "subscribe",
               chat: %{
                 id: 12_345,
                 type: "private"
               }
             })

    update = telegram_update(705, text: "/digest")

    assert :ok = CommandUpdateHandler.handle_update(update)

    assert {:ok, [run]} = SquidMesh.list_runs([workflow: DeliverHnDigest], repo: Repo)
    assert :digest_requested = run.trigger
    assert %{chat_id: 12_345, window_start_at: window_start_at} = run.payload
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(window_start_at)
  end

  test "/digest for an inactive chat sends a safe prompt without starting a digest", %{
    delivery_agent: delivery_agent
  } do
    update = telegram_update(706, text: "/digest")

    expect(TelegramClientMock, :send_message, fn "123:abc", params, opts ->
      assert %{
               chat_id: 12_345,
               text: "Subscribe with /start before requesting a Hacker News digest."
             } = params

      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      Agent.update(delivery_agent, &[Map.take(params, [:chat_id, :text]) | &1])

      {:ok, %{"message_id" => 106}}
    end)

    assert :ok = CommandUpdateHandler.handle_update(update)

    assert {:ok, []} = SquidMesh.list_runs([workflow: DeliverHnDigest], repo: Repo)

    assert %MessageDelivery{
             idempotency_key: "telegram_update/706/digest_inactive_subscription",
             status: "sent"
           } =
             Repo.get_by!(MessageDelivery,
               idempotency_key: "telegram_update/706/digest_inactive_subscription"
             )

    assert [
             %{
               chat_id: 12_345,
               text: "Subscribe with /start before requesting a Hacker News digest."
             }
           ] = delivered_messages(delivery_agent)
  end

  test "unsupported slash commands send a deterministic response without starting workflow work",
       %{
         delivery_agent: delivery_agent
       } do
    update = telegram_update(707, text: "/startnow")

    expect(TelegramClientMock, :send_message, fn "123:abc", params, opts ->
      assert %{
               chat_id: 12_345,
               text:
                 "That command is not supported yet. Available commands: /start, /stop, /digest."
             } = params

      assert "https://api.telegram.org" = Keyword.fetch!(opts, :base_url)

      Agent.update(delivery_agent, &[Map.take(params, [:chat_id, :text]) | &1])

      {:ok, %{"message_id" => 107}}
    end)

    assert :ok = CommandUpdateHandler.handle_update(update)
    assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :squid_mesh)
    assert [] = Repo.all(Chat)
    assert [] = Repo.all(Subscription)

    assert %MessageDelivery{
             idempotency_key: "telegram_update/707/unsupported_command",
             status: "sent"
           } =
             Repo.get_by!(MessageDelivery,
               idempotency_key: "telegram_update/707/unsupported_command"
             )

    assert [
             %{
               chat_id: 12_345,
               text:
                 "That command is not supported yet. Available commands: /start, /stop, /digest."
             }
           ] = delivered_messages(delivery_agent)
  end

  test "non-command messages do not start workflow work" do
    update = telegram_update(703, text: "hello")

    assert :ok = CommandUpdateHandler.handle_update(update)
    assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :squid_mesh)
    assert [] = Repo.all(Chat)
    assert [] = Repo.all(Subscription)
  end

  defp telegram_update(update_id, opts) do
    chat =
      Keyword.get(opts, :chat, %{
        "id" => 12_345,
        "type" => "private"
      })

    %{
      "update_id" => update_id,
      "message" => %{
        "message_id" => update_id + 1,
        "text" => Keyword.fetch!(opts, :text),
        "chat" => chat
      }
    }
  end

  defp delivered_messages(delivery_agent) do
    Agent.get(delivery_agent, &Enum.reverse/1)
  end
end
