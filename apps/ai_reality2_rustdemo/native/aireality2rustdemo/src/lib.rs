#[rustler::nif]
fn add(a: f64, b: f64) -> f64 {
    a + b
}

#[rustler::nif]
fn subtract(a: f64, b: f64) -> f64 {
    a - b
}

rustler::init!("Elixir.AiReality2Rustdemo.Action");
