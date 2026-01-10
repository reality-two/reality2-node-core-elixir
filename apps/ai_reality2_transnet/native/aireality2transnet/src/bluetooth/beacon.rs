//! BLE Beacon Broadcasting Module
//!
//! This module implements AltBeacon protocol broadcasting for Reality2 node discovery.
//! AltBeacon is an open standard for BLE beacons that allows devices to advertise their
//! presence continuously without requiring a connection.
//!
//! ## Architecture
//!
//! - Uses BlueZ via the `bluer` crate for BLE operations
//! - Runs beacon advertising in a background Tokio runtime
//! - Provides graceful shutdown via oneshot channels
//! - Returns a resource handle to Elixir for lifecycle management
//!
//! ## AltBeacon Format (24 bytes)
//!
//! ```text
//! [0-1]   Beacon Code (0xBEAC)
//! [2-17]  UUID (16 bytes) - Reality2 node identifier
//! [18-19] Major (2 bytes) - Organization/group ID
//! [20-21] Minor (2 bytes) - Node-specific ID
//! [22]    RSSI @ 1m (1 byte) - Calibrated signal strength
//! [23]    Reserved (1 byte)
//! ```

use bluer::{adv, Session};
use rustler::{Encoder, Env, NifResult, ResourceArc, Term};
use std::collections::BTreeMap;
use std::sync::Mutex;
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::atoms;
use crate::bluetooth::common::{get_or_default_adapter, ALTBEACON_CODE};
use crate::bluetooth::resources::BeaconHandle;

// -------------------------------------------------------------------------------------------
// Constants
// -------------------------------------------------------------------------------------------

/// Maximum time to wait for beacon advertising to start before returning error to Elixir
const STARTUP_TIMEOUT_SECS: u64 = 2;

// -------------------------------------------------------------------------------------------
// NIFs (Elixir-callable functions)
// -------------------------------------------------------------------------------------------

