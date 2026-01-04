//! Rust NIF for Bluetooth Low Energy (BLE) operations using BlueZ.
//!
//! This module provides Elixir NIFs for:
//! - Listing available Bluetooth adapters
//! - Scanning for nearby BLE devices with AltBeacon support
//! - Continuous monitoring of BLE devices with presence detection
//! - Broadcasting AltBeacon advertisements
//!
//! All operations use the BlueZ D-Bus API through the `bluer` crate.

use bluer::{adv, AdapterEvent, DiscoveryFilter, DiscoveryTransport, Session};
use futures::StreamExt;
use rustler::{Atom, Encoder, Env, LocalPid, NifResult, OwnedEnv, ResourceArc, Term};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Mutex;
use tokio::sync::oneshot;
use tokio::time::{self, Duration, Instant};
use uuid::Uuid;

// ===========================================================================================
// Elixir Atoms
// ===========================================================================================

rustler::atoms! {
    ok,
    error,
    r2_ble_found,
    r2_ble_lost,
    name,
    rssi,
    ble_addr,
    r2_nodes
}

// ===========================================================================================
// Constants
// ===========================================================================================

/// Company ID for AltBeacon manufacturer data.
/// TODO: Replace with actual assigned company ID.
const R2_COMPANY_ID: u16 = 0xFFFF;

/// Minimum timeout to prevent devices from being marked as lost too quickly.
const MIN_LOST_TIMEOUT_MS: u64 = 30_000;

/// Grace period before marking a device as truly lost (prevents flapping).
const LOST_GRACE_PERIOD_MS: u64 = 5_000;

/// Interval for checking device presence timeouts.
const PRESENCE_CHECK_INTERVAL_MS: u64 = 500;

/// Delay before restarting discovery stream after it ends.
const DISCOVERY_RESTART_DELAY_MS: u64 = 200;

/// Default device name when none is advertised.
const DEFAULT_DEVICE_NAME: &str = "R2 Node";

/// Timeout for waiting on async startup operations.
const STARTUP_TIMEOUT_SECS: u64 = 2;

/// AltBeacon identifier bytes (first two bytes of manufacturer data).
const ALTBEACON_CODE: [u8; 2] = [0xBE, 0xAC];

/// Expected minimum length for AltBeacon manufacturer data payload.
const ALTBEACON_MIN_LENGTH: usize = 24;

// ===========================================================================================
// Resource Handles
// ===========================================================================================

