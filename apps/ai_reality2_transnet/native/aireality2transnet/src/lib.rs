use bluer::{adv, AdapterEvent, DiscoveryFilter, DiscoveryTransport, Session};

use futures::StreamExt;
use rustler::{Atom, Encoder, Env, LocalPid, NifResult, OwnedEnv, ResourceArc, Term};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Mutex;
use tokio::sync::oneshot;
use tokio::time::{self, Duration, Instant};
use uuid::Uuid;

rustler::atoms! {
    ok,
    error,
    r2_ble_found,
    r2_ble_lost,
    name,
    rssi,
    ble_addr
}

// -----------------------------------------------------------------------------------------------------------------------------------------
// WatchHandle (continuous discovery watcher)
// -----------------------------------------------------------------------------------------------------------------------------------------

struct WatchHandle {
    shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl WatchHandle {
    fn stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for WatchHandle {
    fn drop(&mut self) {
        if let Ok(mut guard) = self.shutdown_tx.lock() {
            if let Some(tx) = guard.take() {
                let _ = tx.send(());
            }
        }
    }
}

// -----------------------------------------------------------------------------------------------------------------------------------------
// Adapter listing (bluer)
// -----------------------------------------------------------------------------------------------------------------------------------------

#[derive(rustler::NifMap)]
pub struct Adapters {
    pub id: String,
    pub address: String,
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_adapters() -> Vec<Adapters> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("tokio runtime");

    let res: Result<Vec<Adapters>, String> = rt.block_on(async {
        let session = Session::new()
            .await
            .map_err(|e| format!("session_new_failed: {e}"))?;

        let names = session
            .adapter_names()
            .await
            .map_err(|e| format!("adapter_names_failed: {e}"))?;

        let mut out = Vec::with_capacity(names.len());
        for name in names {
            let adapter = session
                .adapter(&name)
                .map_err(|e| format!("adapter_open_failed({name}): {e}"))?;

            let addr = adapter
                .address()
                .await
                .map_err(|e| format!("adapter_address_failed({name}): {e}"))?;

            out.push(Adapters {
                id: name,
                address: addr.to_string(),
            });
        }

        Ok(out)
    });

    match res {
        Ok(v) => v,
        Err(e) => {
            eprintln!("list_adapters(bluer) error: {e}");
            vec![]
        }
    }
}
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Scan for BLE devices nearby
// -----------------------------------------------------------------------------------------------------------------------------------------
#[derive(rustler::NifMap)]
pub struct Device {
    pub name: String,
    pub address: String,
    pub rssi: i16,
}

const R2_COMPANY_ID: u16 = 0xFFFF; // change when you have a real company id

#[rustler::nif]
fn scan_devices(env: Env, pid: LocalPid, timeout_ms: i32) -> Term {
    let _ = std::thread::spawn(move || {
        let mut owned_env = OwnedEnv::new();

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime build failed");

        let result: Result<Vec<Device>, String> = rt.block_on(async move {
            let session = Session::new()
                .await
                .map_err(|e| format!("session_new_failed: {e}"))?;

            let names = session
                .adapter_names()
                .await
                .map_err(|e| format!("adapter_names_failed: {e}"))?;

            let chosen = names
                .iter()
                .find(|n| n.as_str() == "hci0")
                .cloned()
                .or_else(|| names.first().cloned())
                .ok_or_else(|| "No adapters found".to_string())?;

            let adapter = session
                .adapter(&chosen)
                .map_err(|e| format!("adapter_open_failed({chosen}): {e}"))?;

            adapter
                .set_powered(true)
                .await
                .map_err(|e| format!("set_powered_failed: {e}"))?;

            let timeout_ms = timeout_ms.max(0) as u64;

            // Keyed by node GUID (string)
            let mut seen: HashMap<String, Device> = HashMap::new();
            // Map BLE addr -> node GUID so we can handle DeviceRemoved cleanly
            let mut ble_to_node: HashMap<String, String> = HashMap::new();

            let discover = adapter
                .discover_devices_with_changes()
                .await
                .map_err(|e| format!("discover_devices_failed: {e}"))?;
            futures::pin_mut!(discover);

            let deadline = tokio::time::sleep(Duration::from_millis(timeout_ms));
            tokio::pin!(deadline);

            loop {
                tokio::select! {
                    _ = &mut deadline => break,
                    evt = discover.next() => {
                        match evt {
                            Some(AdapterEvent::DeviceAdded(addr)) => {
                                let ble_addr = addr.to_string();

                                let device = adapter
                                    .device(addr)
                                    .map_err(|e| format!("device_open_failed({ble_addr}): {e}"))?;

                                // Manufacturer data is what we use to detect AltBeacon + extract Node GUID.
                                let mfg = device
                                    .manufacturer_data()
                                    .await
                                    .map_err(|e| format!("device_manufacturer_data_failed({ble_addr}): {e}"))?;

                                let Some(mfg) = mfg else {
                                    continue;
                                };

                                let Some(value) = mfg.get(&R2_COMPANY_ID) else {
                                    continue; // not our beacon (or different company id)
                                };

                                let Some(node_uuid) = extract_altbeacon_uuid(value) else {
                                    continue; // not AltBeacon (or malformed)
                                };

                                let node_id = node_uuid.to_string();

                                let name = device
                                    .name()
                                    .await
                                    .map_err(|e| format!("device_name_failed({ble_addr}): {e}"))?
                                    .unwrap_or_else(|| "R2 Node".to_string());

                                let rssi = device
                                    .rssi()
                                    .await
                                    .map_err(|e| format!("device_rssi_failed({ble_addr}): {e}"))?
                                    .unwrap_or(0);

                                seen.insert(node_id.clone(), Device {
                                    name,
                                    address: node_id.clone(), // <-- Node GUID in your struct
                                    rssi,
                                });

                                ble_to_node.insert(ble_addr, node_id);
                            }

                            Some(AdapterEvent::DeviceRemoved(addr)) => {
                                let ble_addr = addr.to_string();
                                if let Some(node_id) = ble_to_node.remove(&ble_addr) {
                                    seen.remove(&node_id);
                                }
                            }

                            Some(_) => {}
                            None => break,
                        }
                    }
                }
            }

            Ok(seen.into_values().collect())
        });

        let _ = owned_env.send_and_clear(&pid, |env| match result {
            Ok(devices) => (rustler::types::atom::ok(), devices).encode(env),
            Err(err) => (rustler::types::atom::error(), err).encode(env),
        });
    });

    rustler::types::atom::ok().encode(env)
}
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Common helpers (AltBeacon parsing + Rust->Elixir message send)
// -----------------------------------------------------------------------------------------------------------------------------------------

// AltBeacon manufacturer payload layout (value part):
// [0..2]=0xBEAC, [2..18]=UUID(16), [18..20]=major, [20..22]=minor, [22]=rssi@1m, [23]=reserved
fn extract_altbeacon_uuid(mfg_value: &[u8]) -> Option<Uuid> {
    if mfg_value.len() < 24 {
        return None;
    }
    if mfg_value[0] != 0xBE || mfg_value[1] != 0xAC {
        return None;
    }
    Uuid::from_slice(&mfg_value[2..18]).ok()
}

fn send_msg(pid: &LocalPid, term_builder: impl FnOnce(Env) -> Term) {
    let mut oenv = OwnedEnv::new();
    let _ = oenv.send_and_clear(pid, |env| term_builder(env));
}
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Continuous watcher: emits {:r2_ble_found, node_id, info_map} / {:r2_ble_lost, node_id}
// -----------------------------------------------------------------------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
fn start_r2_watch<'a>(
    env: Env<'a>,
    pid: LocalPid,
    company_id: u16,
    adapter_name: Option<String>,
    lost_after_ms: u64,
) -> NifResult<Term<'a>> {
    let (shutdown_tx, mut shutdown_rx) = oneshot::channel::<()>();

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

