//! Resource Handles for BLE Operations
//!
//! This module defines Rust resource handles that are passed to Elixir for managing
//! long-running BLE operations (beacon, discovery, GATT server). These handles provide:
//!
//! 1. **Lifecycle Management** - Elixir can explicitly stop operations
//! 2. **Automatic Cleanup** - Resources are stopped when garbage collected (Drop trait)
//! 3. **Thread Safety** - Safe to pass between BEAM scheduler and Rust threads
//!
//! ## Architecture
//!
//! ```text
//! Elixir Process          Rust NIF                  Background Thread
//! ┌──────────────┐        ┌──────────────┐          ┌──────────────┐
//! │              │        │              │          │              │
//! │ start_watch()├───────>│ WatchHandle  ├─────────>│ Tokio Task   │
//! │              │<───────┤ (Resource)   │          │ (async)      │
//! │              │        │              │          │              │
//! │ stop_watch() ├───────>│ shutdown_tx  ├─────────>│ Shutdown     │
//! │              │        │  .send(())   │          │              │
//! └──────────────┘        └──────────────┘          └──────────────┘
//!                                                            │
//!                         GC triggered                       │
//!                                ↓                           │
//!                         Drop::drop()                       │
//!                                ↓                           ↓
//!                         Auto shutdown ────────────> Task stops
//! ```
//!
//! ## Why Oneshot Channels?
//!
//! - **Shutdown signals** use `oneshot::Sender<()>` because:
//!   - Only need to send shutdown signal once
//!   - No data needs to be sent (just the signal itself)
//!   - Lightweight and efficient
//!   - Receiver can be `.await`ed until signal arrives
//!
//! ## Why Unbounded Channels?
//!
//! - **Command channels** use `mpsc::UnboundedSender` because:
//!   - Multiple commands might be queued
//!   - We don't want to block Elixir if queue is full
//!   - Commands are rare (not high-frequency data)
//!
//! ## Thread Safety
//!
//! All fields wrapped in `Mutex<Option<T>>`:
//! - `Mutex` - Safe to access from multiple threads (BEAM scheduler + Rust threads)
//! - `Option` - Can be "taken" once, preventing double-send on channels
//!
//! ## Resource Lifecycle
//!
//! 1. **Creation**: NIF returns `ResourceArc<Handle>` to Elixir
//! 2. **Usage**: Elixir holds reference, can call methods
//! 3. **Explicit Stop**: Elixir calls `stop()` to shutdown cleanly
//! 4. **Automatic Cleanup**: When Elixir GC collects, `Drop::drop()` is called
//! 5. **Background Shutdown**: Background tasks receive shutdown signal and exit

use std::sync::Mutex;
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

// -------------------------------------------------------------------------------------------
// Watch Handle - Device Discovery/Monitoring
// -------------------------------------------------------------------------------------------

/// Resource handle for continuous BLE device discovery and monitoring
///
/// This handle manages a background Tokio task that continuously scans for BLE devices
/// and reports discoveries to the Elixir process. The task runs until explicitly stopped
/// or the handle is garbage collected.
///
/// ## Channels
///
/// - `shutdown_tx` - Oneshot channel to signal task shutdown
/// - `reset_tx` - Unbounded channel to send reset commands (e.g., clear device cache)
///
/// ## Lifecycle
///
/// ```text
/// start_watch() -> WatchHandle -> Background Task (scanning...)
///                                         ↓
///                                   Reports devices
///                                         ↓
/// stop_watch()  -> shutdown signal -> Task exits
///       OR
/// GC triggered  -> Drop::drop()    -> shutdown signal -> Task exits
/// ```
///
/// ## Usage from Elixir
///
/// ```elixir
/// # Start watching
/// {:ok, handle} = Reality2Transnet.Action.start_watch(self(), "hci0")
///
/// # Receive discovery events
/// receive do
///   {:r2node_found, node_id, info} -> ...
///   {:r2node_lost, node_id} -> ...
/// end
///
/// # Stop watching
/// :ok = Reality2Transnet.Action.stop_watch(handle)
/// ```
pub struct WatchHandle {
    /// Oneshot sender for shutdown signal - taken once when stopping
    pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,