/// Starts BLE beacon advertising with AltBeacon protocol
///
/// This NIF spawns a background thread with a Tokio runtime that continuously advertises
/// a BLE beacon. The beacon can be used for presence detection and node discovery.
///
/// ## Parameters
///
/// - `env` - Rustler environment for term encoding
/// - `company_id` - Company identifier (registered with Bluetooth SIG), typically 0xFFFF for custom
/// - `uuid_str` - UUID string identifying this Reality2 node
/// - `major` - Major version/group identifier (16-bit)
/// - `minor` - Minor version/node identifier (16-bit)
/// - `rssi_at_1m` - Calibrated RSSI value at 1 meter distance (used for distance estimation)
/// - `node_name` - Human-readable node name (e.g., "R2Node_A3F7") for BLE device name
/// - `hosting_priority` - Node's WiFi hosting priority (0-100), stored in AltBeacon reserved byte
/// - `adapter_name` - Optional Bluetooth adapter name (e.g., "hci0"), uses default if None
///
/// ## Returns
///
/// - `{:ok, BeaconHandle}` - Success, handle can be used to stop broadcasting
/// - `{:error, reason}` - Failed to start beacon
///
/// ## Scheduling
///
/// Uses `DirtyIo` scheduler because:
/// - Creates system resources (Bluetooth adapter)
/// - Performs blocking I/O operations
/// - Prevents blocking the main BEAM scheduler
///
/// ## Example (from Elixir)
///
/// ```elixir
/// {:ok, handle} = AiReality2Transnet.Action.start_broadcast(
///   0xFFFF,
///   "550e8400-e29b-41d4-a716-446655440000",
///   1,
///   100,
///   -59,
///   "R2Node_A3F7",
///   75,      # hosting priority (0-100)
///   "hci0"
/// )
/// ```
#[rustler::nif(schedule = "DirtyIo")]
pub fn start_broadcast<'a>(
    env: Env<'a>,
    company_id: u16,
    uuid_str: String,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    node_name: String,
    hosting_priority: u8,
    adapter_name: Option<String>,
) -> NifResult<Term<'a>> {
    // Parse UUID string into proper UUID type
    let uuid = match Uuid::parse_str(&uuid_str) {
        Ok(u) => u,
        Err(e) => return Ok((atoms::error(), format!("invalid_uuid: {e}")).encode(env)),
    };

    // Create channels for lifecycle management:
    // - shutdown: Elixir can signal to stop advertising
    // - ready: Background thread signals when advertising has started
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<(), String>>();

    // Spawn background thread to run async beacon advertising
    // Must use std::thread because Tokio runtime cannot run on BEAM scheduler
    std::thread::spawn(move || {
        // Create multi-threaded Tokio runtime for async BLE operations
        let rt = match tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                // Notify Elixir that runtime creation failed
                let _ = ready_tx.send(Err(format!("tokio_runtime_build_failed: {e}")));
                return;
            }
        };

        let ready_tx_clone = ready_tx.clone();

        // Run the async beacon advertising function to completion
        let result = rt.block_on(async move {
            run_beacon_advertisement(
                company_id,
                uuid,
                major,
                minor,
                rssi_at_1m,
                node_name,
                hosting_priority,
                adapter_name,
                shutdown_rx,
                ready_tx,
            )
            .await
        });

        // If advertising failed after starting, send error
        if let Err(e) = result {
            let _ = ready_tx_clone.send(Err(e));
        }
    });

    // Wait for background thread to signal that advertising has started
    // Timeout after STARTUP_TIMEOUT_SECS to avoid hanging Elixir process
    match ready_rx.recv_timeout(std::time::Duration::from_secs(STARTUP_TIMEOUT_SECS)) {
        Ok(Ok(())) => {
            // Success! Create resource handle that Elixir can use to stop advertising
            let handle = ResourceArc::new(BeaconHandle {
                shutdown_tx: Mutex::new(Some(shutdown_tx)),
            });
            Ok((atoms::ok(), handle).encode(env))
        }
        Ok(Err(reason)) => {
            // Beacon failed to start
            Ok((atoms::error(), reason).encode(env))
        }
        Err(_) => {
            // Timeout waiting for beacon to start
            Ok((
                atoms::error(),
                "timeout_waiting_for_advertisement_start".to_string(),
            )
                .encode(env))
        }
    }
}

/// Stops BLE beacon advertising
///
/// Sends shutdown signal to the background thread running the beacon.
/// The beacon will stop advertising and clean up resources gracefully.
///
/// ## Parameters
///
/// - `handle` - BeaconHandle returned from start_broadcast
///
/// ## Returns
///
/// - `:ok` - Beacon stopped successfully (or was already stopped)
///
/// ## Example (from Elixir)
///
/// ```elixir
/// :ok = AiReality2Transnet.Action.stop_broadcast(handle)
/// ```
#[rustler::nif]
pub fn stop_broadcast(handle: ResourceArc<BeaconHandle>) -> rustler::Atom {
    handle.stop();
    atoms::ok()
}

// -------------------------------------------------------------------------------------------
// Internal Functions
// -------------------------------------------------------------------------------------------

