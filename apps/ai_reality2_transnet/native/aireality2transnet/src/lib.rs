use futures::stream::StreamExt;
use rustler::{Encoder, Env, LocalPid, OwnedEnv, Term};
use simplersble; // Ensure 'futures' crate is in Cargo.toml

#[derive(rustler::NifMap)]
pub struct Adapters {
    pub id: String,
    pub address: String,
}

#[rustler::nif]
fn list_adapters() -> Vec<Adapters> {
    simplersble::Adapter::get_adapters()
        .unwrap_or_default()
        .into_iter()
        .map(|adapter| Adapters {
            id: adapter.identifier().unwrap_or_default(),
            address: adapter.address().unwrap_or_default(),
        })
        .collect()
}

#[derive(rustler::NifMap)]
pub struct Device {
    pub name: String,
    pub address: String,
    pub rssi: i16,
}

#[rustler::nif]
fn scan_devices(env: Env, pid: LocalPid, timeout: i32) -> Term {
    let _ = std::thread::spawn(move || {
        let mut owned_env = OwnedEnv::new();

        // Initialize a Tokio runtime to handle the async stream
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let result: Result<Vec<Device>, String> = rt.block_on(async {
            let mut adapters = simplersble::Adapter::get_adapters().map_err(|e| e.to_string())?;
            let adapter = adapters.pop().ok_or("No adapters found")?;

            // Setup the scan event stream
            let mut scan_event = adapter.on_scan_event();

            // Spawn a task to monitor events (optional, useful if you want to stream results)
            tokio::spawn(async move {
                while let Some(Ok(_event)) = scan_event.next().await {
                    // You could send messages back to Elixir here for real-time updates
                }
            });

            // Perform the blocking scan for 10 seconds (10000ms)
            adapter.scan_for(timeout).map_err(|e| e.to_string())?;

            // Retrieve and map the results
            let results = adapter.scan_get_results().map_err(|e| e.to_string())?;

            let devices = results
                .iter()
                .map(|p| Device {
                    name: p.identifier().unwrap_or_else(|_| "Unknown".to_string()),
                    address: p
                        .address()
                        .unwrap_or_else(|_| "00:00:00:00:00:00".to_string()),
                    rssi: p.rssi().unwrap_or(0),
                })
                .collect();

            Ok(devices)
        });

        // Dispatch final message to Elixir
        let _ = owned_env.send_and_clear(&pid, |env| match result {
            Ok(devices) => (rustler::types::atom::ok(), devices).encode(env),
            Err(err) => (rustler::types::atom::error(), err).encode(env),
        });
    });

    rustler::types::atom::ok().encode(env)
}

rustler::init!("Elixir.AiReality2Transnet.Action");
