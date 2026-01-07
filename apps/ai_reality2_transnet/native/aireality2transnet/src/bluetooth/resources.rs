// use std::sync::Mutex;
// use tokio::sync::oneshot;

// /// Handle for continuous device discovery/monitoring.
// pub struct WatchHandle {
//     pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
//     pub(crate) reset_tx: Mutex<Option<tokio::sync::mpsc::UnboundedSender<ResetCommand>>>,
// }

// pub enum ResetCommand {
//     ClearAll,
// }

// impl WatchHandle {
//     pub fn stop(&self) {
//         if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
//             let _ = tx.send(());
//         }
//     }
// }

// impl Drop for WatchHandle {
//     fn drop(&mut self) {
//         self.stop();
//     }
// }

// /// Handle for AltBeacon advertising.
// pub struct BeaconHandle {
//     pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
// }

// impl BeaconHandle {
//     pub fn stop(&self) {
//         if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
//             let _ = tx.send(());
//         }
//     }
// }

// impl Drop for BeaconHandle {
//     fn drop(&mut self) {
//         self.stop();
//     }
// }

use std::sync::Mutex;
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

/// Handle for continuous device discovery/monitoring.
pub struct WatchHandle {
    pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
    pub(crate) reset_tx: Mutex<Option<mpsc::UnboundedSender<ResetCommand>>>,
}

pub enum ResetCommand {
    ClearAll,
}

impl WatchHandle {
    pub fn stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for WatchHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Handle for AltBeacon advertising.
pub struct BeaconHandle {
    pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl BeaconHandle {
    pub fn stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for BeaconHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Handle for GATT server.
pub struct GattServerHandle {
    pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
    pub(crate) write_tx: Mutex<Option<mpsc::UnboundedSender<(Uuid, Vec<u8>)>>>,
    pub(crate) notify_tx: Mutex<Option<mpsc::UnboundedSender<Vec<u8>>>>,
}

impl GattServerHandle {
    pub fn stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for GattServerHandle {
    fn drop(&mut self) {
        self.stop();
    }
}
