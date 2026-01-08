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

//! Reality2 Transient Networks - Rust NIF Module
//!
//! This Rust NIF provides low-level Bluetooth Low Energy (BLE) operations for the Reality2
//! transient networking system. It interfaces with Linux BlueZ via the `bluer` crate.
//!
//! ## Architecture Overview
//!
//! Reality2 uses a **hybrid Bluetooth + WiFi mesh approach** for transient peer-to-peer networking:
//!
//! 1. **BLE Discovery (Low Power)** - Always-on beacon broadcasting and scanning
//! 2. **WiFi Mesh (High Bandwidth)** - On-demand mesh networking for data transfer
//!
//! ```text
//! ┌────────────────────────────────────────────────────────┐
//! │         BLE Layer (Rust NIF - This Module)             │
//! │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
//! │  │   Beacon     │  │  Discovery   │  │     GATT     │ │
//! │  │ (Advertise)  │  │   (Scan)     │  │   (Server)   │ │
//! │  └──────────────┘  └──────────────┘  └──────────────┘ │
//! └────────────────────────────────────────────────────────┘
//!                           ↓
//! ┌────────────────────────────────────────────────────────┐
//! │      WiFi Mesh Layer (Pure Elixir - wifi.ex)          │
//! │  - IEEE 802.11s mesh networking                        │
//! │  - GraphQL-based Sentant queries                       │
//! │  - No size limits, full bandwidth                      │
//! └────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Bluetooth Module Structure
//!
//! ### `bluetooth::beacon`
//! - AltBeacon protocol broadcasting
//! - Continuous presence advertisement
//! - Low power consumption
//! - **Use case:** "I'm here, here's my node ID"
//!
//! ### `bluetooth::discovery`
//! - BLE device scanning
//! - Presence detection (node appeared/disappeared)
//! - RSSI-based proximity
//! - **Use case:** "Who's nearby?"
//!
//! ### `bluetooth::gatt`
//! - GATT server for Android app communication
//! - Minimal mesh coordination info
//! - **Use case:** "Here's my WiFi mesh details" (not for Sentant data!)
//!
//! ### `bluetooth::common`
//! - Shared utilities (adapter selection, constants)
//!
//! ### `bluetooth::resources`
//! - Rust resource handles for Elixir lifecycle management
//!
//! ### `bluetooth::types`
//! - Shared data structures
//!
//! ## Why Rust for BLE?
//!
//! - **Performance:** Compiled, async, zero-cost abstractions
//! - **BlueZ Integration:** `bluer` crate provides robust DBus bindings
//! - **Event Handling:** Tokio for efficient async event streams
//! - **Type Safety:** Strong typing prevents protocol errors
//!
//! ## Why Elixir for WiFi?
//!
//! - **Simplicity:** Just shell out to `iw` and `ip` commands
//! - **Linux Integration:** Kernel's 802.11s stack does the heavy lifting
//! - **No Overhead:** WiFi mesh is standard, no custom protocol needed
//!
//! ## Calling from Elixir
//!
//! All functions are exposed via `AiReality2Transnet.Action` module:
//!
//! ```elixir
//! # Start beacon
//! {:ok, beacon} = AiReality2Transnet.Action.start_broadcast(...)
//!
//! # Start discovery
//! {:ok, watch} = AiReality2Transnet.Action.start_watch(...)
//!
//! # Start GATT server
//! {:ok, gatt} = AiReality2Transnet.Action.start_gatt_server(...)
//! ```

use rustler::{Env, Term};

mod bluetooth;

// -------------------------------------------------------------------------------------------
// Elixir Atoms (Shared Across Modules)
// -------------------------------------------------------------------------------------------
//
// These atoms are used for return values from NIFs to Elixir.
// Rustler automatically generates atom constants at compile time.
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
