# NIF for Elixir.AiReality2Transnet

## To build the NIF module:

- Your NIF will now build along with your project.

## To load the NIF:

```elixir
defmodule AiReality2Transnet do
  use Rustler, otp_app: :ai_reality2_transnet, crate: "aireality2transnet"

  # When the NIF is loaded, it will override these functions.
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
```

## Examples

[This](https://github.com/rusterlium/NifIo) is a complete example of a NIF written in Rust.
