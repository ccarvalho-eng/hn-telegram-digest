defmodule HnTelegramDigest.Telegram.ClientTest do
  use ExUnit.Case, async: true

  alias HnTelegramDigest.Telegram.Client

  test "rejects non-canonical Telegram API base URLs before sending a request" do
    assert_raise ArgumentError, "Telegram API base URL must be https://api.telegram.org", fn ->
      Client.get_updates("123:abc", base_url: "https://api.telegram.org:8443")
    end
  end
end