/// Handle for continuous device discovery/monitoring.
///
/// Dropping this handle will stop the background discovery task.
struct WatchHandle {
    shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl WatchHandle {
    /// Stops the discovery watcher.
    fn stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for WatchHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Handle for AltBeacon advertising.
///
/// Dropping this handle will stop the advertisement.
struct BeaconHandle {
    shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl BeaconHandle {
    /// Stops the beacon advertisement.
    fn stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for BeaconHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

// ===========================================================================================
// Data Structures
// ===========================================================================================

/// Information about a Bluetooth adapter.
#[derive(rustler::NifMap)]
pub struct Adapters {
    /// Adapter identifier (e.g., "hci0").
    pub id: String,
    /// Bluetooth MAC address of the adapter.
    pub address: String,
}

/// Information about a discovered BLE device.
#[derive(rustler::NifMap)]
pub struct Device {
    /// Device name (or default if not advertised).
    pub name: String,
    /// Device identifier (node UUID for AltBeacon devices).
    pub address: String,
    /// Received signal strength indicator in dBm.
    pub rssi: i16,
}

// ===========================================================================================
// Adapter Management
// ===========================================================================================

/// Lists all available Bluetooth adapters on the system.
///
/// Returns a list of adapter information including ID and MAC address.
/// Returns an empty list if no adapters are found or on error.
#[rustler::nif(schedule = "DirtyIo")]
fn list_adapters() -> Vec<Adapters> {
    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            eprintln!("list_adapters: failed to build tokio runtime: {e}");
            return vec![];
        }
    };

    let result: Result<Vec<Adapters>, String> = rt.block_on(async {
        let session = Session::new()
            .await
            .map_err(|e| format!("session_new_failed: {e}"))?;

        let adapter_names = session
            .adapter_names()
            .await
            .map_err(|e| format!("adapter_names_failed: {e}"))?;

        let mut adapters = Vec::with_capacity(adapter_names.len());

        for name in adapter_names {
            let adapter = session
                .adapter(&name)
                .map_err(|e| format!("adapter_open_failed({name}): {e}"))?;

            let address = adapter
                .address()
                .await
                .map_err(|e| format!("adapter_address_failed({name}): {e}"))?;

            adapters.push(Adapters {
                id: name,
                address: address.to_string(),
            });
        }

        Ok(adapters)
    });

    match result {
        Ok(adapters) => adapters,
        Err(e) => {
            eprintln!("list_adapters error: {e}");
            vec![]
        }
    }
}

// ===========================================================================================
// Device Scanning
// ===========================================================================================

/// Scans for nearby BLE devices with AltBeacon support.
///
/// This performs a time-limited scan and sends results to the specified Elixir process.
/// Only devices broadcasting AltBeacon manufacturer data with the configured company ID
/// are reported.
///
/// # Arguments
/// * `env` - Erlang environment
/// * `pid` - Process ID to receive scan results
/// * `timeout_ms` - Maximum scan duration in milliseconds
///
/// # Returns
/// Immediately returns `:ok`. Results are sent asynchronously as:
/// - `{:r2_nodes, [%Device{}]}` on success
/// - `{:error, reason}` on failure
#[rustler::nif]
fn scan_devices(env: Env, pid: LocalPid, timeout_ms: i32) -> Term {
    std::thread::spawn(move || {
        let mut owned_env = OwnedEnv::new();

        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                let error_msg = format!("tokio_runtime_build_failed: {e}");
                let _ = owned_env.send_and_clear(&pid, |env| {
                    (rustler::types::atom::error(), error_msg).encode(env)
                });
                return;
            }
        };

        let result: Result<Vec<Device>, String> = rt.block_on(async move {
            let session = Session::new()
                .await
                .map_err(|e| format!("session_new_failed: {e}"))?;

            let adapter = get_or_default_adapter(&session, None).await?;

            adapter
                .set_powered(true)
                .await
                .map_err(|e| format!("set_powered_failed: {e}"))?;

            let timeout_duration = Duration::from_millis(timeout_ms.max(0) as u64);
            let discovered_devices = scan_for_duration(&adapter, timeout_duration).await?;

            Ok(discovered_devices)
        });

        let _ = owned_env.send_and_clear(&pid, |env| match result {
            Ok(devices) => (r2_nodes(), devices).encode(env),
            Err(err) => (rustler::types::atom::error(), err).encode(env),
        });
    });

    rustler::types::atom::ok().encode(env)
}

/// Performs device scanning for the specified duration.
async fn scan_for_duration(
    adapter: &bluer::Adapter,
    timeout: Duration,
) -> Result<Vec<Device>, String> {
    // Track discovered nodes by their UUID (not BLE address)
    let mut discovered: HashMap<String, Device> = HashMap::new();
    // Map BLE address to node UUID for proper cleanup
    let mut ble_to_node: HashMap<String, String> = HashMap::new();

    let discover = adapter
        .discover_devices_with_changes()
        .await
        .map_err(|e| format!("discover_devices_failed: {e}"))?;
    futures::pin_mut!(discover);

    let deadline = tokio::time::sleep(timeout);
    tokio::pin!(deadline);

    loop {
        tokio::select! {
            _ = &mut deadline => break,

            event = discover.next() => {
                match event {
                    Some(AdapterEvent::DeviceAdded(addr)) => {
                        if let Ok(Some((node_id, device))) =
                            process_discovered_device(adapter, addr, R2_COMPANY_ID).await
                        {
                            let ble_addr = addr.to_string();
                            discovered.insert(node_id.clone(), device);
                            ble_to_node.insert(ble_addr, node_id);
                        }
                    }

                    Some(AdapterEvent::DeviceRemoved(addr)) => {
                        let ble_addr = addr.to_string();
                        if let Some(node_id) = ble_to_node.remove(&ble_addr) {
                            discovered.remove(&node_id);
                        }
                    }

                    Some(_) => {}
                    None => break,
                }
            }
        }
    }

    Ok(discovered.into_values().collect())
}

