//! Common Utilities for Bluetooth Operations
//!
//! This module contains shared constants, helper functions, and utilities used across
//! the beacon, discovery, and GATT modules.
//!
//! ## Key Functions
//!
//! - **Adapter Management** - Select appropriate Bluetooth adapter (hci0, hci1, etc.)
//! - **AltBeacon Parsing** - Extract Reality2 node UUID from beacon payloads
//! - **Device Processing** - Convert BLE advertisement data into Reality2 device info
//! - **IPC Helpers** - Send messages from Rust threads to Elixir processes

use bluer::{DiscoveryFilter, DiscoveryTransport, Session};
use rustler::{Env, LocalPid, OwnedEnv, Term};
use uuid::Uuid;

use crate::bluetooth::types::Device;

// -------------------------------------------------------------------------------------------
// Shared Constants
// -------------------------------------------------------------------------------------------

/// Company ID for Reality2 manufacturer data in BLE advertisements
///
/// Currently using 0xFFFF (reserved for internal/testing use).
/// **TODO:** Replace with an officially assigned Bluetooth SIG company ID for production.
///
/// Company IDs are registered at: https://www.bluetooth.com/specifications/assigned-numbers/
pub const R2_COMPANY_ID: u16 = 0xFFFF;

/// Default human-readable device name shown in BLE scans
///
/// Used when a device doesn't advertise a custom local name.
pub const DEFAULT_DEVICE_NAME: &str = "R2 Node";

/// AltBeacon protocol identifier (first 2 bytes of manufacturer data)
///
/// AltBeacon spec: https://github.com/AltBeacon/spec
/// Value: 0xBEAC identifies this as an AltBeacon packet
pub const ALTBEACON_CODE: [u8; 2] = [0xBE, 0xAC];

/// Minimum length of a valid AltBeacon manufacturer data payload
///
/// AltBeacon format (24 bytes):
/// ```text
/// [0-1]   Beacon code (0xBEAC)
/// [2-17]  UUID (16 bytes)
/// [18-19] Major (2 bytes)
/// [20-21] Minor (2 bytes)
/// [22]    RSSI @ 1m (1 byte)
/// [23]    Hosting priority (1 byte) - WiFi mesh host selection (0-100)
/// ```
pub const ALTBEACON_MIN_LENGTH: usize = 24;

// -------------------------------------------------------------------------------------------
// Bluetooth Adapter Management
// -------------------------------------------------------------------------------------------

/// Gets a Bluetooth adapter by name, or selects a default adapter
///
/// This function provides intelligent adapter selection:
/// 1. If `adapter_name` is provided (e.g., "hci0"), use that specific adapter
/// 2. Otherwise, prefer "hci0" if it exists (most common default)
/// 3. Fall back to system default adapter
///
/// ## Parameters
///
/// - `session` - BlueZ DBus session
/// - `adapter_name` - Optional adapter name (e.g., "hci0", "hci1")
///
/// ## Returns
///
/// - `Ok(Adapter)` - Successfully opened Bluetooth adapter
/// - `Err(String)` - Failed to open adapter (not found, permission denied, etc.)
///
/// ## Examples
///
/// ```rust
/// // Use specific adapter
/// let adapter = get_or_default_adapter(&session, Some("hci1".to_string())).await?;
///
/// // Use default (prefers hci0)
/// let adapter = get_or_default_adapter(&session, None).await?;
/// ```
///
/// ## Common Errors
///
/// - "adapter_open_failed(hci0): No such adapter" - Bluetooth hardware not available
/// - "adapter_open_failed(hci1): Permission denied" - Need root or bluetooth group
pub async fn get_or_default_adapter(
    session: &Session,
    adapter_name: Option<String>,
) -> Result<bluer::Adapter, String> {
    match adapter_name {
        Some(name) => session
            .adapter(&name)
            .map_err(|e| format!("adapter_open_failed({name}): {e}")),
        None => {
            let names = session
                .adapter_names()
                .await
                .map_err(|e| format!("adapter_names_failed: {e}"))?;

            if let Some(hci0) = names.iter().find(|n| n.as_str() == "hci0") {
                session
                    .adapter(hci0)
                    .map_err(|e| format!("adapter_open_failed(hci0): {e}"))
            } else {
                session
                    .default_adapter()
                    .await
                    .map_err(|e| format!("default_adapter_failed: {e}"))
            }
        }
    }
}

