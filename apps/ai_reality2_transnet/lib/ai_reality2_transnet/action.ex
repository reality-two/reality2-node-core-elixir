defmodule AiReality2Transnet.Action do
  use Rustler,
    otp_app: :ai_reality2_transnet,
    crate: "aireality2transnet"

  def list_adapters(), do: :erlang.nif_error(:nif_not_loaded)

  def scan_devices(_pid, _timeout), do: :erlang.nif_error(:nif_not_loaded)

  def start_r2_watch(_pid, _company_id, _adapter_name, _lost_after_ms),
    do: :erlang.nif_error(:nif_not_loaded)

  def stop_r2_watch(_handle),
    do: :erlang.nif_error(:nif_not_loaded)

  def start_altbeacon(_company_id, _uuid_str, _major, _minor, _rssi_at_1m, _adapter_name \\ nil),
    do: :erlang.nif_error(:nif_not_loaded)

  def stop_altbeacon(_handle),
    do: :erlang.nif_error(:nif_not_loaded)
end