// ===========================================================================================
// Continuous Device Monitoring
// ===========================================================================================

/// Starts continuous monitoring of nearby BLE devices.
///
/// This creates a background task that monitors BLE devices and sends real-time
/// presence updates to the specified Elixir process. Devices are tracked using
/// their AltBeacon UUID rather than BLE address.
///
/// # Arguments
/// * `env` - Erlang environment
/// * `pid` - Process ID to receive device presence events
/// * `company_id` - Bluetooth SIG company ID to filter for
/// * `adapter_name` - Optional specific adapter name (e.g., "hci0"), or None for default
/// * `lost_after_ms` - Milliseconds of inactivity before marking device as lost (min: 30s)
///
/// # Returns
/// - `{:ok, handle}` - Handle to stop monitoring
/// - `{:error, reason}` - On failure
///
/// # Events Sent
/// - `{:r2_ble_found, node_id, %{name: ..., rssi: ..., ble_addr: ...}}` - Device appears
/// - `{:r2_ble_lost, node_id}` - Device disappears
#[rustler::nif(schedule = "DirtyIo")]
fn start_r2_watch<'a>(
    env: Env<'a>,
    pid: LocalPid,
    company_id: u16,
    adapter_name: Option<String>,
    lost_after_ms: u64,
) -> NifResult<Term<'a>> {
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<(), String>>();

    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                let _ = ready_tx.send(Err(format!("tokio_runtime_build_failed: {e}")));
                return;
            }
        };

        let ready_tx_clone = ready_tx.clone();

        let result = rt.block_on(async move {
            run_continuous_watch(
                pid,
                company_id,
                adapter_name,
                lost_after_ms,
                shutdown_rx,
                ready_tx,
            )
            .await
        });

        if let Err(e) = result {
            let _ = ready_tx_clone.send(Err(e));
        }
    });

    match ready_rx.recv_timeout(std::time::Duration::from_secs(STARTUP_TIMEOUT_SECS)) {
        Ok(Ok(())) => {
            let handle = ResourceArc::new(WatchHandle {
                shutdown_tx: Mutex::new(Some(shutdown_tx)),
            });
            Ok((ok(), handle).encode(env))
        }
        Ok(Err(reason)) => Ok((error(), reason).encode(env)),
        Err(_) => Ok((error(), "timeout_waiting_for_watch_start".to_string()).encode(env)),
    }
}

