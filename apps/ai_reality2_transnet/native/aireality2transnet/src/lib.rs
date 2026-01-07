// //! Rust NIF for BLE operations using BlueZ via `bluer`.
// //!
// //! Split into:
// //! - bluetooth::beacon     (advertising / beaconing)
// //! - bluetooth::discovery  (scan + watch/presence)

// use rustler::{Env, Term};

// mod bluetooth;

// // -------------------------------------------------------------------------------------------
// // Elixir atoms (shared across modules)
// // -------------------------------------------------------------------------------------------
// pub mod atoms {
//     rustler::atoms! {
//         ok,
//         error,
//         r2nodes,
//         r2node_found,
//         r2node_lost,
//         name,
//         rssi,
//         address,
//         adapters,
//         devices_cleared,
//     }
// }

// // -------------------------------------------------------------------------------------------
// // NIF load: register Resource types (handles)
// // -------------------------------------------------------------------------------------------
// #[allow(non_local_definitions)]
// fn load(env: Env, _info: Term) -> bool {
//     let _ = rustler::resource!(bluetooth::WatchHandle, env);
//     let _ = rustler::resource!(bluetooth::BeaconHandle, env);
//     true
// }

// // -------------------------------------------------------------------------------------------
// // NIF init: expose functions (re-exported from bluetooth/mod.rs)
// // -------------------------------------------------------------------------------------------
// rustler::init!("Elixir.AiReality2Transnet.Action", load = load);

//! Rust NIF for BLE operations using BlueZ via `bluer`.
//!
//! Split into:
//! - bluetooth::beacon     (advertising / beaconing)
//! - bluetooth::discovery  (scan + watch/presence)
//! - bluetooth::gatt       (GATT server and client)

use rustler::{Env, Term};

mod bluetooth;

// -------------------------------------------------------------------------------------------
// Elixir atoms (shared across modules)
// -------------------------------------------------------------------------------------------
pub mod atoms {
    rustler::atoms! {
        ok,
        error,
        r2nodes,
        r2node_found,
        r2node_lost,
        name,
        rssi,
        address,
        adapters,
        devices_cleared,
        // GATT atoms
        gatt_server_started,
        gatt_connected,
        gatt_write,
        gatt_read,
        gatt_write_success,
        gatt_services_discovered,
    }
}

// -------------------------------------------------------------------------------------------
// NIF load: register Resource types (handles)
// -------------------------------------------------------------------------------------------
#[allow(non_local_definitions)]
fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(bluetooth::WatchHandle, env);
    let _ = rustler::resource!(bluetooth::BeaconHandle, env);
    let _ = rustler::resource!(bluetooth::GattServerHandle, env);
    true
}

// -------------------------------------------------------------------------------------------
// NIF init: expose functions (re-exported from bluetooth/mod.rs)
// -------------------------------------------------------------------------------------------
rustler::init!("Elixir.AiReality2Transnet.Action", load = load);
