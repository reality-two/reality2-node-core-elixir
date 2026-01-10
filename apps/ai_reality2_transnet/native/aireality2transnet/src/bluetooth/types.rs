//! Type Definitions for BLE Operations
//!
//! This module defines data structures that are passed between Rust and Elixir for BLE
//! operations. All types derive `rustler::NifMap` which allows them to be automatically
//! converted to/from Elixir maps.
//!
//! ## Rustler Automatic Conversion
//!
//! ```rust
//! #[derive(rustler::NifMap)]
//! pub struct Device { ... }
//! ```
//!
//! In Rust:
//! ```rust
//! let device = Device {
//!     transport: "bluetooth".to_string(),
//!     name: "Sensor".to_string(),
//!     id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
//!     rssi: -45,
//! };
//! ```
//!
//! Automatically becomes this in Elixir:
//! ```elixir
//! %{
//!   transport: "bluetooth",
//!   name: "Sensor",
//!   id: "550e8400-e29b-41d4-a716-446655440000",
//!   rssi: -45
//! }
//! ```
//!
//! ## Why These Types?
//!
//! - **Adapters** - Enumerates available Bluetooth adapters (hci0, hci1, etc.)
//! - **Device** - Represents a discovered Reality2 node with metadata

// -------------------------------------------------------------------------------------------
// Bluetooth Adapter Information
// -------------------------------------------------------------------------------------------

/// Information about a Bluetooth adapter (hardware interface)
///
/// Represents a physical or virtual Bluetooth adapter on the system. On Linux, these
/// are typically named `hci0`, `hci1`, etc. Each adapter has a unique MAC address.
///
/// ## Usage
///
/// Returned by adapter enumeration functions to help Elixir code select which
/// Bluetooth adapter to use for BLE operations.
///
/// ## Example in Elixir
///
/// ```elixir
/// adapters = AiReality2Transnet.Action.list_adapters()
/// # => [
/// #      %{transport: "bluetooth", name: "hci0", address: "AA:BB:CC:DD:EE:FF"},
/// #      %{transport: "bluetooth", name: "hci1", address: "11:22:33:44:55:66"}
/// #    ]
/// ```
#[derive(rustler::NifMap)]
pub struct Adapters {
    /// Transport type - always "bluetooth" for BLE adapters
    pub transport: String,

    /// Adapter identifier as recognized by the OS
    ///
    /// ## Common names:
    /// - `hci0` - First Bluetooth adapter (most common)
    /// - `hci1` - Second Bluetooth adapter (if multiple)
    /// - `hci2`, `hci3`, etc. - Additional adapters
    ///
    /// ## Usage:
    /// Pass this name to BLE operation functions to specify which adapter to use
    pub name: String,

    /// MAC address of the Bluetooth adapter
    ///
    /// Format: `XX:XX:XX:XX:XX:XX` (6 bytes in hex, colon-separated)
    ///
    /// This is the hardware address that will be seen by other devices during
    /// BLE advertising and scanning.
    pub address: String,
}

// -------------------------------------------------------------------------------------------
// Discovered Device Information
// -------------------------------------------------------------------------------------------

/// Information about a discovered BLE device (Reality2 node)
///
/// Represents a Reality2 node that was discovered via BLE scanning. Contains the node's
/// identification, name, and signal strength for proximity detection.
///
/// ## Discovery Flow
///
/// ```text
/// BLE Scan → AltBeacon detected → Parse UUID → Create Device struct → Send to Elixir
/// ```
///
/// ## Usage
///
/// Sent from Rust to Elixir via messages when devices are discovered or lost:
///
/// ```elixir
/// receive do
///   {:r2node_found, node_id, device_info} ->
///     # device_info is a Device struct converted to Elixir map
///     IO.inspect(device_info.name)  # "Sensor 1"
///     IO.inspect(device_info.rssi)  # -45 (dBm)
/// end
/// ```
///
/// ## RSSI for Proximity Detection
///
/// RSSI (Received Signal Strength Indicator) can be used to estimate distance:
/// - **-30 to -50 dBm**: Very close (< 1 meter)
/// - **-50 to -70 dBm**: Close (1-3 meters)
/// - **-70 to -90 dBm**: Medium (3-10 meters)
/// - **-90 to -100 dBm**: Far (10-30 meters)
/// - **< -100 dBm**: Very far or obstructed (> 30 meters)
///
/// Note: RSSI varies significantly with obstacles, orientation, and interference.
#[derive(rustler::NifMap)]
pub struct Device {
    /// Transport type - always "bluetooth" for BLE-discovered devices
    ///
    /// This distinguishes BLE-discovered devices from WiFi mesh peers or
    /// other transport types in the future.
    pub transport: String,

    /// Human-readable device name
    ///
    /// ## Sources (in order of preference):
    /// 1. Advertised "Local Name" from BLE advertisement
    /// 2. Default: "R2 Node" if no name advertised
    ///
    /// This is for display purposes and logging, not for identification
    /// (use `id` for identification).
    pub name: String,

    /// Unique device identifier (Reality2 node UUID)
    ///
    /// This is the **16-byte UUID** extracted from the AltBeacon payload.
    /// It uniquely identifies this Reality2 node across all transient networks.
    ///
    /// Format: Standard UUID string (e.g., "550e8400-e29b-41d4-a716-446655440000")
    ///
    /// **Critical:** This ID is used for:
    /// - Tracking peer presence/absence
    /// - Addressing commands to specific nodes
    /// - Matching BLE discovery with WiFi mesh peers
    pub id: String,

    /// Received Signal Strength Indicator in dBm
    ///
    /// ## Range: -127 to 0 dBm
    /// - Higher (closer to 0) = Stronger signal = Closer device
    /// - Lower (closer to -127) = Weaker signal = Farther device
    ///
    /// ## Typical Values:
    /// - **0 dBm**: Theoretical maximum (never achieved in practice)
    /// - **-30 dBm**: Very strong (right next to device)
    /// - **-45 dBm**: Strong (within arm's reach)
    /// - **-60 dBm**: Good (same room)
    /// - **-75 dBm**: Fair (adjacent room)
    /// - **-90 dBm**: Weak (far end of house)
    /// - **-100 dBm**: Very weak (limit of useful range)
    ///
    /// ## Use Cases:
    /// - **Proximity detection**: Trigger WiFi mesh upgrade when RSSI > -70 dBm
    /// - **Presence tracking**: Mark device as "lost" when RSSI drops below -95 dBm
    /// - **Sorting**: Show nearby devices first in UI
    pub rssi: i16,

    /// WiFi hosting priority (0-100)
    ///
    /// Indicates how suitable this node is for hosting a WiFi hotspot.
    /// Higher values indicate better hosting capability.
    ///
    /// ## Typical Values:
    /// - **0**: Cannot host (no WiFi adapter)
    /// - **10**: Basic hosting (single WiFi, no internet)
    /// - **50**: Moderate (has internet but single WiFi interface)
    /// - **75**: Good (can NAT but may lose internet when hosting)
    /// - **100**: Best (wired internet or multiple WiFi adapters)
    ///
    /// ## Use Cases:
    /// - **Host selection**: Node with highest priority should become WiFi host
    /// - **Yield decisions**: Lower priority hosts should yield to higher priority nodes
    pub hosting_priority: u8,
}