/// Runs the continuous device monitoring loop.
async fn run_continuous_watch(
    pid: LocalPid,
    company_id: u16,
    adapter_name: Option<String>,
    lost_after_ms: u64,
    mut shutdown_rx: oneshot::Receiver<()>,
    ready_tx: std::sync::mpsc::Sender<Result<(), String>>,
) -> Result<(), String> {
    let session = Session::new()
        .await
        .map_err(|e| format!("session_new_failed: {e}"))?;

    let adapter = get_or_default_adapter(&session, adapter_name).await?;

    adapter
        .set_powered(true)
        .await
        .map_err(|e| format!("set_powered_failed: {e}"))?;

    // Configure discovery filter to receive RSSI updates.
    // This forces BlueZ to emit DeviceAdded events when RSSI changes,
    // allowing us to refresh device presence even without new advertisements.
    configure_rssi_discovery_filter(&adapter).await;

    let lost_after = Duration::from_millis(lost_after_ms.max(MIN_LOST_TIMEOUT_MS));
    let lost_grace = Duration::from_millis(LOST_GRACE_PERIOD_MS);
    let mut tick_interval = time::interval(Duration::from_millis(PRESENCE_CHECK_INTERVAL_MS));

    let mut presence_tracker = PresenceTracker::new();

    // Signal that initialization completed successfully
    let _ = ready_tx.send(Ok(()));

    loop {
        let discover = adapter
            .discover_devices_with_changes()
            .await
            .map_err(|e| format!("discover_devices_failed: {e}"))?;
        futures::pin_mut!(discover);

        loop {
            tokio::select! {
                // Shutdown requested
                _ = &mut shutdown_rx => return Ok(()),

                // Check for devices that have timed out
                _ = tick_interval.tick() => {
                    handle_presence_timeout(
                        &mut presence_tracker,
                        &pid,
                        lost_after,
                        lost_grace,
                    );
                }

                // Process discovery events
                event = discover.next() => {
                    match event {
                        Some(AdapterEvent::DeviceAdded(addr)) => {
                            handle_device_added(
                                &adapter,
                                addr,
                                company_id,
                                &mut presence_tracker,
                                &pid,
                            ).await?;
                        }

                        Some(AdapterEvent::DeviceRemoved(_)) => {
                            // Do not treat DeviceRemoved as "lost" for proximity tracking.
                            // BlueZ may remove device objects for various reasons unrelated
                            // to actual RF presence. Rely on RSSI timeout instead.
                        }

                        Some(AdapterEvent::PropertyChanged(_)) => {
                            // Ignore property changes
                        }

                        None => {
                            // Discovery stream ended, restart after brief delay
                            break;
                        }
                    }
                }
            }
        }

        // Brief delay before restarting discovery
        time::sleep(Duration::from_millis(DISCOVERY_RESTART_DELAY_MS)).await;
    }
}

/// Stops continuous device monitoring.
#[rustler::nif]
fn stop_r2_watch(handle: ResourceArc<WatchHandle>) -> Atom {
    handle.stop();
    ok()
}

// ===========================================================================================
// Presence Tracking
// ===========================================================================================

/// Tracks device presence state for continuous monitoring.
struct PresenceTracker {
    /// Set of currently present node UUIDs
    present: HashSet<String>,
    /// Timestamp of last sighting for each node
    last_seen: HashMap<String, Instant>,
    /// Timestamp when device first became suspect (exceeded timeout)
    suspect_since: HashMap<String, Instant>,
    /// Mapping from node UUID to last known BLE address
    node_to_ble: HashMap<String, String>,
}

impl PresenceTracker {
    fn new() -> Self {
        Self {
            present: HashSet::new(),
            last_seen: HashMap::new(),
            suspect_since: HashMap::new(),
            node_to_ble: HashMap::new(),
        }
    }

    /// Records a device sighting, updating presence and timing information.
    fn record_sighting(&mut self, node_id: String, ble_addr: String) {
        self.last_seen.insert(node_id.clone(), Instant::now());
        self.suspect_since.remove(&node_id);
        self.node_to_ble.insert(node_id, ble_addr);
    }

    /// Marks a device as newly present.
    ///
    /// Returns true if this is the first sighting (should notify Elixir).
    fn mark_present(&mut self, node_id: String) -> bool {
        self.present.insert(node_id)
    }

    /// Marks a device as lost and cleans up all tracking data.
    fn mark_lost(&mut self, node_id: &str) {
        self.present.remove(node_id);
        self.last_seen.remove(node_id);
        self.suspect_since.remove(node_id);
        self.node_to_ble.remove(node_id);
    }

