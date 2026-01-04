use bluer::{DiscoveryFilter, DiscoveryTransport, Session};
use rustler::{Env, LocalPid, OwnedEnv, Term};
use uuid::Uuid;

use crate::bluetooth::types::Device;

// -------------------------------------------------------------------------------------------
// Shared constants
// -------------------------------------------------------------------------------------------

/// Default Company ID for R2 manufacturer data.
/// TODO: Replace with an assigned company ID.
pub const R2_COMPANY_ID: u16 = 0xFFFF;

/// Default device name when none is advertised.
pub const DEFAULT_DEVICE_NAME: &str = "R2 Node";

/// AltBeacon identifier bytes (first two bytes of manufacturer data).
pub const ALTBEACON_CODE: [u8; 2] = [0xBE, 0xAC];

/// Expected minimum length for AltBeacon manufacturer data payload.
pub const ALTBEACON_MIN_LENGTH: usize = 24;

// -------------------------------------------------------------------------------------------
// Shared helper functions
// -------------------------------------------------------------------------------------------

/// Gets the default Bluetooth adapter, or sets it to default hci0 if none exists (or returns an error)
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

/// Configure discovery filter to receive continuous RSSI updates.
pub async fn configure_rssi_discovery_filter(adapter: &bluer::Adapter) {
    let mut filter = DiscoveryFilter::default();
    filter.transport = DiscoveryTransport::Le;
    filter.rssi = Some(-127);

    if let Err(e) = adapter.set_discovery_filter(filter).await {
        eprintln!("set_discovery_filter failed (continuing): {e}");
    }
}

/// Checks whether the device is a Reality2 device.
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

    let Some(node_uuid) = extract_altbeacon_uuid(payload) else {
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
            name: device_name,
            id: node_id,
            rssi,
        },
    )))
}

/// Get the Reality2 Node UUID from an AltBeacon payload.
pub fn extract_altbeacon_uuid(payload: &[u8]) -> Option<Uuid> {
    if payload.len() < ALTBEACON_MIN_LENGTH {
        return None;
    }
    if payload[0] != ALTBEACON_CODE[0] || payload[1] != ALTBEACON_CODE[1] {
        return None;
    }
    Uuid::from_slice(&payload[2..18]).ok()
}

/// Send a message to an Elixir process using an OwnedEnv (thread-safe).
pub fn send_msg(pid: &LocalPid, term_builder: impl FnOnce(Env) -> Term) {
    let mut owned_env = OwnedEnv::new();
    let _ = owned_env.send_and_clear(pid, term_builder);
}
