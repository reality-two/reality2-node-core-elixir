defmodule ComRaspberrypiApiTest do
  use ExUnit.Case
  doctest ComRaspberrypiApi

  test "greets the world" do
    assert ComRaspberrypiApi.hello() == :world
  end
end