    /// Unbounded sender for reset commands - can send multiple commands
    pub(crate) reset_tx: Mutex<Option<mpsc::UnboundedSender<ResetCommand>>>,
}

/// Commands that can be sent to the watch task
pub enum ResetCommand {
    /// Clear all tracked devices and restart discovery fresh
    ClearAll,
    /// Pause BLE scanning (to allow GATT client connections on the same adapter)
    Pause,
    /// Resume BLE scanning after a pause
    Resume,
}

impl WatchHandle {
    /// Explicitly stops the discovery task
    ///
    /// Sends a shutdown signal to the background Tokio task, causing it to exit gracefully.
    /// This is idempotent - calling multiple times is safe (subsequent calls are no-ops).
    ///
    /// ## Thread Safety
    ///
    /// Can be called from any thread. The `Mutex` ensures exclusive access to the channel.
    pub fn stop(&self) {
        // Try to take the shutdown sender (will be None if already taken)
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            // Send shutdown signal (ignore errors - task might already be stopped)
            let _ = tx.send(());
        }
    }

    /// Sends a command to the watch task without stopping it.
    ///
    /// Used for Pause/Resume/ClearAll operations. Unlike `stop()`, this can be
    /// called multiple times since it borrows (not takes) the channel sender.
    pub fn send_command(&self, cmd: ResetCommand) {
        if let Some(tx) = self.reset_tx.lock().unwrap().as_ref() {
            let _ = tx.send(cmd);
        }
    }
}

impl Drop for WatchHandle {
    /// Automatically stops the task when handle is garbage collected
    ///
    /// This ensures that background tasks are always cleaned up, even if Elixir code
    /// doesn't explicitly call `stop()`. When the Elixir VM garbage collects this
    /// resource, Rust's Drop trait runs and gracefully shuts down the background task.
    fn drop(&mut self) {
        self.stop();
    }
}

// -------------------------------------------------------------------------------------------
// Beacon Handle - AltBeacon Advertising
// -------------------------------------------------------------------------------------------

/// Resource handle for continuous AltBeacon advertising
///
/// This handle manages a background Tokio task that continuously broadcasts an AltBeacon
/// via BLE advertising. The beacon announces this node's presence to nearby devices.
///
/// ## Channels
///
/// - `shutdown_tx` - Oneshot channel to signal task shutdown
///
/// ## Lifecycle
///
/// ```text
/// start_broadcast() -> BeaconHandle -> Background Task (advertising...)
///                                              ↓
///                                      Broadcasts beacon
///                                              ↓
/// stop_broadcast()  -> shutdown signal -> Task exits, advertising stops
///       OR
/// GC triggered      -> Drop::drop()    -> shutdown signal -> Task exits
/// ```
///
/// ## Usage from Elixir
///
/// ```elixir
/// # Start beacon
/// {:ok, handle} = Reality2Transnet.Action.start_broadcast(
///   0xFFFF,                                      # Company ID
///   "550e8400-e29b-41d4-a716-446655440000",      # Node UUID
///   1, 100, -59,                                 # Major, minor, RSSI
///   "hci0"                                       # Adapter
/// )
///
/// # Beacon is now broadcasting continuously...
///
/// # Stop beacon
/// :ok = Reality2Transnet.Action.stop_broadcast(handle)
/// ```
pub struct BeaconHandle {
    /// Oneshot sender for shutdown signal - taken once when stopping
    pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl BeaconHandle {
    /// Explicitly stops the beacon advertising
    ///
    /// Sends a shutdown signal to the background Tokio task, causing it to stop advertising
    /// and exit gracefully. This is idempotent - calling multiple times is safe.
    ///
    /// ## Thread Safety
    ///
    /// Can be called from any thread. The `Mutex` ensures exclusive access to the channel.
    pub fn stop(&self) {
        // Try to take the shutdown sender (will be None if already taken)
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            // Send shutdown signal (ignore errors - task might already be stopped)
            let _ = tx.send(());
        }
    }
}

