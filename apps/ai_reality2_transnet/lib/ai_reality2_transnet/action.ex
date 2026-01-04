defmodule AiReality2Transnet.Action do
  # *******************************************************************************************************************************************
  @moduledoc """
  Actions for Transient Networking

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # We are using the bluer library in Rust, which we communicate with via Rustler NIFs.  This depends on bluez being installed in the OS,
  # but that is fairly common.  Alternatives are to use BlueHeron in Elixir, but it is still quite raw.  Or dbus.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  use Rustler,
    otp_app: :ai_reality2_transnet,
    crate: "aireality2transnet"

  # List the adapters this device has.  We assume hci0 in general.  TODO: allow other adapters through an environment variable
  def list_adapters(), do: :erlang.nif_error(:nif_not_loaded)

  # Scan for Reality2 nodes but timeout after a specified duration
  def scan_devices(_pid, _timeout), do: :erlang.nif_error(:nif_not_loaded)

  # Start watching for Reality2 nodes on a specified adapter
  def start_r2_watch(_pid, _company_id, _adapter_name, _lost_after_ms),
    do: :erlang.nif_error(:nif_not_loaded)

  # Stop watching for Reality2 nodes on a specified adapter
  def stop_r2_watch(_handle),
    do: :erlang.nif_error(:nif_not_loaded)

  # Start the Reality2 AltBEacon
  def start_altbeacon(_company_id, _uuid_str, _major, _minor, _rssi_at_1m, _adapter_name \\ nil),
    do: :erlang.nif_error(:nif_not_loaded)

  # Stop the Reality2 AltBEacon
  def stop_altbeacon(_handle),
    do: :erlang.nif_error(:nif_not_loaded)
end
