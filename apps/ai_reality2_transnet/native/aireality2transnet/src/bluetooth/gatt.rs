use bluer::{gatt::local::*, Address, Session};
use rustler::{Encoder, Env, LocalPid, NifResult, ResourceArc, Term};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

use crate::atoms;
use crate::bluetooth::common::{get_or_default_adapter, send_msg};
use crate::bluetooth::resources::GattServerHandle;

// -------------------------------------------------------------------------------------------
// Constants
// -------------------------------------------------------------------------------------------

const STARTUP_TIMEOUT_SECS: u64 = 3;

// R2 GATT Service UUID - must match Android app's BleCharacteristics.R2_SERVICE_UUID
const R2_SERVICE_UUID: Uuid = Uuid::from_u128(0x00001234_0000_1000_8000_00805F9B34FB);

// Characteristic UUIDs - replace with your own
const CHAR_COMMAND_UUID: Uuid = Uuid::from_u128(0x00002A57_0000_1000_8000_00805F9B34FB);
const CHAR_DATA_UUID: Uuid = Uuid::from_u128(0x00002A58_0000_1000_8000_00805F9B34FB);
const CHAR_NOTIFY_UUID: Uuid = Uuid::from_u128(0x00002A59_0000_1000_8000_00805F9B34FB);
const MESH_INFO_CHAR_UUID: Uuid = Uuid::from_u128(0x00001235_0000_1000_8000_00805F9B34FB);
const NODE_INFO_CHAR_UUID: Uuid = Uuid::from_u128(0x00001237_0000_1000_8000_00805F9B34FB);
const HIVE_JOIN_CHAR_UUID: Uuid = Uuid::from_u128(0x00001238_0000_1000_8000_00805F9B34FB);

// -------------------------------------------------------------------------------------------
// GATT Server Types
// -------------------------------------------------------------------------------------------

#[derive(Clone)]
struct CharacteristicData {
    value: Arc<Mutex<Vec<u8>>>,
    notifier: Arc<Mutex<Option<mpsc::UnboundedSender<Vec<u8>>>>>,
}

impl CharacteristicData {
    fn new(initial_value: Vec<u8>) -> Self {
        Self {
            value: Arc::new(Mutex::new(initial_value)),
            notifier: Arc::new(Mutex::new(None)),
        }
    }

    fn read(&self) -> Vec<u8> {
        self.value.lock().unwrap().clone()
    }

    fn write(&self, new_value: Vec<u8>) {
        *self.value.lock().unwrap() = new_value;
    }

    fn set_notifier(&self, tx: mpsc::UnboundedSender<Vec<u8>>) {
        *self.notifier.lock().unwrap() = Some(tx);
    }

    fn notify(&self, value: Vec<u8>) -> bool {
        if let Some(tx) = self.notifier.lock().unwrap().as_ref() {
            tx.send(value).is_ok()
        } else {
            false
        }
    }
}

// -------------------------------------------------------------------------------------------
// GATT Server NIFs
// -------------------------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
pub fn start_gatt_server<'a>(
    env: Env<'a>,
    pid: LocalPid,
    adapter_name: Option<String>,
) -> NifResult<Term<'a>> {
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (write_tx, write_rx) = mpsc::unbounded_channel();
    let (notify_tx, notify_rx) = mpsc::unbounded_channel();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<(), String>>();

    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                let _ = ready_tx.send(Err(format!("tokio_runtime_build_failed: {e}")));
                return;
            }
        };

        let ready_tx_clone = ready_tx.clone();

        let result = rt.block_on(async move {
            run_gatt_server(
                pid,
                adapter_name,
                shutdown_rx,
                write_rx,
                notify_rx,
                ready_tx,
            )
            .await
        });

        if let Err(e) = result {
            let _ = ready_tx_clone.send(Err(e));
        }
    });

    match ready_rx.recv_timeout(std::time::Duration::from_secs(STARTUP_TIMEOUT_SECS)) {
        Ok(Ok(())) => {
            let handle = ResourceArc::new(GattServerHandle {
                shutdown_tx: Mutex::new(Some(shutdown_tx)),
                write_tx: Mutex::new(Some(write_tx)),
                notify_tx: Mutex::new(Some(notify_tx)),
            });
            Ok((atoms::ok(), handle).encode(env))
        }
        Ok(Err(reason)) => Ok((atoms::error(), reason).encode(env)),
        Err(_) => Ok((
            atoms::error(),
            "timeout_waiting_for_gatt_server_start".to_string(),
        )
            .encode(env)),
    }
}

