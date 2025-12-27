defmodule AiReality2Rustdemo.Action do
  use Rustler, otp_app: :ai_reality2_rustdemo, crate: "aireality2rustdemo"

  # When the NIF is loaded, it will override these functions.
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def subtract(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
