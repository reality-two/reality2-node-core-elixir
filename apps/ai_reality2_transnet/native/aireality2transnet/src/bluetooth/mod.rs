pub mod beacon;
pub mod common;
pub mod discovery;
pub mod gatt;
pub mod resources;
pub mod types;

// Re-export resource handle types so lib.rs can register them
pub use resources::{BeaconHandle, GattServerHandle, WatchHandle};