// -------------------------------------------------------------------------------------------
// BLE Discovery Configuration
// -------------------------------------------------------------------------------------------

/// Configures discovery filter to receive continuous RSSI updates
///
/// By default, BlueZ only reports device discovery events once. This filter configures
/// the adapter to continuously report RSSI (signal strength) updates, which is essential
/// for:
/// - Proximity detection (closer devices have higher RSSI)
/// - Presence tracking (device moved away = lower RSSI, then lost)
/// - Signal quality monitoring
///
/// ## Parameters
///
/// - `adapter` - Bluetooth adapter to configure
///
/// ## Filter Configuration
///
/// - **Transport:** LE (Low Energy) only - ignore BR/EDR (Classic Bluetooth)
/// - **RSSI:** -127 dBm minimum - accept all signal strengths (maximum range)
///
/// ## Error Handling
///
/// Errors are logged but not propagated, as discovery can work without this filter
/// (just won't get continuous RSSI updates).
pub async fn configure_rssi_discovery_filter(adapter: &bluer::Adapter) {
    let mut filter = DiscoveryFilter::default();
    filter.transport = DiscoveryTransport::Le; // BLE only, ignore Classic Bluetooth
    filter.rssi = Some(-127); // Accept all signal strengths (-127 = minimum)

    if let Err(e) = adapter.set_discovery_filter(filter).await {
        eprint!("[warning] set_discovery_filter failed (continuing): {e}\r\n");
    }
}

// -------------------------------------------------------------------------------------------
// Device Processing
// -------------------------------------------------------------------------------------------

/// Processes a discovered BLE device to check if it's a Reality2 node
///
/// This function:
/// 1. Reads manufacturer data from the device
/// 2. Checks if it contains our company ID
/// 3. Validates AltBeacon format
/// 4. Extracts node UUID and device information
///
/// ## Parameters
///
/// - `adapter` - Bluetooth adapter
/// - `addr` - BLE device address (MAC address)
/// - `company_id` - Reality2 company ID to filter for
///
/// ## Returns
///
/// - `Ok(Some((node_id, Device)))` - This is a Reality2 device, here's its info
/// - `Ok(None)` - Not a Reality2 device (wrong format, no manufacturer data, etc.)
/// - `Err(String)` - Failed to query device (permission issue, device disappeared, etc.)
///
/// ## Device Info Extracted
///
/// - **Node ID** - UUID from AltBeacon payload (unique node identifier)
/// - **Device Name** - Advertised local name, or "R2 Node" if not set
/// - **RSSI** - Signal strength (for proximity detection)
/// - **Transport** - Always "bluetooth" for BLE-discovered devices
pub async fn process_discovered_device(
    adapter: &bluer::Adapter,
    addr: bluer::Address,
    company_id: u16,
) -> Result<Option<(String, Device)>, String> {
    let ble_addr = addr.to_string();

    let device = adapter
        .device(addr)
        .map_err(|e| format!("device_open_failed({ble_addr}): {e}"))?;

    let Some(manufacturer_data) = device
        .manufacturer_data()
        .await
        .map_err(|e| format!("manufacturer_data_failed({ble_addr}): {e}"))?
    else {
        return Ok(None);
    };

    let Some(payload) = manufacturer_data.get(&company_id) else {
        return Ok(None);
    };

    let Some((node_uuid, hosting_priority)) = extract_altbeacon_data(payload) else {
        return Ok(None);
    };

    let node_id = node_uuid.to_string();

    let rssi = match device
        .rssi()
        .await
        .map_err(|e| format!("rssi_failed({ble_addr}): {e}"))?
    {
        Some(r) => r,
        None => return Ok(None),
    };

    let device_name = device
        .name()
        .await
        .map_err(|e| format!("name_failed({ble_addr}): {e}"))?
        .unwrap_or_else(|| DEFAULT_DEVICE_NAME.to_string());

    Ok(Some((
        node_id.clone(),
        Device {
            transport: String::from("bluetooth"),
            name: device_name,
            id: node_id,
            rssi,
            hosting_priority,
        },
    )))
}

