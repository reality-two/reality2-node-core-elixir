use bluer::{adv, Session};
use rustler::{Encoder, Env, NifResult, ResourceArc, Term};
use std::collections::BTreeMap;
use std::sync::Mutex;
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::atoms;
use crate::bluetooth::common::{get_or_default_adapter, ALTBEACON_CODE, DEFAULT_DEVICE_NAME};
use crate::bluetooth::resources::BeaconHandle;

// -------------------------------------------------------------------------------------------
// Constants (beacon-specific)
// -------------------------------------------------------------------------------------------

const STARTUP_TIMEOUT_SECS: u64 = 2;

// -------------------------------------------------------------------------------------------
// NIFs
// -------------------------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
pub fn start_altbeacon<'a>(
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
        Err(e) => return Ok((atoms::error(), format!("invalid_uuid: {e}")).encode(env)),
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
            Ok((atoms::ok(), handle).encode(env))
        }
        Ok(Err(reason)) => Ok((atoms::error(), reason).encode(env)),
        Err(_) => Ok((
            atoms::error(),
            "timeout_waiting_for_advertisement_start".to_string(),
        )
            .encode(env)),
    }
}

#[rustler::nif]
pub fn stop_altbeacon(handle: ResourceArc<BeaconHandle>) -> rustler::Atom {
    handle.stop();
    atoms::ok()
}

// -------------------------------------------------------------------------------------------
// Internals
// -------------------------------------------------------------------------------------------

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

    let _ = ready_tx.send(Ok(()));

    let _ = shutdown_rx.await;

    drop(adv_handle);
    Ok(())
}

fn build_altbeacon_payload(
    uuid: Uuid,
    major: u16,
    minor: u16,
    rssi_at_1m: i8,
    reserved: u8,
) -> Vec<u8> {
    let mut payload = Vec::with_capacity(24);

    payload.extend_from_slice(&ALTBEACON_CODE);
    payload.extend_from_slice(uuid.as_bytes());
    payload.extend_from_slice(&major.to_be_bytes());
    payload.extend_from_slice(&minor.to_be_bytes());
    payload.push(rssi_at_1m as u8);
    payload.push(reserved);

    payload
}
