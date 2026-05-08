defmodule HnTelegramDigestTest do
  use ExUnit.Case
  doctest HnTelegramDigest

  test "greets the world" do
    assert HnTelegramDigest.hello() == :world
  end
end