        let ready_tx_err = ready_tx.clone();

        let res: Result<(), String> = rt.block_on(async move {
            let session = Session::new()
                .await
                .map_err(|e| format!("session_new_failed: {e}"))?;

            let adapter = if let Some(name) = adapter_name.as_deref() {
                session
                    .adapter(name)
                    .map_err(|e| format!("adapter_open_failed({name}): {e}"))?
            } else {
                session
                    .default_adapter()
                    .await
                    .map_err(|e| format!("default_adapter_failed: {e}"))?
            };

            adapter
                .set_powered(true)
                .await
                .map_err(|e| format!("set_powered_failed: {e}"))?;

            // Key trick: set an RSSI discovery filter so BlueZ emits RSSI updates for existing devices
            // and disables the default RSSI delta-threshold. This makes `discover_devices_with_changes`
            // generate repeated DeviceAdded events as RSSI updates come in. :contentReference[oaicite:2]{index=2}
            let mut filter = DiscoveryFilter::default();
            filter.transport = DiscoveryTransport::Le;
            filter.rssi = Some(-127); // accept everything, but forces RSSI updates
            // duplicate_data is already true by default per docs, but leaving default is fine. :contentReference[oaicite:3]{index=3}

            if let Err(e) = adapter.set_discovery_filter(filter).await {
                // Don’t fail the watch if another client has discovery running; just log.
                eprintln!("set_discovery_filter failed (continuing): {e}");
            }

            let lost_after = Duration::from_millis(lost_after_ms.max(30_000));
            let lost_grace = Duration::from_millis(5_000); // hysteresis to prevent single-gap flaps
            let mut tick = time::interval(Duration::from_millis(500));

            // Present keyed by node UUID string
            let mut present: HashSet<String> = HashSet::new();
            let mut last_seen: HashMap<String, Instant> = HashMap::new();
            let mut suspect_since: HashMap<String, Instant> = HashMap::new();

            // Optional: keep last BLE addr for info/debug
            let mut node_to_ble: HashMap<String, String> = HashMap::new();

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

                        _ = tick.tick() => {
                            let now = Instant::now();

                            // Mark suspects; only emit lost after both lost_after AND lost_grace.
                            let mut to_lost = Vec::new();
                            for node_id in present.iter() {
                                let Some(ts) = last_seen.get(node_id) else { continue; };
                                let overdue = now.duration_since(*ts) > lost_after;
                                if !overdue {
                                    suspect_since.remove(node_id);
                                    continue;
                                }

                                match suspect_since.get(node_id) {
                                    None => { suspect_since.insert(node_id.clone(), now); }
                                    Some(since) => {
                                        if now.duration_since(*since) > lost_grace {
                                            to_lost.push(node_id.clone());
                                        }
                                    }
                                }
                            }

                            for node_id in to_lost {
                                present.remove(&node_id);
                                last_seen.remove(&node_id);
                                suspect_since.remove(&node_id);
                                node_to_ble.remove(&node_id);
                                send_msg(&pid, |env| (r2_ble_lost(), node_id).encode(env));
                            }
                        }

                        evt = discover.next() => {
                            match evt {
                                Some(AdapterEvent::DeviceAdded(addr)) => {
                                    let ble_addr_str = addr.to_string();

                                    let dev = adapter
                                        .device(addr)
                                        .map_err(|e| format!("device_open_failed({ble_addr_str}): {e}"))?;

                                    let mfg = dev
                                        .manufacturer_data()
                                        .await
                                        .map_err(|e| format!("manufacturer_data_failed({ble_addr_str}): {e}"))?;

                                    let Some(mfg) = mfg else { continue; };
                                    let Some(value) = mfg.get(&company_id) else { continue; };

                                    let Some(node_uuid) = extract_altbeacon_uuid(value) else { continue; };
                                    let node_id = node_uuid.to_string();

                                    // Guard against cached devices: RSSI indicates "currently present". :contentReference[oaicite:4]{index=4}
                                    let rssi_now = match dev.rssi().await
                                        .map_err(|e| format!("rssi_failed({ble_addr_str}): {e}"))?
                                    {
                                        Some(r) => r,
                                        None => continue,
                                    };

                                    let dev_name = dev
                                        .name()
                                        .await
                                        .map_err(|e| format!("name_failed({ble_addr_str}): {e}"))?
                                        .unwrap_or_else(|| "R2 Node".to_string());

                                    // Refresh liveness on *every* matching event, not just first sighting
                                    last_seen.insert(node_id.clone(), Instant::now());
                                    suspect_since.remove(&node_id);
                                    node_to_ble.insert(node_id.clone(), ble_addr_str.clone());

                                    if present.insert(node_id.clone()) {
                                        send_msg(&pid, |env| {
                                            let info =
                                                rustler::types::map::map_new(env)
                                                    .map_put(name().encode(env), dev_name.encode(env)).unwrap()
                                                    .map_put(rssi().encode(env), (rssi_now as i32).encode(env)).unwrap()
                                                    .map_put(ble_addr().encode(env), ble_addr_str.encode(env)).unwrap();

                                            (r2_ble_found(), node_id, info).encode(env)
                                        });
                                    }
                                }

                                Some(AdapterEvent::DeviceRemoved(_addr)) => {
                                    // Do NOT treat this as “lost” for proximity; rely on last_seen + timeout.
                                    // BlueZ can remove device objects for reasons unrelated to RF presence.
                                }

                                Some(AdapterEvent::PropertyChanged(_)) => { /* ignore */ }

                                None => break, // stream ended; restart
                            }
                        }
                    }
                }

