use std::sync::Mutex;
use tokio::sync::oneshot;

/// Handle for continuous device discovery/monitoring.
pub struct WatchHandle {
    pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
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
