// needs cmake, pkg-config, libdbus-1-dev and rust installed

use bluer::{adv, AdapterEvent, Session};
use futures::StreamExt;
use rustler::{Atom, Encoder, Env, LocalPid, NifResult, OwnedEnv, ResourceArc, Term};
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::sync::Mutex;
use tokio::sync::oneshot;
use tokio::time::Duration;
use uuid::Uuid;

rustler::atoms! {
    ok,
    error
}

// -----------------------------------------------------------------------------------------------------------------------------------------
// List the bluetooth adapters
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
            .map_err(|e| format!("adapter_names_failed: {e}"))?; // lists e.g. ["hci0", ...] :contentReference[oaicite:3]{index=3}

        let mut out = Vec::with_capacity(names.len());
        for name in names {
            let adapter = session
                .adapter(&name)
                .map_err(|e| format!("adapter_open_failed({name}): {e}"))?; // non-async :contentReference[oaicite:4]{index=4}

            let addr = adapter
                .address()
                .await
                .map_err(|e| format!("adapter_address_failed({name}): {e}"))?; // async :contentReference[oaicite:5]{index=5}

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

fn extract_altbeacon_uuid(mfg_value: &[u8]) -> Option<Uuid> {
    // mfg_value layout (your payload):
    // [0..2]=0xBEAC, [2..18]=UUID(16), [18..20]=major, [20..22]=minor, [22]=rssi, [23]=reserved
    if mfg_value.len() < 24 {
        return None;
    }
    if mfg_value[0] != 0xBE || mfg_value[1] != 0xAC {
        return None;
    }
    Uuid::from_slice(&mfg_value[2..18]).ok()
}

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

// #[rustler::nif]
// fn scan_devices(env: Env, pid: LocalPid, timeout_ms: i32) -> Term {
//     let _ = std::thread::spawn(move || {
//         let mut owned_env = OwnedEnv::new();

//         let rt = tokio::runtime::Builder::new_current_thread()
//             .enable_all()
//             .build()
//             .expect("tokio runtime build failed");

//         let result: Result<Vec<Device>, String> = rt.block_on(async move {
//             let session = Session::new()
//                 .await
//                 .map_err(|e| format!("session_new_failed: {e}"))?;

//             // Prefer hci0 if present; otherwise first adapter.
//             let names = session
//                 .adapter_names()
//                 .await
//                 .map_err(|e| format!("adapter_names_failed: {e}"))?;

//             let chosen = names
//                 .iter()
//                 .find(|n| n.as_str() == "hci0")
//                 .cloned()
//                 .or_else(|| names.first().cloned())
//                 .ok_or_else(|| "No adapters found".to_string())?;

//             let adapter = session
//                 .adapter(&chosen)
//                 .map_err(|e| format!("adapter_open_failed({chosen}): {e}"))?;

//             adapter
//                 .set_powered(true)
//                 .await
//                 .map_err(|e| format!("set_powered_failed: {e}"))?;

//             let timeout_ms = timeout_ms.max(0) as u64;
//             let mut seen: HashMap<String, Device> = HashMap::new();

//             // Use "with_changes" so you get follow-up DeviceAdded events when properties (like RSSI/name) update.
//             // This is helpful because BlueZ may not have resolved properties at the instant the device is first seen.
//             {
//                 let discover = adapter
//                     .discover_devices_with_changes()
//                     .await
//                     .map_err(|e| format!("discover_devices_failed: {e}"))?;
//                 futures::pin_mut!(discover);

//                 let deadline = tokio::time::sleep(Duration::from_millis(timeout_ms));
//                 tokio::pin!(deadline);

//                 loop {
//                     tokio::select! {
//                         _ = &mut deadline => break,
//                         evt = discover.next() => {
//                             match evt {
//                                 Some(AdapterEvent::DeviceAdded(addr)) => {
//                                     let device = adapter
//                                         .device(addr)
//                                         .map_err(|e| format!("device_open_failed({addr}): {e}"))?;

//                                     let name = device
//                                         .name()
//                                         .await
//                                         .map_err(|e| format!("device_name_failed({addr}): {e}"))?
//                                         .unwrap_or_else(|| "Unknown".to_string());

//                                     let rssi = device
//                                         .rssi()
//                                         .await
//                                         .map_err(|e| format!("device_rssi_failed({addr}): {e}"))?
//                                         .unwrap_or(0);

//                                     let address = addr.to_string();
//                                     seen.insert(address.clone(), Device { name, address, rssi });
//                                 }
//                                 Some(AdapterEvent::DeviceRemoved(addr)) => {
//                                     seen.remove(&addr.to_string());
//                                 }
//                                 Some(_) => {}
//                                 None => break,
//                             }
//                         }
//                     }
//                 }
//                 // Dropping `discover` ends the discovery session.
//             }

//             Ok(seen.into_values().collect())
//         });

//         let _ = owned_env.send_and_clear(&pid, |env| match result {
//             Ok(devices) => (rustler::types::atom::ok(), devices).encode(env),
//             Err(err) => (rustler::types::atom::error(), err).encode(env),
//         });
//     });

//     rustler::types::atom::ok().encode(env)
// }
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// AltBeacon advertising via BlueZ D-Bus (bluer)
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Beacon Handle
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
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Build the BLE Beacon Payload (AltBeacon format)
// -----------------------------------------------------------------------------------------------------------------------------------------
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
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Start the BLE Beacon
// -----------------------------------------------------------------------------------------------------------------------------------------
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
// -----------------------------------------------------------------------------------------------------------------------------------------

// -----------------------------------------------------------------------------------------------------------------------------------------
// Stop the BLE beacon
// -----------------------------------------------------------------------------------------------------------------------------------------

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
    rustler::resource!(BeaconHandle, env)
}

rustler::init!("Elixir.AiReality2Transnet.Action", load = load);