#[rustler::nif]
pub fn stop_gatt_server(handle: ResourceArc<GattServerHandle>) -> rustler::Atom {
    handle.stop();
    atoms::ok()
}

#[rustler::nif]
pub fn gatt_notify(handle: ResourceArc<GattServerHandle>, data: Vec<u8>) -> rustler::Atom {
    let lock = handle.notify_tx.lock().unwrap();
    if let Some(tx) = lock.as_ref() {
        if tx.send(data).is_ok() {
            atoms::ok()
        } else {
            atoms::error()
        }
    } else {
        atoms::error()
    }
}

#[rustler::nif]
pub fn gatt_write_characteristic(
    handle: ResourceArc<GattServerHandle>,
    char_uuid: String,
    data: Vec<u8>,
) -> rustler::Atom {
    let uuid = match Uuid::parse_str(&char_uuid) {
        Ok(u) => u,
        Err(_) => return atoms::error(),
    };

    let lock = handle.write_tx.lock().unwrap();
    if let Some(tx) = lock.as_ref() {
        if tx.send((uuid, data)).is_ok() {
            atoms::ok()
        } else {
            atoms::error()
        }
    } else {
        atoms::error()
    }
}

// -------------------------------------------------------------------------------------------
// GATT Server Implementation
// -------------------------------------------------------------------------------------------

