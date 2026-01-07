defmodule AiReality2Transnet.Action do
  # *******************************************************************************************************************************************
  @moduledoc """
  Rust NIF bindings for Transient Networking Bluetooth operations.

  This module provides Elixir bindings to a Rust crate that interfaces with the Linux
  Bluetooth stack (BlueZ) via `bluer`. All functions are asynchronous NIFs that send
  results back to the calling process.

  ## Modules
  - Adapter Discovery - List and manage Bluetooth adapters
  - Node Discovery - Scan and watch for Reality2 nodes
  - AltBeacon - Broadcast Reality2 beacons
  - GATT Server - Provide Sentant access via BLE
  - GATT Client - Connect to remote GATT devices

  ## Author
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  use Rustler, otp_app: :ai_reality2_transnet, crate: "aireality2transnet"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Adapter Discovery NIFs
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Lists Bluetooth adapters available on this device (asynchronous).

  ## Parameters
  - `pid` - The Elixir process that will receive the adapter list

  ## Events sent to `pid`
  - `{:adapters, adapters}` - List of available adapters

  ## Returns
  `:ok` immediately (async operation)
  """
  def list_adapters(_pid), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Lists Bluetooth adapters available on this device (synchronous).

  Returns the list of adapters directly. Use this when adapter enumeration
  must be serialized or when immediate results are needed.

  ## Returns
  List of adapter maps, or empty list if none found
  """
  def list_adapters_seq(), do: :erlang.nif_error(:nif_not_loaded)

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Node Discovery NIFs
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Performs a one-time scan for Reality2 nodes.

  ## Parameters
  - `pid` - The Elixir process that will receive scan results
  - `timeout` - Scan duration in milliseconds

  ## Events sent to `pid`
  - `{:r2nodes, nodes}` - List of discovered node IDs after timeout

  ## Returns
  `:ok` immediately (async operation)
  """
  def scan_nodes(_pid, _timeout), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Starts continuous watching for Reality2 nodes on a specified adapter.

  ## Parameters
  - `pid` - The Elixir process that will receive watch events
  - `company_id` - Manufacturer/company identifier (e.g., 0xFFFF)
  - `adapter_name` - Bluetooth adapter name (e.g., "hci0")
  - `lost_after_ms` - Consider a device "lost" after this many ms without detection

  ## Events sent to `pid`
  - `{:r2node_found, id, info}` - A Reality2 node was detected
  - `{:r2node_lost, id}` - A previously detected node is now out of range

  ## Returns
  - `{:ok, handle}` - Handle to use with `stop_watching/1`
  - `{:error, reason}` - Failed to start watching
  """
  def start_watching(_pid, _company_id, _adapter_name, _lost_after_ms),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Stops continuous watching for Reality2 nodes.

  ## Parameters
  - `handle` - The handle returned from `start_watching/4`

  ## Returns
  `:ok` on success
  """
  def stop_watching(_handle), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Resets the internal list of discovered devices.

  ## Parameters
  - `handle` - The watch handle from `start_watching/4`

  ## Returns
  `:ok` on success
  """
  def reset_nodes(_handle), do: :erlang.nif_error(:nif_not_loaded)

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # AltBeacon NIFs
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Starts broadcasting a Reality2 AltBeacon.

  ## Parameters
  - `company_id` - Manufacturer/company identifier (e.g., 0xFFFF)
  - `uuid_str` - Beacon UUID string (typically the node ID)
  - `major` - AltBeacon major value
  - `minor` - AltBeacon minor value
  - `rssi_at_1m` - Calibrated RSSI at 1 meter (typically -59)
  - `adapter_name` - Bluetooth adapter name (e.g., "hci0")

  ## Returns
  - `{:ok, handle}` - Handle to use with `stop_broadcast/1`
  - `{:error, reason}` - Failed to start broadcasting
  """
  def start_broadcast(_company_id, _uuid_str, _major, _minor, _rssi_at_1m, _adapter_name),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Stops broadcasting a Reality2 AltBeacon.

  ## Parameters
  - `handle` - The handle returned from `start_broadcast/6`

  ## Returns
  `:ok` on success
  """
  def stop_broadcast(_handle), do: :erlang.nif_error(:nif_not_loaded)

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GATT Server NIFs
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Starts a GATT server with pre-defined Sentant characteristics.

  The server exposes three characteristics:
  - Query (0x2A57) - Read to get all Sentants
  - Mutation (0x2A58) - Write to send events to Sentants
  - Subscription (0x2A59) - Subscribe to receive Sentant signals

  ## Parameters
  - `pid` - The Elixir process that will receive GATT events
  - `adapter_name` - Bluetooth adapter name (e.g., "hci0")

  ## Events sent to `pid`
  - `:gatt_server_started` - Server is ready and discoverable
  - `{:gatt_write, "command", data}` - Client wrote to query characteristic
  - `{:gatt_write, "data", data}` - Client wrote to mutation characteristic
  - `{:error, reason}` - Server error occurred

  ## Returns
  - `{:ok, handle}` - Handle to use with other GATT functions
  - `{:error, reason}` - Failed to start server
  """
  def start_gatt_server(_pid, _adapter_name), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Stops a running GATT server.

  ## Parameters
  - `handle` - The handle returned from `start_gatt_server/2`

  ## Returns
  `:ok` on success
  """
  def stop_gatt_server(_handle), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Sends a notification to all connected GATT clients via the subscription characteristic.

  ## Parameters
  - `handle` - The GATT server handle
  - `data` - Binary data or list of bytes to send

  ## Returns
  - `:ok` - Notification sent successfully
  - `:error` - Failed to send notification
  """
  def gatt_notify(_handle, _data), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Updates a characteristic value programmatically (server-side write).

  Used to update the query characteristic with current Sentant data.

  ## Parameters
  - `handle` - The GATT server handle
  - `char_uuid` - UUID string of the characteristic to update (e.g., "00002a57-0000-1000-8000-00805f9b34fb")
  - `data` - Binary data or list of bytes to write

  ## Returns
  - `:ok` - Characteristic updated successfully
  - `:error` - Failed to update characteristic
  """
  def gatt_write_characteristic(_handle, _char_uuid, _data),
    do: :erlang.nif_error(:nif_not_loaded)

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GATT Client NIFs
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Connects to a remote GATT device and discovers its services/characteristics.

  ## Parameters
  - `pid` - The Elixir process that will receive GATT events
  - `address` - Bluetooth MAC address (e.g., "AA:BB:CC:DD:EE:FF")
  - `adapter_name` - Bluetooth adapter name (e.g., "hci0")

  ## Events sent to `pid`
  - `:gatt_connected` - Successfully connected
  - `{:gatt_services_discovered, services}` - Discovered services and characteristics
  - `{:error, reason}` - Connection failed

  ## Returns
  `:ok` immediately (async operation)
  """
  def gatt_connect(_pid, _address, _adapter_name), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Reads a characteristic value from a remote GATT device.

  ## Parameters
  - `pid` - The Elixir process that will receive the result
  - `address` - Bluetooth MAC address of the remote device
  - `char_uuid` - UUID string of the characteristic to read
  - `adapter_name` - Bluetooth adapter name (e.g., "hci0")

  ## Events sent to `pid`
  - `{:gatt_read, value}` - Successfully read characteristic value (list of bytes)
  - `{:error, reason}` - Read failed

  ## Returns
  `:ok` immediately (async operation)
  """
  def gatt_read_characteristic(_pid, _address, _char_uuid, _adapter_name),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Writes data to a characteristic on a remote GATT device.

  ## Parameters
  - `pid` - The Elixir process that will receive the result
  - `address` - Bluetooth MAC address of the remote device
  - `char_uuid` - UUID string of the characteristic to write to
  - `data` - Binary data or list of bytes to write
  - `adapter_name` - Bluetooth adapter name (e.g., "hci0")

  ## Events sent to `pid`
  - `:gatt_write_success` - Write succeeded
  - `{:error, reason}` - Write failed

  ## Returns
  `:ok` immediately (async operation)
  """
  def gatt_write_to_device(_pid, _address, _char_uuid, _data, _adapter_name),
    do: :erlang.nif_error(:nif_not_loaded)
end
