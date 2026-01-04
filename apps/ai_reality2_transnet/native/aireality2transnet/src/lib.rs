//! Rust NIF for BLE operations using BlueZ via `bluer`.
//!
//! Split into:
//! - bluetooth::beacon     (advertising / beaconing)
//! - bluetooth::discovery  (scan + watch/presence)

use rustler::{Env, Term};

mod bluetooth;

// -------------------------------------------------------------------------------------------
// Elixir atoms (shared across modules)
// -------------------------------------------------------------------------------------------
pub mod atoms {
    rustler::atoms! {
        ok,
        error,
        r2_ble_found,
        r2_ble_lost,
        name,
        rssi,
        address,
        r2_nodes,
        adapters,
    }
}

// -------------------------------------------------------------------------------------------
// NIF load: register Resource types (handles)
// -------------------------------------------------------------------------------------------
#[allow(non_local_definitions)]
fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(bluetooth::WatchHandle, env);
    let _ = rustler::resource!(bluetooth::BeaconHandle, env);
    true
}

// -------------------------------------------------------------------------------------------
// NIF init: expose functions (re-exported from bluetooth/mod.rs)
// -------------------------------------------------------------------------------------------
rustler::init!("Elixir.AiReality2Transnet.Action", load = load);