async fn run_gatt_server(
    pid: LocalPid,
    adapter_name: Option<String>,
    mut shutdown_rx: oneshot::Receiver<()>,
    mut write_rx: mpsc::UnboundedReceiver<(Uuid, Vec<u8>)>,
    mut notify_rx: mpsc::UnboundedReceiver<Vec<u8>>,
    ready_tx: std::sync::mpsc::Sender<Result<(), String>>,
) -> Result<(), String> {
    let session = Session::new()
        .await
        .map_err(|e| format!("session_new_failed: {e}"))?;

    let adapter = get_or_default_adapter(&session, adapter_name).await?;

    adapter
        .set_powered(true)
        .await
        .map_err(|e| format!("set_powered_failed: {e}"))?;

    // Create characteristic data stores
    let command_data = CharacteristicData::new(vec![]);
    let data_char_data = CharacteristicData::new(vec![]);
    let notify_data = CharacteristicData::new(vec![]);
    let mesh_info_data = CharacteristicData::new(vec![]);
    let node_info_data = CharacteristicData::new(vec![]);
    let hive_join_data = CharacteristicData::new(vec![]);

    // Build GATT service
    let (notify_tx, notify_notifier_rx) = mpsc::unbounded_channel();
    notify_data.set_notifier(notify_tx);

    let (hive_join_notify_tx, hive_join_notify_rx) = mpsc::unbounded_channel();
    hive_join_data.set_notifier(hive_join_notify_tx);

    // Wrap the receiver in Arc<tokio::sync::Mutex<>> so it can be shared across async contexts
    let notify_rx_shared = Arc::new(tokio::sync::Mutex::new(notify_notifier_rx));
    let hive_join_notify_rx_shared = Arc::new(tokio::sync::Mutex::new(hive_join_notify_rx));

    let command_data_clone = command_data.clone();
    let command_data_read = command_data.clone();
    let command_data_write = command_data.clone();
    let data_char_data_clone = data_char_data.clone();
    let data_char_data_read = data_char_data.clone();
    let data_char_data_write = data_char_data.clone();
    let notify_data_clone = notify_data.clone();
    let mesh_info_data_read = mesh_info_data.clone();
    let mesh_info_data_write = mesh_info_data.clone();
    let node_info_data_read = node_info_data.clone();
    let node_info_data_write = node_info_data.clone();
    let hive_join_data_clone = hive_join_data.clone();
    let hive_join_data_read = hive_join_data.clone();
    let hive_join_data_write = hive_join_data.clone();
    let hive_join_data_notify_clone = hive_join_data.clone();
    let pid_clone = pid.clone();
    let pid_hive_join = pid.clone();

    let service = Service {
        uuid: R2_SERVICE_UUID,
        primary: true,
        characteristics: vec![
            // Command characteristic (write)
            Characteristic {
                uuid: CHAR_COMMAND_UUID,
                write: Some(CharacteristicWrite {
                    write: true,
                    write_without_response: true,
                    method: CharacteristicWriteMethod::Fun(Box::new(
                        move |new_value, _req_data| {
                            let data = command_data_clone.clone();
                            let pid = pid_clone.clone();
                            Box::pin(async move {
                                eprint!("[debug] GATT COMMAND char write from client: {} bytes\r\n", new_value.len());
                                data.write(new_value.clone());
                                send_msg(&pid, |env| {
                                    (atoms::gatt_write(), "command", new_value.clone()).encode(env)
                                });
                                eprint!("[debug] GATT notified Elixir about write\r\n");
                                Ok(())
                            })
                        },
                    )),
                    ..Default::default()
                }),
                read: Some(CharacteristicRead {
                    read: true,
                    fun: Box::new(move |_req_data| {
                        let data = command_data_read.clone();
                        Box::pin(async move {
                            let value = data.read();
                            eprint!("[debug] GATT COMMAND char read request - returning {} bytes\r\n", value.len());
                            Ok(value)
                        })
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            },
            // Data characteristic (read/write)
            Characteristic {
                uuid: CHAR_DATA_UUID,
                write: Some(CharacteristicWrite {
                    write: true,
                    write_without_response: false,
                    method: CharacteristicWriteMethod::Fun(Box::new(
                        move |new_value, _req_data| {
                            let data = data_char_data_clone.clone();
                            let pid = pid.clone();
                            Box::pin(async move {
                                data.write(new_value.clone());
                                send_msg(&pid, |env| {
                                    (atoms::gatt_write(), "data", new_value.clone()).encode(env)
                                });
                                Ok(())
                            })
                        },
                    )),
                    ..Default::default()
                }),
                read: Some(CharacteristicRead {
                    read: true,
                    fun: Box::new(move |_req_data| {
                        let data = data_char_data_read.clone();
                        Box::pin(async move { Ok(data.read()) })
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            },
            // Notify characteristic (notify/indicate)
            Characteristic {
                uuid: CHAR_NOTIFY_UUID,
                notify: Some(CharacteristicNotify {
                    notify: true,
                    method: CharacteristicNotifyMethod::Fun(Box::new(move |mut notifier| {
                        let rx_lock = notify_rx_shared.clone();
                        Box::pin(async move {
                            loop {
                                let value_opt = {
                                    let mut rx = rx_lock.lock().await;
                                    rx.recv().await
                                };

                                match value_opt {
                                    Some(value) => {
                                        if notifier.notify(value).await.is_err() {
                                            break;
                                        }
                                    }
                                    None => break,
                                }
                            }
                        })
                    })),
                    ..Default::default()
                }),
                read: Some(CharacteristicRead {
                    read: true,
                    fun: Box::new(move |_req_data| {
                        let data = notify_data_clone.clone();
                        Box::pin(async move { Ok(data.read()) })
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            },
            // Mesh Info characteristic (read-only)
            Characteristic {
                uuid: MESH_INFO_CHAR_UUID,
                read: Some(CharacteristicRead {
                    read: true,
                    fun: Box::new(move |_req_data| {
                        let data = mesh_info_data_read.clone();
                        Box::pin(async move {
                            let value = data.read();
                            eprint!("[debug] GATT MESH_INFO char read request - returning {} bytes\r\n", value.len());
                            Ok(value)
                        })
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            },
            // Node Info characteristic (read-only)
            Characteristic {
                uuid: NODE_INFO_CHAR_UUID,
                read: Some(CharacteristicRead {
                    read: true,
                    fun: Box::new(move |_req_data| {
                        let data = node_info_data_read.clone();
                        Box::pin(async move {
                            let value = data.read();
                            eprint!("[debug] GATT NODE_INFO char read request - returning {} bytes\r\n", value.len());
                            Ok(value)
                        })
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            },
            // Hive Join characteristic (read/write/notify)
            Characteristic {
                uuid: HIVE_JOIN_CHAR_UUID,
                write: Some(CharacteristicWrite {
                    write: true,
                    write_without_response: false,
                    method: CharacteristicWriteMethod::Fun(Box::new(
                        move |new_value, _req_data| {
                            let data = hive_join_data_clone.clone();
                            let pid = pid_hive_join.clone();
                            Box::pin(async move {
                                eprint!("[debug] GATT HIVE_JOIN char write from client: {} bytes\r\n", new_value.len());
                                data.write(new_value.clone());
                                send_msg(&pid, |env| {
                                    (atoms::gatt_write(), "hive_join", new_value.clone()).encode(env)
                                });
                                Ok(())
                            })
                        },
                    )),
                    ..Default::default()
                }),
                read: Some(CharacteristicRead {
                    read: true,
                    fun: Box::new(move |_req_data| {
                        let data = hive_join_data_read.clone();
                        Box::pin(async move {
                            let value = data.read();
                            eprint!("[debug] GATT HIVE_JOIN char read request - returning {} bytes\r\n", value.len());
                            Ok(value)
                        })
                    }),
                    ..Default::default()
                }),
                notify: Some(CharacteristicNotify {
                    notify: true,
                    method: CharacteristicNotifyMethod::Fun(Box::new(move |mut notifier| {
                        let rx_lock = hive_join_notify_rx_shared.clone();
                        Box::pin(async move {
                            loop {
                                let value_opt = {
                                    let mut rx = rx_lock.lock().await;
                                    rx.recv().await
                                };
                                match value_opt {
                                    Some(value) => {
                                        if notifier.notify(value).await.is_err() {
                                            break;
                                        }
                                    }
                                    None => break,
                                }
                            }
                        })
                    })),
                    ..Default::default()
                }),
                ..Default::default()
            },
        ],
        ..Default::default()
    };

    let app = Application {
        services: vec![service],
        ..Default::default()
    };

    let app_handle = adapter
        .serve_gatt_application(app)
        .await
        .map_err(|e| format!("serve_gatt_application_failed: {e}"))?;

    // Make adapter discoverable
    // adapter
    //     .set_discoverable(true)
    //     .await
    //     .map_err(|e| format!("set_discoverable_failed: {e}"))?;

    let _ = ready_tx.send(Ok(()));

    send_msg(&pid, |env| atoms::gatt_server_started().encode(env));

    // Handle shutdown and notification requests
    loop {
        tokio::select! {
            _ = &mut shutdown_rx => {
                break;
            }

            Some((uuid, data)) = write_rx.recv() => {
                // Handle programmatic writes to characteristics
                // This allows Elixir to update characteristic values
                if uuid == CHAR_COMMAND_UUID {
                    eprint!("[debug] GATT received programmatic write to COMMAND char: {} bytes\r\n", data.len());
                    command_data_write.write(data.clone());
                    eprint!("[debug] GATT buffer updated, new size: {} bytes\r\n", data.len());
                } else if uuid == CHAR_DATA_UUID {
                    data_char_data_write.write(data);
                } else if uuid == CHAR_NOTIFY_UUID {
                    notify_data.write(data.clone());
                    notify_data.notify(data);
                } else if uuid == MESH_INFO_CHAR_UUID {
                    eprint!("[debug] GATT received programmatic write to MESH_INFO char: {} bytes\r\n", data.len());
                    mesh_info_data_write.write(data);
                } else if uuid == NODE_INFO_CHAR_UUID {
                    eprint!("[debug] GATT received programmatic write to NODE_INFO char: {} bytes\r\n", data.len());
                    node_info_data_write.write(data);
                } else if uuid == HIVE_JOIN_CHAR_UUID {
                    eprint!("[debug] GATT received programmatic write to HIVE_JOIN char: {} bytes\r\n", data.len());
                    hive_join_data_write.write(data.clone());
                    hive_join_data_notify_clone.notify(data);
                }
            }

            Some(data) = notify_rx.recv() => {
                notify_data.write(data.clone());
                notify_data.notify(data);
            }
        }
    }

    drop(app_handle);
    Ok(())
}

// -------------------------------------------------------------------------------------------
// GATT Client NIFs
// -------------------------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
pub fn gatt_connect<'a>(
    env: Env<'a>,
    pid: LocalPid,
    address: String,
    adapter_name: Option<String>,
) -> NifResult<Term<'a>> {
    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                send_msg(&pid, |env| {
                    (atoms::error(), format!("tokio_runtime_build_failed: {e}")).encode(env)
                });
                return;
            }
        };

        let result =
            rt.block_on(async { connect_and_discover(pid.clone(), address, adapter_name).await });

        match result {
            Ok(()) => {
                send_msg(&pid, |env| atoms::gatt_connected().encode(env));
            }
            Err(e) => {
                send_msg(&pid, |env| (atoms::error(), e).encode(env));
            }
        }
    });

    Ok(atoms::ok().encode(env))
}

#[rustler::nif(schedule = "DirtyIo")]
pub fn gatt_read_characteristic<'a>(
    env: Env<'a>,
    pid: LocalPid,
    address: String,
    char_uuid: String,
    adapter_name: Option<String>,
) -> NifResult<Term<'a>> {
    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                send_msg(&pid, |env| {
                    (atoms::error(), format!("tokio_runtime_build_failed: {e}")).encode(env)
                });
                return;
            }
        };

        let result: Result<Vec<u8>, String> = rt.block_on(async {
            let uuid = Uuid::parse_str(&char_uuid).map_err(|e| format!("invalid_uuid: {e}"))?;

            read_characteristic_value(address, uuid, adapter_name).await
        });

        match result {
            Ok(value) => {
                send_msg(&pid, |env| (atoms::gatt_read(), value).encode(env));
            }
            Err(e) => {
                send_msg(&pid, |env| (atoms::error(), e).encode(env));
            }
        }
    });

    Ok(atoms::ok().encode(env))
}

#[rustler::nif(schedule = "DirtyIo")]
pub fn gatt_write_to_device<'a>(
    env: Env<'a>,
    pid: LocalPid,
    address: String,
    char_uuid: String,
    data: Vec<u8>,
    adapter_name: Option<String>,
) -> NifResult<Term<'a>> {
    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                send_msg(&pid, |env| {
                    (atoms::error(), format!("tokio_runtime_build_failed: {e}")).encode(env)
                });
                return;
            }
        };

        let result: Result<(), String> = rt.block_on(async {
            let uuid = Uuid::parse_str(&char_uuid).map_err(|e| format!("invalid_uuid: {e}"))?;

            write_characteristic_value(address, uuid, data, adapter_name).await
        });

        match result {
            Ok(()) => {
                send_msg(&pid, |env| atoms::gatt_write_success().encode(env));
            }
            Err(e) => {
                send_msg(&pid, |env| (atoms::error(), e).encode(env));
            }
        }
    });

    Ok(atoms::ok().encode(env))
}

// -------------------------------------------------------------------------------------------
// GATT Client Implementation
// -------------------------------------------------------------------------------------------

async fn connect_and_discover(
    pid: LocalPid,
    address: String,
    adapter_name: Option<String>,
) -> Result<(), String> {
    let addr: Address = address
        .parse()
        .map_err(|e| format!("invalid_address: {e}"))?;

    let session = Session::new()
        .await
        .map_err(|e| format!("session_new_failed: {e}"))?;

    let adapter = get_or_default_adapter(&session, adapter_name).await?;

    let device = adapter
        .device(addr)
        .map_err(|e| format!("device_open_failed: {e}"))?;

    if !device
        .is_connected()
        .await
        .map_err(|e| format!("is_connected_check_failed: {e}"))?
    {
        device
            .connect()
            .await
            .map_err(|e| format!("connect_failed: {e}"))?;
    }

    // Discover services
    let services = device
        .services()
        .await
        .map_err(|e| format!("services_discovery_failed: {e}"))?;

    let mut service_info = Vec::new();

    for service in services {
        let uuid = service
            .uuid()
            .await
            .map_err(|e| format!("service_uuid_failed: {e}"))?;

        let characteristics = service
            .characteristics()
            .await
            .map_err(|e| format!("characteristics_discovery_failed: {e}"))?;

        let mut char_uuids = Vec::new();
        for char in characteristics {
            let char_uuid = char
                .uuid()
                .await
                .map_err(|e| format!("characteristic_uuid_failed: {e}"))?;
            char_uuids.push(char_uuid.to_string());
        }

        service_info.push((uuid.to_string(), char_uuids));
    }

    send_msg(&pid, |env| {
        (atoms::gatt_services_discovered(), service_info).encode(env)
    });

    Ok(())
}

async fn read_characteristic_value(
    address: String,
    char_uuid: Uuid,
    adapter_name: Option<String>,
) -> Result<Vec<u8>, String> {
    let addr: Address = address
        .parse()
        .map_err(|e| format!("invalid_address: {e}"))?;

    let session = Session::new()
        .await
        .map_err(|e| format!("session_new_failed: {e}"))?;

    let adapter = get_or_default_adapter(&session, adapter_name).await?;

    let device = adapter
        .device(addr)
        .map_err(|e| format!("device_open_failed: {e}"))?;

    if !device
        .is_connected()
        .await
        .map_err(|e| format!("is_connected_check_failed: {e}"))?
    {
        device
            .connect()
            .await
            .map_err(|e| format!("connect_failed: {e}"))?;
    }

    let services = device
        .services()
        .await
        .map_err(|e| format!("services_discovery_failed: {e}"))?;

    for service in services {
        let characteristics = service
            .characteristics()
            .await
            .map_err(|e| format!("characteristics_discovery_failed: {e}"))?;

        for char in characteristics {
            let uuid = char
                .uuid()
                .await
                .map_err(|e| format!("characteristic_uuid_failed: {e}"))?;

            if uuid == char_uuid {
                let value = char.read().await.map_err(|e| format!("read_failed: {e}"))?;
                return Ok(value);
            }
        }
    }

    Err("characteristic_not_found".to_string())
}

async fn write_characteristic_value(
    address: String,
    char_uuid: Uuid,
    data: Vec<u8>,
    adapter_name: Option<String>,
) -> Result<(), String> {
    let addr: Address = address
        .parse()
        .map_err(|e| format!("invalid_address: {e}"))?;

    let session = Session::new()
        .await
        .map_err(|e| format!("session_new_failed: {e}"))?;

    let adapter = get_or_default_adapter(&session, adapter_name).await?;

    let device = adapter
        .device(addr)
        .map_err(|e| format!("device_open_failed: {e}"))?;

    if !device
        .is_connected()
        .await
        .map_err(|e| format!("is_connected_check_failed: {e}"))?
    {
        device
            .connect()
            .await
            .map_err(|e| format!("connect_failed: {e}"))?;
    }

    let services = device
        .services()
        .await
        .map_err(|e| format!("services_discovery_failed: {e}"))?;

    for service in services {
        let characteristics = service
            .characteristics()
            .await
            .map_err(|e| format!("characteristics_discovery_failed: {e}"))?;

        for char in characteristics {
            let uuid = char
                .uuid()
                .await
                .map_err(|e| format!("characteristic_uuid_failed: {e}"))?;

            if uuid == char_uuid {
                char.write(&data)
                    .await
                    .map_err(|e| format!("write_failed: {e}"))?;
                return Ok(());
            }
        }
    }

    Err("characteristic_not_found".to_string())
}
