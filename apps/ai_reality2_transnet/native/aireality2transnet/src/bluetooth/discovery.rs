use bluer::{AdapterEvent, Session};
use futures::StreamExt;
use rustler::{Encoder, Env, LocalPid, NifResult, OwnedEnv, ResourceArc, Term};
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use tokio::sync::oneshot;
use tokio::time::{self, Duration, Instant};

use crate::atoms;
use crate::bluetooth::common::{
    configure_rssi_discovery_filter, get_or_default_adapter, process_discovered_device, send_msg,
    R2_COMPANY_ID,
};
use crate::bluetooth::resources::{ResetCommand, WatchHandle};
use crate::bluetooth::types::{Adapters, Device};

// -------------------------------------------------------------------------------------------
// Constants (discovery-specific)
// -------------------------------------------------------------------------------------------

const MIN_LOST_TIMEOUT_MS: u64 = 30_000;
const LOST_GRACE_PERIOD_MS: u64 = 5_000;
const PRESENCE_CHECK_INTERVAL_MS: u64 = 500;
const DISCOVERY_RESTART_DELAY_MS: u64 = 200;
const STARTUP_TIMEOUT_SECS: u64 = 2;

// -------------------------------------------------------------------------------------------
// Adapter Management
// -------------------------------------------------------------------------------------------

// Lists the available Bluetooth adapters, waiting for the response and returning the list of adapters.
#[rustler::nif(schedule = "DirtyIo")]
pub fn list_adapters_seq() -> Vec<Adapters> {
    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            eprint!("[warning] list_adapters: failed to build tokio runtime: {e}\r\n");
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
                transport: String::from("bluetooth"),
                name: name,
                address: address.to_string(),
            });
        }

        Ok(adapters)
    });

    match result {
        Ok(adapters) => adapters,
        Err(e) => {
            eprint!("[warning] list_adapters error: {e}\r\n");
            vec![]
        }
    }
}

/// Lists the Bluetooth adapters available on the system, sends a response back when ready.
#[rustler::nif]
pub fn list_adapters(env: Env, pid: LocalPid) -> Term {
    std::thread::spawn(move || {
        let mut owned_env = OwnedEnv::new();

        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                let error_msg = format!("tokio_runtime_build_failed: {e}");
                let _ =
                    owned_env.send_and_clear(&pid, |env| (atoms::error(), error_msg).encode(env));
                return;
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
                    transport: String::from("bluetooth"),
                    name: name,
                    address: address.to_string(),
                });
            }

            Ok(adapters)
        });

        let _ = owned_env.send_and_clear(&pid, |env| match result {
            Ok(adapters) => (atoms::adapters(), adapters).encode(env),
            Err(err) => (atoms::error(), err).encode(env),
        });
    });

    atoms::ok().encode(env)
}

#[rustler::nif]
pub fn reset_nodes(handle: ResourceArc<WatchHandle>) -> rustler::Atom {
    let lock = handle.reset_tx.lock().unwrap();
    if let Some(tx) = lock.as_ref() {
        let _ = tx.send(ResetCommand::ClearAll);
        atoms::ok()
    } else {
        atoms::error()
    }
}

// -------------------------------------------------------------------------------------------
// Device Scanning (time-limited)
// -------------------------------------------------------------------------------------------

#[rustler::nif]
pub fn scan_nodes(env: Env, pid: LocalPid, timeout_ms: i32) -> Term {
    std::thread::spawn(move || {
        let mut owned_env = OwnedEnv::new();

        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                let error_msg = format!("tokio_runtime_build_failed: {e}");
                let _ =
                    owned_env.send_and_clear(&pid, |env| (atoms::error(), error_msg).encode(env));
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
            scan_for_duration(&adapter, timeout_duration).await
        });

        let _ = owned_env.send_and_clear(&pid, |env| match result {
            Ok(devices) => (atoms::r2nodes(), devices).encode(env),
            Err(err) => (atoms::error(), err).encode(env),
        });
    });

    atoms::ok().encode(env)
}

async fn scan_for_duration(
    adapter: &bluer::Adapter,
    timeout: Duration,
) -> Result<Vec<Device>, String> {
    let mut discovered: HashMap<String, Device> = HashMap::new();
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

// -------------------------------------------------------------------------------------------
// Continuous Device Monitoring (presence watch)
// -------------------------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
pub fn start_watching<'a>(
    env: Env<'a>,
    pid: LocalPid,
    company_id: u16,
    adapter_name: Option<String>,
    lost_after_ms: u64,
) -> NifResult<Term<'a>> {
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (reset_tx, reset_rx) = tokio::sync::mpsc::unbounded_channel::<ResetCommand>();
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
                reset_rx,
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
                reset_tx: Mutex::new(Some(reset_tx)),
            });
            Ok((atoms::ok(), handle).encode(env))
        }
        Ok(Err(reason)) => Ok((atoms::error(), reason).encode(env)),
        Err(_) => Ok((
            atoms::error(),
            "timeout_waiting_for_watch_start".to_string(),
        )
            .encode(env)),
    }
}

