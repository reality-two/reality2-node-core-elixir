//! Bluetooth Module - BLE Operations for Reality2 Transient Networks
//!
//! This module contains all Bluetooth Low Energy (BLE) functionality for Reality2 node discovery
//! and communication. It's organized into focused submodules:
//!
//! ## Submodules
//!
//! - **beacon** - AltBeacon broadcasting for continuous presence advertisement
//! - **discovery** - BLE scanning to detect nearby Reality2 nodes
//! - **gatt** - GATT server for Android app and mesh coordination
//! - **common** - Shared utilities (adapter selection, constants)
//! - **resources** - Rust resource handles for Elixir lifecycle management
//! - **types** - Shared data structures and type definitions
//!
//! ## Design Philosophy
//!
//! **BLE is for discovery, WiFi is for data:**
//! - BLE: Low power, always-on, "who's nearby?"
//! - WiFi: High bandwidth, on-demand, "query sentants, send commands"
//!
//! ## Resource Management
//!
//! All long-running BLE operations (beacon, scan, GATT server) return resource handles
//! to Elixir. These handles provide graceful shutdown via oneshot channels and are
//! automatically cleaned up when garbage collected.

pub mod beacon;
pub mod common;
pub mod discovery;
pub mod gatt;
pub mod resources;
pub mod types;

// Re-export resource handle types so lib.rs can register them with Rustler
pub use resources::{BeaconHandle, GattServerHandle, WatchHandle};
