/// Information about a Bluetooth adapter.
#[derive(rustler::NifMap)]
pub struct Adapters {
    /// Adapter identifier (e.g., "hci0").
    pub name: String,
    /// Bluetooth MAC address of the adapter.
    pub address: String,
}

/// Information about a discovered BLE device.
#[derive(rustler::NifMap)]
pub struct Device {
    /// Device name (or default if not advertised).
    pub name: String,
    /// Device identifier (node UUID for AltBeacon devices).
    pub id: String,
    /// Received signal strength indicator in dBm.
    pub rssi: i16,
}
