defmodule HnTelegramDigest.Telegram.Client do
  @moduledoc false

  @callback get_updates(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}

  @behaviour __MODULE__

  @impl true
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
    |> parse_response()
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

  defp parse_response(
         {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => updates}}}
       )
       when is_list(updates) do
    {:ok, updates}
  end

  defp parse_response({:ok, %Req.Response{status: status, body: %{"ok" => false} = body}}) do
    {:error,
     {:telegram_error, status, Map.take(body, ["error_code", "description", "parameters"])}}
  end

  defp parse_response({:ok, %Req.Response{status: status}}) do
    {:error, {:unexpected_status, status}}
  end

  defp parse_response({:error, reason}), do: {:error, reason}
end