    /// Returns nodes that should be marked as lost based on timeout and grace period.
    fn get_timed_out_nodes(&mut self, lost_after: Duration, lost_grace: Duration) -> Vec<String> {
        let now = Instant::now();
        let mut to_lost = Vec::new();

        for node_id in &self.present {
            let Some(&last_seen_time) = self.last_seen.get(node_id) else {
                continue;
            };

            let time_since_seen = now.duration_since(last_seen_time);
            let is_overdue = time_since_seen > lost_after;

            if !is_overdue {
                // Device is still within timeout - clear suspect status
                self.suspect_since.remove(node_id);
                continue;
            }

            // Device exceeded timeout - apply grace period
            match self.suspect_since.get(node_id) {
                None => {
                    // First time seeing device as overdue - mark as suspect
                    self.suspect_since.insert(node_id.clone(), now);
                }
                Some(&suspect_start) => {
                    // Check if grace period has also elapsed
                    if now.duration_since(suspect_start) > lost_grace {
                        to_lost.push(node_id.clone());
                    }
                }
            }
        }

        to_lost
    }
}

/// Handles periodic timeout checking and marks devices as lost.
fn handle_presence_timeout(
    tracker: &mut PresenceTracker,
    pid: &LocalPid,
    lost_after: Duration,
    lost_grace: Duration,
) {
    let timed_out = tracker.get_timed_out_nodes(lost_after, lost_grace);

    for node_id in timed_out {
        tracker.mark_lost(&node_id);
        send_msg(pid, |env| (r2_ble_lost(), node_id).encode(env));
    }
}

/// Processes a DeviceAdded event during continuous monitoring.
async fn handle_device_added(
    adapter: &bluer::Adapter,
    addr: bluer::Address,
    company_id: u16,
    tracker: &mut PresenceTracker,
    pid: &LocalPid,
) -> Result<(), String> {
    let ble_address_str = addr.to_string();

    let Some((node_id, device_info)) = process_discovered_device(adapter, addr, company_id).await?
    else {
        return Ok(());
    };

    // Refresh liveness on every matching event (not just first sighting).
    // This ensures continuous RSSI updates keep the device marked as present.
    tracker.record_sighting(node_id.clone(), ble_address_str.clone());

    // Only notify Elixir on first sighting
    if tracker.mark_present(node_id.clone()) {
        send_msg(pid, |env| {
            let info = rustler::types::map::map_new(env)
                .map_put(name().encode(env), device_info.name.encode(env))
                .unwrap()
                .map_put(rssi().encode(env), (device_info.rssi as i32).encode(env))
                .unwrap()
                .map_put(ble_addr().encode(env), ble_address_str.encode(env))
                .unwrap();

            (r2_ble_found(), node_id, info).encode(env)
        });
    }

    Ok(())
}

// ===========================================================================================
// AltBeacon Advertising
// ===========================================================================================

/// Starts broadcasting an AltBeacon advertisement.
///
/// This creates a background task that continuously broadcasts the specified
/// AltBeacon until stopped.
///
/// # Arguments
/// * `env` - Erlang environment
/// * `company_id` - Bluetooth SIG company ID for manufacturer data
/// * `uuid_str` - UUID to broadcast (typically a unique node identifier)
/// * `major` - Major version number (2 bytes)
/// * `minor` - Minor version number (2 bytes)
/// * `rssi_at_1m` - Calibrated RSSI at 1 meter distance
/// * `adapter_name` - Optional specific adapter name, or None for default
///
/// # Returns
/// - `{:ok, handle}` - Handle to stop advertising
/// - `{:error, reason}` - On failure
#[rustler::nif(schedule = "DirtyIo")]
fn start_altbeacon<'a>(
    env: Env<'a>,
    company_id: u16,
    uuid_str: String,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    adapter_name: Option<String>,
) -> NifResult<Term<'a>> {
    let uuid = match Uuid::parse_str(&uuid_str) {
        Ok(u) => u,
        Err(e) => return Ok((error(), format!("invalid_uuid: {e}")).encode(env)),
    };

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<(), String>>();

    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                let _ = ready_tx.send(Err(format!("tokio_runtime_build_failed: {e}")));
                return;
            }
        };

        let ready_tx_clone = ready_tx.clone();

        let result = rt.block_on(async move {
            run_beacon_advertisement(
                company_id,
                uuid,
                major,
                minor,
                rssi_at_1m,
                adapter_name,
                shutdown_rx,
                ready_tx,
            )
            .await
        });

        if let Err(e) = result {
            let _ = ready_tx_clone.send(Err(e));
        }
    });

    match ready_rx.recv_timeout(std::time::Duration::from_secs(STARTUP_TIMEOUT_SECS)) {
        Ok(Ok(())) => {
            let handle = ResourceArc::new(BeaconHandle {
                shutdown_tx: Mutex::new(Some(shutdown_tx)),
            });
            Ok((ok(), handle).encode(env))
        }
        Ok(Err(reason)) => Ok((error(), reason).encode(env)),
        Err(_) => Ok((
            error(),
            "timeout_waiting_for_advertisement_start".to_string(),
        )
            .encode(env)),
    }
}

