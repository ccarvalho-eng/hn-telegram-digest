defmodule HnTelegramDigest.Telegram.Command do
  @moduledoc false

  @type t :: %{
          required(:action) => String.t(),
          required(:chat) => map(),
          required(:text) => String.t(),
          required(:update_id) => integer(),
          optional(:command) => String.t()
        }

  @spec from_update(map()) :: {:ok, t()} | :ignore | {:error, atom()}
  def from_update(update) when is_map(update) do
    with {:ok, update_id} <- fetch_integer(update, :update_id),
         {:ok, message} <- fetch_map(update, :message),
         {:ok, text} <- fetch_binary(message, :text),
         {:ok, command} <- command_action(text),
         {:ok, chat} <- fetch_map(message, :chat),
         {:ok, normalized_chat} <- normalize_chat(chat) do
      {:ok,
       %{
         action: command.action,
         command: command.name,
         chat: normalized_chat,
         text: text,
         update_id: update_id
       }}
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

  defp normalize_command("/" <> _command = command) do
    with :ok <- validate_command_suffix(command) do
      case command_name(command) do
        "/start" -> {:ok, %{action: "subscribe", name: "/start"}}
        "/stop" -> {:ok, %{action: "unsubscribe", name: "/stop"}}
        "/digest" -> {:ok, %{action: "digest", name: "/digest"}}
        name -> {:ok, %{action: "unsupported", name: name}}
      end
    end
  end

  defp normalize_command(_command), do: :ignore

  defp validate_command_suffix(command) do
    case String.split(command, "@", parts: 2) do
      [_name] -> :ok
      [_name, bot_name] when bot_name != "" -> :ok
      [_name, _bot_name] -> :ignore
    end
  end

  defp command_name(command) do
    command
    |> String.split("@", parts: 2)
    |> List.first()
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
