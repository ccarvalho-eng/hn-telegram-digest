defmodule HnTelegramDigest.Telegram.SubscriptionCommand do
  @moduledoc false

  @type t :: %{
          required(:action) => String.t(),
          required(:chat) => map(),
          required(:text) => String.t()
        }

  @spec from_update(map()) :: {:ok, t()} | :ignore | {:error, atom()}
  def from_update(update) when is_map(update) do
    with {:ok, message} <- fetch_map(update, :message),
         {:ok, text} <- fetch_binary(message, :text),
         {:ok, action} <- command_action(text),
         {:ok, chat} <- fetch_map(message, :chat),
         {:ok, normalized_chat} <- normalize_chat(chat) do
      {:ok, %{action: action, chat: normalized_chat, text: text}}
    else
      :ignore -> :ignore
      {:error, reason} -> {:error, reason}
    end
  end

  defp command_action(text) do
    text
    |> String.trim()
    |> String.split()
    |> List.first()
    |> case do
      nil -> :ignore
      "" -> :ignore
      command -> normalize_command(command)
    end
  end

  defp normalize_command("/start" <> suffix) do
    if command_suffix?(suffix), do: {:ok, "subscribe"}, else: :ignore
  end

  defp normalize_command("/stop" <> suffix) do
    if command_suffix?(suffix), do: {:ok, "unsubscribe"}, else: :ignore
  end

  defp normalize_command(_command), do: :ignore

  defp command_suffix?(""), do: true
  defp command_suffix?("@" <> bot_name), do: bot_name != ""
  defp command_suffix?(_suffix), do: false

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
         payload: chat_payload(chat)
       }}
    end
  end

  defp chat_payload(chat) do
    %{
      id: value(chat, :id),
      type: value(chat, :type),
      username: optional_binary(chat, :username),
      first_name: optional_binary(chat, :first_name),
      last_name: optional_binary(chat, :last_name),
      title: optional_binary(chat, :title)
    }
  end

  defp fetch_map(map, key) do
    case value(map, key) do
      value when is_map(value) -> {:ok, value}
      _value -> {:error, :"missing_#{key}"}
    end
  end

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