/// Runs the beacon advertisement until stopped.
async fn run_beacon_advertisement(
    company_id: u16,
    uuid: Uuid,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    adapter_name: Option<String>,
    shutdown_rx: oneshot::Receiver<()>,
    ready_tx: std::sync::mpsc::Sender<Result<(), String>>,
) -> Result<(), String> {
    let payload = build_altbeacon_payload(uuid, major, minor, rssi_at_1m, 0x00);
    let mut manufacturer_data = BTreeMap::new();
    manufacturer_data.insert(company_id, payload);

    let session = Session::new()
        .await
        .map_err(|e| format!("session_new_failed: {e}"))?;

    let adapter = get_or_default_adapter(&session, adapter_name).await?;

    adapter
        .set_powered(true)
        .await
        .map_err(|e| format!("set_powered_failed: {e}"))?;

    // Configure advertisement.
    // Note: Using Peripheral type allows for GATT connections if needed.
    // For pure AltBeacon (non-connectable), use Type::Broadcast instead.
    // Including local_name may require extended advertising depending on controller.
    let advertisement = adv::Advertisement {
        advertisement_type: adv::Type::Peripheral,
        discoverable: Some(true),
        local_name: Some(DEFAULT_DEVICE_NAME.to_string()),
        manufacturer_data,
        ..Default::default()
    };

    let adv_handle = adapter
        .advertise(advertisement)
        .await
        .map_err(|e| format!("advertise_failed: {e}"))?;

    // Signal that advertising started successfully
    let _ = ready_tx.send(Ok(()));

    // Wait for shutdown signal
    let _ = shutdown_rx.await;

    // Stop advertising by dropping the handle
    drop(adv_handle);

    Ok(())
}

/// Stops AltBeacon advertising.
#[rustler::nif]
fn stop_altbeacon(handle: ResourceArc<BeaconHandle>) -> Atom {
    handle.stop();
    ok()
}

// ===========================================================================================
// Helper Functions
// ===========================================================================================