impl Drop for BeaconHandle {
    /// Automatically stops advertising when handle is garbage collected
    ///
    /// This ensures beacon advertising is always stopped, even if Elixir code doesn't
    /// explicitly call `stop()`. Prevents "ghost beacons" from continuing to advertise
    /// after the Elixir process exits.
    fn drop(&mut self) {
        self.stop();
    }
}

// -------------------------------------------------------------------------------------------
// GATT Server Handle - Android App Communication
// -------------------------------------------------------------------------------------------

/// Resource handle for GATT server operation
///
/// This handle manages a background Tokio task that runs a GATT (Generic Attribute Profile)
/// server, allowing Android apps to connect and interact with this Reality2 node via BLE.
///
/// ## GATT Server Purpose
///
/// The GATT server provides minimal coordination information for transient networking:
/// - **Node Info** - Node UUID, capabilities, Sentant count
/// - **Mesh Details** - WiFi mesh ID, IPv6 address, HTTP port
/// - **Mesh Commands** - Instructions to join WiFi mesh
///
/// **Note:** GATT is NOT used for Sentant data transfer (that's done via WiFi mesh HTTP).
/// GATT is only for discovery and mesh coordination.
///
/// ## Channels
///
/// - `shutdown_tx` - Oneshot channel to signal server shutdown
/// - `write_tx` - Unbounded channel for GATT write notifications (client → server)
/// - `notify_tx` - Unbounded channel for GATT value notifications (server → client)
///
/// ## Lifecycle
///
/// ```text
/// start_gatt_server() -> GattServerHandle -> Background Task (GATT server...)
///                                                     ↓
///                                             Accepts connections
///                                                     ↓
/// Client writes → write_tx → Elixir process handles write
/// Server notifies → notify_tx → Sends notification to client
///                                                     ↓
/// stop_gatt_server() -> shutdown signal -> Server stops, clients disconnected
///       OR
/// GC triggered       -> Drop::drop()    -> shutdown signal -> Server stops
/// ```
///
/// ## Usage from Elixir
///
/// ```elixir
/// # Start GATT server
/// {:ok, handle} = Reality2Transnet.Action.start_gatt_server(
///   self(),    # PID to receive events
///   "hci0"     # Bluetooth adapter
/// )
///
/// # Receive GATT events
/// receive do
///   {:gatt_connected, client_address} -> ...
///   {:gatt_write, char_uuid, data} -> ...
/// end
///
/// # Stop GATT server
/// :ok = Reality2Transnet.Action.stop_gatt_server(handle)
/// ```
pub struct GattServerHandle {
    /// Oneshot sender for shutdown signal - taken once when stopping
    pub(crate) shutdown_tx: Mutex<Option<oneshot::Sender<()>>>,

    /// Unbounded sender for GATT write events (characteristic UUID, data)
    /// When a client writes to a characteristic, the (UUID, bytes) are sent here
    pub(crate) write_tx: Mutex<Option<mpsc::UnboundedSender<(Uuid, Vec<u8>)>>>,

    /// Unbounded sender for GATT notify/indicate operations
    /// When the server wants to push data to connected clients, bytes are sent here
    pub(crate) notify_tx: Mutex<Option<mpsc::UnboundedSender<Vec<u8>>>>,
}

impl GattServerHandle {
    /// Explicitly stops the GATT server
    ///
    /// Sends a shutdown signal to the background Tokio task, causing it to stop accepting
    /// connections, disconnect any connected clients, and exit gracefully.
    /// This is idempotent - calling multiple times is safe.
    ///
    /// ## Thread Safety
    ///
    /// Can be called from any thread. The `Mutex` ensures exclusive access to the channel.
    pub fn stop(&self) {
        // Try to take the shutdown sender (will be None if already taken)
        if let Some(tx) = self.shutdown_tx.lock().unwrap().take() {
            // Send shutdown signal (ignore errors - task might already be stopped)
            let _ = tx.send(());
        }
    }
}

impl Drop for GattServerHandle {
    /// Automatically stops the GATT server when handle is garbage collected
    ///
    /// This ensures the GATT server is always stopped and clients are disconnected,
    /// even if Elixir code doesn't explicitly call `stop()`. Prevents lingering GATT
    /// services that could confuse connecting clients.
    fn drop(&mut self) {
        self.stop();
    }
}
