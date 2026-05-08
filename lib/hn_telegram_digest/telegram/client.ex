defmodule HnTelegramDigest.Telegram.Client do
  @moduledoc """
  Small boundary around the Telegram Bot HTTP API.

  The client accepts the bot token as an argument so callers can keep secrets at
  the application boundary. Returned errors are structured and do not include
  the token or request URL.
  """

  @callback get_updates(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback send_message(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

  @impl __MODULE__
  def get_updates(token, opts \\ []) when is_binary(token) do
    base_url = Keyword.fetch!(opts, :base_url)
    :ok = validate_base_url(base_url)

    params =
      opts
      |> Keyword.take([:offset, :limit, :timeout, :allowed_updates])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    receive_timeout = Keyword.get(opts, :receive_timeout, receive_timeout(params))

    token
    |> endpoint(base_url, "getUpdates")
    |> Req.post(json: params, receive_timeout: receive_timeout)
    |> parse_updates_response()
  end

  @impl __MODULE__
  def send_message(token, params, opts) when is_binary(token) and is_map(params) do
    with {:ok, message_params} <- build_message_params(params) do
      base_url = Keyword.fetch!(opts, :base_url)
      :ok = validate_base_url(base_url)

      receive_timeout = Keyword.get(opts, :receive_timeout, :timer.seconds(10))

      token
      |> endpoint(base_url, "sendMessage")
      |> Req.post(json: message_params, receive_timeout: receive_timeout)
      |> parse_message_response()
    end
  end

  defp validate_base_url(base_url) do
    uri = URI.parse(base_url)

    if uri.scheme == "https" and uri.host == "api.telegram.org" and uri.port in [nil, 443] and
         uri.path in [nil, ""] and is_nil(uri.query) and is_nil(uri.fragment) and
         is_nil(uri.userinfo) do
      :ok
    else
      raise ArgumentError, "Telegram API base URL must be https://api.telegram.org"
    end
  end

  defp endpoint(token, base_url, method) do
    "#{String.trim_trailing(base_url, "/")}/bot#{token}/#{method}"
  end

  defp receive_timeout(%{timeout: timeout}) when is_integer(timeout) and timeout > 0 do
    :timer.seconds(timeout + 5)
  end

  defp receive_timeout(_params), do: :timer.seconds(10)

  defp build_message_params(params) do
    with {:ok, chat_id} <- fetch_param(params, :chat_id),
         {:ok, text} <- fetch_param(params, :text) do
      message_params =
        params
        |> take_params([:parse_mode, :disable_notification, :reply_markup])
        |> Map.put(:chat_id, chat_id)
        |> Map.put(:text, text)

      {:ok, message_params}
    end
  end

  defp fetch_param(params, key) do
    case value(params, key) do
      value when not is_nil(value) -> {:ok, value}
      _value -> {:error, {:missing_telegram_message_param, key}}
    end
  end

  defp take_params(params, keys) do
    keys
    |> Enum.reduce(%{}, fn key, acc ->
      case value(params, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp value(map, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.fetch!(map, key)
      Map.has_key?(map, string_key) -> Map.fetch!(map, string_key)
      true -> nil
    end
  end

  defp parse_updates_response(
         {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => updates}}}
       )
       when is_list(updates) do
    {:ok, updates}
  end

  defp parse_updates_response(response), do: parse_error_response(response)

  defp parse_message_response(
         {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => message}}}
       )
       when is_map(message) do
    {:ok, message}
  end

  defp parse_message_response(response), do: parse_error_response(response)

  defp parse_error_response({:ok, %Req.Response{status: status, body: %{"ok" => false} = body}}) do
    {:error,
     {:telegram_error, status, Map.take(body, ["error_code", "description", "parameters"])}}
  end

  defp parse_error_response({:ok, %Req.Response{status: status}}) do
    {:error, {:unexpected_status, status}}
  end

  defp parse_error_response({:error, reason}), do: {:error, reason}
end