/// Gets a specific adapter or the default if none specified.
async fn get_or_default_adapter(
    session: &Session,
    adapter_name: Option<String>,
) -> Result<bluer::Adapter, String> {
    match adapter_name {
        Some(name) => session
            .adapter(&name)
            .map_err(|e| format!("adapter_open_failed({name}): {e}")),
        None => {
            // Try to get "hci0" first, fall back to system default
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

/// Configures discovery filter to receive continuous RSSI updates.
///
/// This is crucial for presence detection: it forces BlueZ to emit
/// DeviceAdded events when RSSI changes, allowing us to refresh
/// device liveness even without new advertising packets.
async fn configure_rssi_discovery_filter(adapter: &bluer::Adapter) {
    let mut filter = DiscoveryFilter::default();
    filter.transport = DiscoveryTransport::Le;
    // Set RSSI to minimum value to accept all devices but enable RSSI tracking
    filter.rssi = Some(-127);

    if let Err(e) = adapter.set_discovery_filter(filter).await {
        // Don't fail if filter can't be set (another client may be using discovery)
        eprintln!("set_discovery_filter failed (continuing): {e}");
    }
}

/// Processes a discovered device and extracts AltBeacon information if present.
///
/// Returns `Ok(Some((node_id, device)))` if the device is a valid AltBeacon,
/// `Ok(None)` if it's not an AltBeacon or doesn't match criteria,
/// or `Err` on communication errors.
async fn process_discovered_device(
    adapter: &bluer::Adapter,
    addr: bluer::Address,
    company_id: u16,
) -> Result<Option<(String, Device)>, String> {
    let ble_addr = addr.to_string();

    let device = adapter
        .device(addr)
        .map_err(|e| format!("device_open_failed({ble_addr}): {e}"))?;

    // Check for manufacturer data
    let Some(manufacturer_data) = device
        .manufacturer_data()
        .await
        .map_err(|e| format!("manufacturer_data_failed({ble_addr}): {e}"))?
    else {
        return Ok(None);
    };

    // Check for our company ID
    let Some(payload) = manufacturer_data.get(&company_id) else {
        return Ok(None);
    };

    // Parse AltBeacon UUID
    let Some(node_uuid) = extract_altbeacon_uuid(payload) else {
        return Ok(None);
    };

    let node_id = node_uuid.to_string();

    // Verify device is currently present by checking RSSI.
    // Devices without RSSI are likely cached/stale entries.
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
            name: device_name,
            address: node_id, // Use node UUID as address
            rssi,
        },
    )))
}

/// Extracts UUID from AltBeacon manufacturer data payload.
///
/// AltBeacon format (24+ bytes):
/// - [0..2]: Beacon code (0xBEAC)
/// - [2..18]: UUID (16 bytes)
/// - [18..20]: Major (2 bytes, big-endian)
/// - [20..22]: Minor (2 bytes, big-endian)
/// - [22]: RSSI at 1 meter
/// - [23]: Reserved
///
/// Returns the UUID if the payload is valid AltBeacon format.
fn extract_altbeacon_uuid(payload: &[u8]) -> Option<Uuid> {
    if payload.len() < ALTBEACON_MIN_LENGTH {
        return None;
    }

    // Verify AltBeacon identifier
    if payload[0] != ALTBEACON_CODE[0] || payload[1] != ALTBEACON_CODE[1] {
        return None;
    }

    // Extract and parse UUID
    Uuid::from_slice(&payload[2..18]).ok()
}

/// Builds AltBeacon manufacturer data payload.
///
/// Creates a 24-byte payload according to AltBeacon specification.
fn build_altbeacon_payload(
    uuid: Uuid,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    reserved: u8,
) -> Vec<u8> {
    let mut payload = Vec::with_capacity(24);

    // Beacon code
    payload.extend_from_slice(&ALTBEACON_CODE);

    // UUID (16 bytes)
    payload.extend_from_slice(uuid.as_bytes());

    // Major and minor (big-endian)
    payload.extend_from_slice(&major.to_be_bytes());
    payload.extend_from_slice(&minor.to_be_bytes());

    // RSSI at 1 meter (signed byte as unsigned)
    payload.push(rssi_at_1m as u8);

    // Reserved byte
    payload.push(reserved);

    payload
}

/// Sends a message to an Elixir process.
///
/// The message is constructed in an isolated environment to avoid
/// issues with term ownership across threads.
fn send_msg(pid: &LocalPid, term_builder: impl FnOnce(Env) -> Term) {
    let mut owned_env = OwnedEnv::new();
    let _ = owned_env.send_and_clear(pid, term_builder);
}

// ===========================================================================================
// NIF Initialization
// ===========================================================================================

/// Loads resources and initializes the NIF module.
#[allow(non_local_definitions)]
fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(WatchHandle, env);
    let _ = rustler::resource!(BeaconHandle, env);
    true
}

rustler::init!("Elixir.AiReality2Transnet.Action", load = load);