/// The continuous watch task.
async fn run_continuous_watch(
    pid: LocalPid,
    company_id: u16,
    adapter_name: Option<String>,
    lost_after_ms: u64,
    mut shutdown_rx: oneshot::Receiver<()>,
    mut reset_rx: tokio::sync::mpsc::UnboundedReceiver<ResetCommand>,
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

    configure_rssi_discovery_filter(&adapter).await;

    let lost_after = Duration::from_millis(lost_after_ms.max(MIN_LOST_TIMEOUT_MS));
    let lost_grace = Duration::from_millis(LOST_GRACE_PERIOD_MS);
    let mut tick_interval = time::interval(Duration::from_millis(PRESENCE_CHECK_INTERVAL_MS));

    let mut presence_tracker = PresenceTracker::new();

    let _ = ready_tx.send(Ok(()));

    loop {
        let discover = adapter
            .discover_devices_with_changes()
            .await
            .map_err(|e| format!("discover_devices_failed: {e}"))?;
        futures::pin_mut!(discover);

        loop {
            tokio::select! {
                _ = &mut shutdown_rx => return Ok(()),

                Some(cmd) = reset_rx.recv() => {
                    match cmd {
                        ResetCommand::ClearAll => {
                            presence_tracker.clear_all();
                            send_msg(&pid, |env| atoms::devices_cleared().encode(env));
                        }
                    }
                }

                _ = tick_interval.tick() => {
                    handle_presence_timeout(&mut presence_tracker, &pid, lost_after, lost_grace);
                }

                event = discover.next() => {
                    match event {
                        Some(AdapterEvent::DeviceAdded(addr)) => {
                            handle_device_added(&adapter, addr, company_id, &mut presence_tracker, &pid).await?;
                        }
                        Some(AdapterEvent::DeviceRemoved(_)) => {}
                        Some(AdapterEvent::PropertyChanged(_)) => {}
                        None => break,
                    }
                }
            }
        }

        time::sleep(Duration::from_millis(DISCOVERY_RESTART_DELAY_MS)).await;
    }
}

#[rustler::nif]
pub fn stop_watching(handle: ResourceArc<WatchHandle>) -> rustler::Atom {
    handle.stop();
    atoms::ok()
}

// -------------------------------------------------------------------------------------------
// Presence Tracking
// -------------------------------------------------------------------------------------------

struct PresenceTracker {
    present: HashSet<String>,
    last_seen: HashMap<String, Instant>,
    suspect_since: HashMap<String, Instant>,
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

    fn clear_all(&mut self) {
        self.present.clear();
        self.last_seen.clear();
        self.suspect_since.clear();
        self.node_to_ble.clear();
    }

    fn record_sighting(&mut self, node_id: String, ble_addr: String) {
        self.last_seen.insert(node_id.clone(), Instant::now());
        self.suspect_since.remove(&node_id);
        self.node_to_ble.insert(node_id, ble_addr);
    }

    fn mark_present(&mut self, node_id: String) -> bool {
        self.present.insert(node_id)
    }

    fn mark_lost(&mut self, node_id: &str) {
        self.present.remove(node_id);
        self.last_seen.remove(node_id);
        self.suspect_since.remove(node_id);
        self.node_to_ble.remove(node_id);
    }

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
                self.suspect_since.remove(node_id);
                continue;
            }

            match self.suspect_since.get(node_id) {
                None => {
                    self.suspect_since.insert(node_id.clone(), now);
                }
                Some(&suspect_start) => {
                    if now.duration_since(suspect_start) > lost_grace {
                        to_lost.push(node_id.clone());
                    }
                }
            }
        }

        to_lost
    }
}

fn handle_presence_timeout(
    tracker: &mut PresenceTracker,
    pid: &LocalPid,
    lost_after: Duration,
    lost_grace: Duration,
) {
    let timed_out = tracker.get_timed_out_nodes(lost_after, lost_grace);

    for node_id in timed_out {
        tracker.mark_lost(&node_id);
        send_msg(pid, |env| (atoms::r2node_lost(), node_id).encode(env));
    }
}

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

    tracker.record_sighting(node_id.clone(), ble_address_str.clone());

    if tracker.mark_present(node_id.clone()) {
        send_msg(pid, |env| {
            let info = rustler::types::map::map_new(env)
                .map_put(
                    crate::atoms::name().encode(env),
                    device_info.name.encode(env),
                )
                .unwrap()
                .map_put(
                    crate::atoms::rssi().encode(env),
                    (device_info.rssi as i32).encode(env),
                )
                .unwrap()
                .map_put(
                    crate::atoms::address().encode(env),
                    ble_address_str.encode(env),
                )
                .unwrap()
                .map_put(
                    crate::atoms::hosting_priority().encode(env),
                    (device_info.hosting_priority as i32).encode(env),
                )
                .unwrap();

            (crate::atoms::r2node_found(), node_id, info).encode(env)
        });
    }

    Ok(())
}