// -------------------------------------------------------------------------------------------
// AltBeacon Parsing
// -------------------------------------------------------------------------------------------

/// Extracts the Reality2 node UUID and hosting priority from an AltBeacon payload
///
/// Validates and parses AltBeacon format to extract:
/// - 16-byte UUID (bytes 2-17) - unique node identifier
/// - Hosting priority (byte 23) - WiFi mesh host selection score (0-100)
///
/// ## Parameters
///
/// - `payload` - Manufacturer data bytes from BLE advertisement
///
/// ## Returns
///
/// - `Some((Uuid, u8))` - Valid payload: (node UUID, hosting priority)
/// - `None` - Invalid payload (too short, wrong beacon code, malformed UUID)
///
/// ## Validation
///
/// 1. Check length >= 24 bytes (minimum AltBeacon size)
/// 2. Check bytes 0-1 == 0xBEAC (AltBeacon identifier)
/// 3. Parse bytes 2-17 as UUID (16 bytes)
/// 4. Extract byte 23 as hosting priority
///
/// ## Example
///
/// ```rust
/// let payload = vec![
///     0xBE, 0xAC,                           // Beacon code
///     // UUID bytes here (16 bytes)
///     // ... major, minor, rssi, priority
/// ];
/// if let Some((uuid, priority)) = extract_altbeacon_data(&payload) {
///     println!("Found Reality2 node: {} with priority {}", uuid, priority);
/// }
/// ```
pub fn extract_altbeacon_data(payload: &[u8]) -> Option<(Uuid, u8)> {
    // Check minimum length
    if payload.len() < ALTBEACON_MIN_LENGTH {
        return None;
    }

    // Validate AltBeacon identifier (0xBEAC)
    if payload[0] != ALTBEACON_CODE[0] || payload[1] != ALTBEACON_CODE[1] {
        return None;
    }

    // Extract UUID from bytes 2-17 (16 bytes)
    let uuid = Uuid::from_slice(&payload[2..18]).ok()?;

    // Extract hosting priority from byte 23
    let hosting_priority = payload[23];

    Some((uuid, hosting_priority))
}

/// Extracts just the Reality2 node UUID from an AltBeacon payload (legacy function)
///
/// Use `extract_altbeacon_data` instead to also get hosting priority.
#[allow(dead_code)]
pub fn extract_altbeacon_uuid(payload: &[u8]) -> Option<Uuid> {
    extract_altbeacon_data(payload).map(|(uuid, _)| uuid)
}

// -------------------------------------------------------------------------------------------
// Elixir IPC
// -------------------------------------------------------------------------------------------

/// Sends a message from a Rust thread to an Elixir process
///
/// This function provides thread-safe communication from Rust async tasks back to Elixir.
/// Uses `OwnedEnv` which allows sending terms across thread boundaries.
///
/// ## Parameters
///
/// - `pid` - Elixir process ID (LocalPid) to send message to
/// - `term_builder` - Closure that builds the term to send (receives an Env)
///
/// ## Usage Pattern
///
/// ```rust
/// // From async Rust task, send tuple {:r2node_found, node_id} to Elixir
/// send_msg(&pid, |env| {
///     (atoms::r2node_found(), node_id.clone()).encode(env)
/// });
/// ```
///
/// ## Thread Safety
///
/// `OwnedEnv` creates a new environment that can be sent across threads, allowing
/// Rust async tasks running on Tokio thread pool to communicate with BEAM processes.
///
/// ## Error Handling
///
/// Errors (e.g., process died) are silently ignored. This is appropriate for event
/// notifications where we don't want to crash the Rust task if Elixir process exits.
pub fn send_msg(pid: &LocalPid, term_builder: impl FnOnce(Env) -> Term) {
    let mut owned_env = OwnedEnv::new();
    let _ = owned_env.send_and_clear(pid, term_builder);
}
