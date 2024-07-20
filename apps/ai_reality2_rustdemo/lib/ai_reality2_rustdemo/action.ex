defmodule AiReality2Rustdemo.Action do
  use Rustler, otp_app: :ai_reality2_rustdemo, crate: "aireality2rustdemo"

  # When your NIF is loaded, it will override this function.
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def subtract(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
