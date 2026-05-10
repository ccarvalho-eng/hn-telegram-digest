defmodule HnTelegramDigest.Telegram.Subscriptions do
  @moduledoc """
  Coordinates Telegram chat subscription persistence and reads.
  """

  import Ecto.Query

  alias HnTelegramDigest.Repo
  alias HnTelegramDigest.Telegram.Chat
  alias HnTelegramDigest.Telegram.Subscription

  @type subscription_result :: %{
          required(:chat_id) => integer(),
          required(:status) => String.t(),
          required(:action) => String.t(),
          required(:confirmation_text) => String.t()
        }

  @spec apply_subscription_command(map(), module()) ::
          {:ok, subscription_result()} | {:error, term()}
  def apply_subscription_command(command, repo \\ Repo) when is_map(command) do
    with {:ok, action} <- fetch_action(command),
         {:ok, chat} <- fetch_chat(command) do
      now = DateTime.utc_now(:microsecond)

      repo.transaction(fn ->
        :ok = upsert_chat(repo, chat, now)
        :ok = upsert_subscription(repo, action, chat.id, now)

        %Subscription{} = subscription = repo.get_by!(Subscription, chat_id: chat.id)

        %{
          chat_id: subscription.chat_id,
          status: subscription.status,
          action: action,
          confirmation_text: confirmation_text(subscription.status)
        }
      end)
    end
  end

  @doc """
  Lists Telegram chat ids with active subscriptions.
  """
  @spec list_active_chat_ids(module()) :: [integer()]
  def list_active_chat_ids(repo \\ Repo) do
    Subscription
    |> where([subscription], subscription.status == "active")
    |> order_by([subscription], asc: subscription.chat_id)
    |> select([subscription], subscription.chat_id)
    |> repo.all()
  end

  defp fetch_action(command) do
    case value(command, :action) do
      action when action in ["subscribe", "unsubscribe"] -> {:ok, action}
      _other -> {:error, :unsupported_subscription_action}
    end
  end

  defp fetch_chat(command) do
    case value(command, :chat) do
      chat when is_map(chat) -> normalize_chat(chat)
      _other -> {:error, :missing_chat}
    end
  end

  defp normalize_chat(chat) do
    with {:ok, chat_id} <- fetch_integer(chat, :id),
         {:ok, type} <- fetch_binary(chat, :type) do
      {:ok,
       %{
         id: chat_id,
         type: type,
         username: optional_binary(chat, :username),
         first_name: optional_binary(chat, :first_name),
         last_name: optional_binary(chat, :last_name),
         title: optional_binary(chat, :title),
         payload: value(chat, :payload) || chat
       }}
    end
  end

  defp upsert_chat(repo, chat, now) do
    row = %{
      chat_id: chat.id,
      type: chat.type,
      username: chat.username,
      first_name: chat.first_name,
      last_name: chat.last_name,
      title: chat.title,
      payload: chat.payload,
      inserted_at: now,
      updated_at: now
    }

    {_count, _rows} =
      repo.insert_all(Chat, [row],
        on_conflict:
          {:replace, [:type, :username, :first_name, :last_name, :title, :payload, :updated_at]},
        conflict_target: [:chat_id],
        returning: false
      )

    :ok
  end

  defp upsert_subscription(repo, "subscribe", chat_id, now) do
    row = %{
      chat_id: chat_id,
      status: "active",
      subscribed_at: now,
      unsubscribed_at: nil,
      inserted_at: now,
      updated_at: now
    }

    {_count, _rows} =
      repo.insert_all(Subscription, [row],
        on_conflict: [
          set: [
            status: "active",
            unsubscribed_at: nil,
            updated_at: now
          ]
        ],
        conflict_target: [:chat_id],
        returning: false
      )

    :ok
  end

  defp upsert_subscription(repo, "unsubscribe", chat_id, now) do
    upsert_subscription_status(repo, chat_id, "inactive", now, unsubscribed_at: now)
  end

  defp upsert_subscription_status(repo, chat_id, status, now, attrs) do
    row = %{
      chat_id: chat_id,
      status: status,
      subscribed_at: Keyword.get(attrs, :subscribed_at),
      unsubscribed_at: Keyword.get(attrs, :unsubscribed_at),
      inserted_at: now,
      updated_at: now
    }

    conflict_updates =
      attrs
      |> Keyword.put(:status, status)
      |> Keyword.put(:updated_at, now)

    {_count, _rows} =
      repo.insert_all(Subscription, [row],
        on_conflict: [set: conflict_updates],
        conflict_target: [:chat_id],
        returning: false
      )

    :ok
  end

  defp confirmation_text("active"), do: "You are subscribed to Hacker News digests."
  defp confirmation_text("inactive"), do: "You are unsubscribed from Hacker News digests."

  defp fetch_binary(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp fetch_integer(map, key) do
    case value(map, key) do
      value when is_integer(value) -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

  defp optional_binary(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      _value -> nil
    end
  end

  defp value(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
