defmodule AiReality2RustdemoTest do
  use ExUnit.Case
  doctest AiReality2Rustdemo

  test "greets the world" do
    assert AiReality2Rustdemo.hello() == :world
  end
end
