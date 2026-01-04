pub mod beacon;
pub mod common;
pub mod discovery;
pub mod resources;
pub mod types;

// Re-export NIF functions so lib.rs can reference `bluetooth::fn_name`
// pub use beacon::{start_altbeacon, stop_altbeacon};
// pub use discovery::{list_adapters, scan_devices, start_r2_watch, stop_r2_watch};

// Re-export resource handle types so lib.rs can register them
pub use resources::{BeaconHandle, WatchHandle};
