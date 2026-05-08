defmodule HnTelegramDigest.Telegram.MessageDeliveries do
  @moduledoc """
  Coordinates durable, idempotent Telegram message delivery.

  This context owns persistence and retry semantics for outbound Telegram
  messages. It stores the intended message before making the HTTP request,
  claims a pending or failed row, sends through the configured Telegram client,
  and records either a sent marker or a structured failure. Stale in-flight
  sends are marked `unknown` for inspection because their external outcome is
  ambiguous after a crash or restart.
  """

  import Ecto.Query

  alias HnTelegramDigest.Repo
  alias HnTelegramDigest.Telegram.Client
  alias HnTelegramDigest.Telegram.MessageDelivery

  @type delivery_attrs :: %{
          required(:idempotency_key) => String.t(),
          required(:chat_id) => integer(),
          required(:text) => String.t()
        }

  @type telegram_config :: keyword()

  @type delivery_result :: %{
          required(:status) => String.t(),
          required(:duplicate?) => boolean(),
          optional(:telegram_message_id) => integer() | nil
        }

  @doc """
  Sends a Telegram message at most once for the supplied idempotency key.

    A successful duplicate call returns `duplicate?: true` without calling the
    Telegram API again. A failed send leaves a failed row that can be claimed and
    retried by a later call. A stale in-flight send is not retried automatically
    because the Telegram side effect may already have happened.
  """
  @spec deliver_once(delivery_attrs() | map(), telegram_config(), module()) ::
          {:ok, delivery_result()} | {:error, term()}
  def deliver_once(attrs, telegram_config, repo \\ Repo)
      when is_map(attrs) and is_list(telegram_config) do
    with {:ok, normalized_attrs} <- normalize_attrs(attrs),
         :ok <- requeue_stale_sending(repo, delivery_timeout_ms(telegram_config)),
         {:ok, delivery} <- ensure_delivery(repo, normalized_attrs),
         {:ok, claim_result} <- claim_delivery(repo, delivery.idempotency_key) do
      deliver_claim(repo, claim_result, telegram_config)
    end
  end

  defp deliver_claim(repo, {:claimed, %MessageDelivery{} = delivery}, telegram_config) do
    with {:ok, token} <- require_processing_token(delivery.processing_token),
         {:ok, result} <- send_message(delivery, telegram_config) do
      mark_sent(repo, delivery, token, result)
    else
      {:error, reason} ->
        fail_claim(repo, delivery, reason)
    end
  end

  defp deliver_claim(_repo, {:already_sent, %MessageDelivery{} = delivery}, _telegram_config) do
    {:ok, duplicate_result(delivery)}
  end

  defp fail_claim(repo, %MessageDelivery{} = delivery, reason) do
    with {:ok, token} <- require_processing_token(delivery.processing_token) do
      _transition_result = mark_failed(repo, delivery, token, reason)
      {:error, reason}
    end
  end

  defp normalize_attrs(attrs) do
    with {:ok, idempotency_key} <- fetch_non_empty_binary(attrs, :idempotency_key),
         {:ok, chat_id} <- fetch_integer(attrs, :chat_id),
         {:ok, text} <- fetch_non_empty_binary(attrs, :text) do
      {:ok, %{idempotency_key: idempotency_key, chat_id: chat_id, text: text}}
    end
  end

  defp ensure_delivery(repo, attrs) do
    now = DateTime.utc_now(:microsecond)

    row =
      attrs
      |> Map.put(:status, "pending")
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    {_count, _rows} =
      repo.insert_all(MessageDelivery, [row],
        on_conflict: :nothing,
        conflict_target: [:idempotency_key],
        returning: false
      )

    case repo.get_by(MessageDelivery, idempotency_key: attrs.idempotency_key) do
      %MessageDelivery{} = delivery -> verify_delivery_matches(delivery, attrs)
      nil -> {:error, :telegram_message_delivery_not_found}
    end
  end

  defp verify_delivery_matches(%MessageDelivery{} = delivery, attrs) do
    if delivery.chat_id == attrs.chat_id and delivery.text == attrs.text do
      {:ok, delivery}
    else
      {:error, :telegram_message_delivery_idempotency_conflict}
    end
  end

  defp requeue_stale_sending(repo, timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    now = DateTime.utc_now(:microsecond)
    stale_before = DateTime.add(now, -timeout_ms, :millisecond)

    MessageDelivery
    |> where([delivery], delivery.status == "sending")
    |> where([delivery], delivery.processing_started_at < ^stale_before)
    |> repo.update_all(
      set: [
        status: "unknown",
        last_error: %{"kind" => "stale_delivery_claim"},
        processing_token: nil,
        processing_started_at: nil,
        updated_at: now
      ]
    )

    :ok
  end

  defp claim_delivery(repo, idempotency_key) do
    now = DateTime.utc_now(:microsecond)
    processing_token = Ecto.UUID.generate()

    count =
      MessageDelivery
      |> where([delivery], delivery.idempotency_key == ^idempotency_key)
      |> where([delivery], delivery.status in ["pending", "failed"])
      |> repo.update_all(
        set: [
          status: "sending",
          processing_token: processing_token,
          processing_started_at: now,
          updated_at: now
        ]
      )
      |> elem(0)

    case count do
      1 -> {:ok, {:claimed, repo.get_by!(MessageDelivery, idempotency_key: idempotency_key)}}
      0 -> claim_status(repo, idempotency_key)
    end
  end

  defp claim_status(repo, idempotency_key) do
    case delivery_status(repo, idempotency_key) do
      {:already_sent, %MessageDelivery{} = delivery} -> {:ok, {:already_sent, delivery}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delivery_status(repo, idempotency_key) do
    case repo.get_by(MessageDelivery, idempotency_key: idempotency_key) do
      %MessageDelivery{status: "sent"} = delivery ->
        {:already_sent, delivery}

      %MessageDelivery{status: "sending"} ->
        {:error, :telegram_message_delivery_in_progress}

      %MessageDelivery{status: "unknown"} ->
        {:error, :telegram_message_delivery_requires_inspection}

      %MessageDelivery{status: status} ->
        {:error, {:unexpected_telegram_message_delivery_status, status}}

      nil ->
        {:error, :telegram_message_delivery_not_found}
    end
  end

  defp send_message(%MessageDelivery{} = delivery, telegram_config) do
    with {:ok, token} <- fetch_bot_token(telegram_config),
         {:ok, opts} <- client_opts(telegram_config) do
      client = Keyword.get(telegram_config, :client, Client)

      safe_send_message(client, token, %{chat_id: delivery.chat_id, text: delivery.text}, opts)
    end
  end

  defp safe_send_message(client, token, params, opts) do
    client.send_message(token, params, opts)
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp mark_sent(repo, %MessageDelivery{} = delivery, processing_token, result) do
    now = DateTime.utc_now(:microsecond)
    telegram_message_id = message_id(result)

    count =
      MessageDelivery
      |> where([message_delivery], message_delivery.idempotency_key == ^delivery.idempotency_key)
      |> where([message_delivery], message_delivery.status == "sending")
      |> where([message_delivery], message_delivery.processing_token == ^processing_token)
      |> repo.update_all(
        set: [
          status: "sent",
          telegram_message_id: telegram_message_id,
          last_error: nil,
          processing_token: nil,
          processing_started_at: nil,
          sent_at: now,
          updated_at: now
        ]
      )
      |> elem(0)

    case count do
      1 ->
        {:ok, sent_result(telegram_message_id)}

      0 ->
        {:error, :stale_telegram_message_delivery_claim}
    end
  end

  defp mark_failed(repo, %MessageDelivery{} = delivery, processing_token, reason) do
    now = DateTime.utc_now(:microsecond)

    count =
      MessageDelivery
      |> where([message_delivery], message_delivery.idempotency_key == ^delivery.idempotency_key)
      |> where([message_delivery], message_delivery.status == "sending")
      |> where([message_delivery], message_delivery.processing_token == ^processing_token)
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

    case count do
      1 -> :ok
      0 -> {:error, :stale_telegram_message_delivery_claim}
    end
  end

  defp fetch_bot_token(telegram_config) do
    case Keyword.get(telegram_config, :bot_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _token -> {:error, :missing_telegram_bot_token}
    end
  end

  defp client_opts(telegram_config) do
    case Keyword.get(telegram_config, :api_base_url) do
      base_url when is_binary(base_url) and base_url != "" ->
        {:ok, Keyword.put(telegram_config, :base_url, base_url)}

      _base_url ->
        {:error, :missing_telegram_api_base_url}
    end
  end

  defp delivery_timeout_ms(telegram_config) do
    case Keyword.get(telegram_config, :delivery_timeout_ms, :timer.minutes(5)) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> timeout_ms
      _timeout_ms -> :timer.minutes(5)
    end
  end

  defp require_processing_token(token) when is_binary(token) and token != "" do
    {:ok, token}
  end

  defp require_processing_token(_token), do: {:error, :missing_telegram_message_delivery_claim}

  defp message_id(result) do
    case Map.get(result, "message_id") || Map.get(result, :message_id) do
      value when is_integer(value) -> value
      _value -> nil
    end
  end

  defp sent_result(telegram_message_id) do
    %{
      status: "sent",
      duplicate?: false,
      telegram_message_id: telegram_message_id
    }
  end

  defp duplicate_result(%MessageDelivery{} = delivery) do
    %{
      status: delivery.status,
      duplicate?: true,
      telegram_message_id: delivery.telegram_message_id
    }
  end

  defp reason_to_error({:telegram_error, status, details}) when is_integer(status) do
    %{
      "kind" => "telegram_error",
      "status" => status,
      "details" => details
    }
  end

  defp reason_to_error({reason, _details}) when is_atom(reason) do
    %{"kind" => Atom.to_string(reason)}
  end

  defp reason_to_error(reason) when is_atom(reason) do
    %{"kind" => Atom.to_string(reason)}
  end

  defp reason_to_error(%{__exception__: true} = exception) do
    %{"kind" => exception.__struct__ |> Module.split() |> Enum.join(".")}
  end

  defp reason_to_error(_reason), do: %{"kind" => "telegram_message_delivery_error"}

  defp fetch_non_empty_binary(map, key) do
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

  defp value(map, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.fetch!(map, key)
      Map.has_key?(map, string_key) -> Map.fetch!(map, string_key)
      true -> nil
    end
  end
end
