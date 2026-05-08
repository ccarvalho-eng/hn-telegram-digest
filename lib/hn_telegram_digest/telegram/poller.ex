defmodule HnTelegramDigest.Telegram.Poller do
  @moduledoc false

  use GenServer

  require Logger

  alias HnTelegramDigest.Telegram.Client
  alias HnTelegramDigest.Telegram.UpdateStore

  @type state :: %{
          api_base_url: String.t(),
          bot_token: String.t(),
          client: module(),
          repo: module(),
          update_handler: module(),
          timeout_seconds: pos_integer(),
          limit: pos_integer(),
          allowed_updates: [String.t()],
          processing_timeout_ms: pos_integer(),
          error_backoff_ms: pos_integer()
        }

  def start_link(config) when is_list(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    state = build_state(config)
    send(self(), :poll)

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    request_opts = [
      base_url: state.api_base_url,
      offset: UpdateStore.next_offset(state.repo),
      limit: state.limit,
      timeout: state.timeout_seconds,
      allowed_updates: state.allowed_updates
    ]

    case state.client.get_updates(state.bot_token, request_opts) do
      {:ok, updates} ->
        {:ok, _inserted_count} = UpdateStore.insert_new_updates(state.repo, updates)
        handle_received_updates(state)
        schedule_poll(0)

        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Telegram polling failed: #{inspect(redact_reason(reason))}")
        schedule_poll(backoff_ms(reason, state.error_backoff_ms))

        {:noreply, state}
    end
  end

  defp build_state(config) do
    polling_config = Keyword.fetch!(config, :polling)

    %{
      api_base_url: Keyword.fetch!(config, :api_base_url),
      bot_token: fetch_bot_token!(config),
      client: Keyword.get(config, :client, Client),
      repo: Keyword.get(config, :repo, HnTelegramDigest.Repo),
      update_handler: Keyword.fetch!(config, :update_handler),
      timeout_seconds: Keyword.fetch!(polling_config, :timeout_seconds),
      limit: Keyword.fetch!(polling_config, :limit),
      allowed_updates: Keyword.fetch!(polling_config, :allowed_updates),
      processing_timeout_ms: Keyword.fetch!(polling_config, :processing_timeout_ms),
      error_backoff_ms: Keyword.fetch!(polling_config, :error_backoff_ms)
    }
  end

  defp fetch_bot_token!(config) do
    case Keyword.fetch!(config, :bot_token) do
      token when is_binary(token) and token != "" ->
        token

      _token ->
        raise ArgumentError, "Telegram polling requires TELEGRAM_BOT_TOKEN"
    end
  end

  defp handle_received_updates(state) do
    {_count, _updates} =
      UpdateStore.requeue_stale_processing(state.repo, state.processing_timeout_ms)

    {:ok, updates} = UpdateStore.claim_received(state.repo)

    Enum.each(updates, fn update ->
      handle_received_update(state, update)
    end)
  end

  defp handle_received_update(state, update) do
    case safe_handle_update(state.update_handler, update.payload) do
      :ok ->
        record_transition(
          UpdateStore.mark_handled(state.repo, update.update_id, update.processing_token)
        )

      {:error, reason} ->
        Logger.warning("Telegram update handler failed: #{inspect(redact_reason(reason))}")

        record_transition(
          UpdateStore.mark_failed(state.repo, update.update_id, update.processing_token, reason)
        )
    end
  end

  defp record_transition(:ok), do: :ok

  defp record_transition({:error, :stale_claim}) do
    Logger.warning("Telegram update claim expired before terminal transition")
    :ok
  end

  defp safe_handle_update(update_handler, update) do
    case update_handler.handle_update(update) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_handler_result}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp schedule_poll(delay_ms) do
    Process.send_after(self(), :poll, delay_ms)
  end

  defp backoff_ms(
         {:telegram_error, _status, %{"parameters" => %{"retry_after" => seconds}}},
         _default_ms
       )
       when is_integer(seconds) and seconds > 0 do
    :timer.seconds(seconds)
  end

  defp backoff_ms(_reason, default_ms), do: default_ms

  defp redact_reason(reason) when is_atom(reason), do: reason
  defp redact_reason({reason, _details}) when is_atom(reason), do: reason
  defp redact_reason(%{__exception__: true} = exception), do: exception.__struct__
  defp redact_reason(_reason), do: :handler_error
end