                time::sleep(Duration::from_millis(200)).await;
            }
        });

        if let Err(e) = res {
            let _ = ready_tx_err.send(Err(e));
        }
    });

    match ready_rx.recv_timeout(std::time::Duration::from_secs(2)) {
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

#[rustler::nif]
fn stop_r2_watch(handle: ResourceArc<WatchHandle>) -> Atom {
    handle.stop();
    ok()
}
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// AltBeacon advertising (bluer)
// -----------------------------------------------------------------------------------------------------------------------------------------

struct BeaconHandle {
    shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl BeaconHandle {
    fn stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for BeaconHandle {
    fn drop(&mut self) {
        if let Ok(mut guard) = self.shutdown_tx.lock() {
            if let Some(tx) = guard.take() {
                let _ = tx.send(());
            }
        }
    }
}

// AltBeacon manufacturer payload (value part) = 0xBEAC + UUID(16) + major(2) + minor(2) + rssi + reserved
fn build_altbeacon_payload(
    uuid: Uuid,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    reserved: u8,
) -> Vec<u8> {
    let mut v = Vec::with_capacity(2 + 20 + 1 + 1);
    v.extend_from_slice(&[0xBE, 0xAC]); // Beacon Code
    v.extend_from_slice(uuid.as_bytes()); // 16 bytes
    v.extend_from_slice(&major.to_be_bytes());
    v.extend_from_slice(&minor.to_be_bytes());
    v.push(rssi_at_1m as u8);
    v.push(reserved);
    v
}

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

        let ready_tx_err = ready_tx.clone();

        let res: Result<(), String> = rt.block_on(async move {
            let payload = build_altbeacon_payload(uuid, major, minor, rssi_at_1m, 0x00);
            let mut mfg: BTreeMap<u16, Vec<u8>> = BTreeMap::new();
            mfg.insert(company_id, payload);

            let session = Session::new()
                .await
                .map_err(|e| format!("session_new_failed: {e}"))?;

            let adapter = if let Some(name) = adapter_name.as_deref() {
                session
                    .adapter(name)
                    .map_err(|e| format!("adapter_open_failed({name}): {e}"))?
            } else {
                session
                    .default_adapter()
                    .await
                    .map_err(|e| format!("default_adapter_failed: {e}"))?
            };

            adapter
                .set_powered(true)
                .await
                .map_err(|e| format!("set_powered_failed: {e}"))?;

            // NOTE:
            // - AltBeacon is usually broadcast/non-connectable, but you can choose Peripheral if you
            //   intend to accept GATT connections. Keeping a local_name may push payload into extended
            //   advertising depending on controller capabilities.
            let ad = adv::Advertisement {
                advertisement_type: adv::Type::Peripheral,
                discoverable: Some(true),
                local_name: Some("R2 node".to_string()),
                manufacturer_data: mfg,
                ..Default::default()
            };

            let adv_handle = adapter
                .advertise(ad)
                .await
                .map_err(|e| format!("advertise_failed: {e}"))?;

            let _ = ready_tx.send(Ok(()));
            let _ = shutdown_rx.await;

            drop(adv_handle);
            Ok::<(), String>(())
        });

        if let Err(e) = res {
            let _ = ready_tx_err.send(Err(e));
        }
    });

    match ready_rx.recv_timeout(std::time::Duration::from_secs(2)) {
        Ok(Ok(())) => {
            let res = ResourceArc::new(BeaconHandle {
                shutdown_tx: Mutex::new(Some(shutdown_tx)),
            });
            Ok((ok(), res).encode(env))
        }
        Ok(Err(reason)) => Ok((error(), reason).encode(env)),
        Err(_) => Ok((
            error(),
            "timeout_waiting_for_advertisement_start".to_string(),
        )
            .encode(env)),
    }
}

#[rustler::nif]
fn stop_altbeacon(handle: ResourceArc<BeaconHandle>) -> Atom {
    handle.stop();
    ok()
}
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Rustler resource registration + init
// -----------------------------------------------------------------------------------------------------------------------------------------

#[allow(non_local_definitions)]
fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(WatchHandle, env);
    let _ = rustler::resource!(BeaconHandle, env);
    true
}

rustler::init!("Elixir.AiReality2Transnet.Action", load = load);