/// Runs the BLE beacon advertisement in an async context
///
/// This function:
/// 1. Builds the AltBeacon payload with node identification
/// 2. Connects to BlueZ via DBus
/// 3. Starts BLE advertising
/// 4. Waits for shutdown signal
/// 5. Cleans up gracefully
///
/// ## Parameters
///
/// - `company_id` - Bluetooth SIG company identifier
/// - `uuid` - Node UUID for identification
/// - `major` - Major version identifier
/// - `minor` - Minor version identifier
/// - `rssi_at_1m` - Calibrated signal strength for distance calculation
/// - `node_name` - Human-readable node name for BLE device name
/// - `hosting_priority` - WiFi hosting priority (0-100), stored in reserved byte
/// - `adapter_name` - Bluetooth adapter to use (e.g., "hci0")
/// - `shutdown_rx` - Receives signal from Elixir to stop advertising
/// - `ready_tx` - Sends signal to Elixir when advertising starts
///
/// ## Returns
///
/// - `Ok(())` - Advertising completed normally
/// - `Err(String)` - Failed to start or run advertising
async fn run_beacon_advertisement(
    company_id: u16,
    uuid: Uuid,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    node_name: String,
    hosting_priority: u8,
    adapter_name: Option<String>,
    shutdown_rx: oneshot::Receiver<()>,
    ready_tx: std::sync::mpsc::Sender<Result<(), String>>,
) -> Result<(), String> {
    // Build 24-byte AltBeacon payload with node identification
    // Use hosting_priority as the reserved byte for peer selection decisions
    let payload = build_altbeacon_payload(uuid, major, minor, rssi_at_1m, hosting_priority);

    // Manufacturer data is a BTreeMap of company_id -> payload
    // This is how custom data is advertised in BLE beacons
    let mut manufacturer_data = BTreeMap::new();
    manufacturer_data.insert(company_id, payload);

    // Connect to BlueZ via DBus
    let session = Session::new()
        .await
        .map_err(|e| format!("session_new_failed: {e}"))?;

    // Get the Bluetooth adapter (hci0, hci1, etc.)
    let adapter = get_or_default_adapter(&session, adapter_name).await?;

    // Power on the adapter if it's not already
    adapter
        .set_powered(true)
        .await
        .map_err(|e| format!("set_powered_failed: {e}"))?;

    // Configure advertisement with:
    // - Type: Peripheral (connectable, for GATT if needed)
    // - Discoverable: Yes (visible in scans)
    // - Local name: Node name from Bootstrap (e.g., "R2Node_A3F7")
    // - Manufacturer data: Our AltBeacon payload
    let advertisement = adv::Advertisement {
        advertisement_type: adv::Type::Peripheral,
        discoverable: Some(true),
        local_name: Some(node_name),
        manufacturer_data,
        ..Default::default()
    };

    // Start advertising - this returns a handle that keeps advertising alive
    let adv_handle = adapter
        .advertise(advertisement)
        .await
        .map_err(|e| format!("advertise_failed: {e}"))?;

    // Signal to Elixir that advertising has started successfully
    let _ = ready_tx.send(Ok(()));

    // Wait for shutdown signal from Elixir
    // This keeps the async task alive and advertising active
    let _ = shutdown_rx.await;

    // Drop the advertisement handle, which stops advertising
    drop(adv_handle);
    Ok(())
}

/// Builds an AltBeacon payload according to the specification
///
/// AltBeacon format (24 bytes total):
/// - Bytes 0-1: Beacon code (0xBEAC)
/// - Bytes 2-17: UUID (16 bytes)
/// - Bytes 18-19: Major (big-endian u16)
/// - Bytes 20-21: Minor (big-endian u16)
/// - Byte 22: RSSI at 1 meter (signed byte, for distance calculation)
/// - Byte 23: Hosting priority (0-100) - used for WiFi mesh host selection
///
/// ## Parameters
///
/// - `uuid` - Node identifier
/// - `major` - Organization/group ID
/// - `minor` - Node-specific ID
/// - `rssi_at_1m` - Calibrated signal strength at 1m distance
/// - `hosting_priority` - WiFi hosting priority (0=cannot host, 100=best host candidate)
///
/// ## Returns
///
/// 24-byte vector containing the complete AltBeacon payload
fn build_altbeacon_payload(
    uuid: Uuid,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    hosting_priority: u8,
) -> Vec<u8> {
    let mut payload = Vec::with_capacity(24);

    // Bytes 0-1: AltBeacon code (0xBEAC)
    payload.extend_from_slice(&ALTBEACON_CODE);

    // Bytes 2-17: UUID (16 bytes)
    payload.extend_from_slice(uuid.as_bytes());

    // Bytes 18-19: Major (big-endian)
    payload.extend_from_slice(&major.to_be_bytes());

    // Bytes 20-21: Minor (big-endian)
    payload.extend_from_slice(&minor.to_be_bytes());

    // Byte 22: RSSI @ 1m
    payload.push(rssi_at_1m as u8);

    // Byte 23: Hosting priority (0-100 for WiFi mesh host selection)
    payload.push(hosting_priority);

    payload
}
