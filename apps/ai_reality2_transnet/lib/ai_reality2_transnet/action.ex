defmodule AiReality2Transnet.Action do
  use Rustler, otp_app: :ai_reality2_transnet, crate: "aireality2transnet"

  # When the NIF is loaded, it will override these functions.
  def list_adapters(), do: :erlang.nif_error(:nif_not_loaded)
  def scan_devices(_pid, _timeout), do: :erlang.nif_error(:nif_not_loaded)
end
