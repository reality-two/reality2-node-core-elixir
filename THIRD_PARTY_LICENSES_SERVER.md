# Third Party Licenses - Server Components

This document lists all third-party open source libraries used in the Reality2 server
(Elixir and Rust components), along with their licenses.

Generated: 2026-01-17

---

## Elixir Dependencies

| Package | Version | License | URL |
|---------|---------|---------|-----|
| absinthe | ~> 1.7 | MIT | https://hex.pm/packages/absinthe |
| absinthe_phoenix | ~> 2.0 | MIT | https://hex.pm/packages/absinthe_phoenix |
| absinthe_plug | ~> 1.5 | MIT | https://hex.pm/packages/absinthe_plug |
| bcrypt_elixir | ~> 3.0 | BSD-3-Clause / ISC / BSD-4-Clause | https://hex.pm/packages/bcrypt_elixir |
| dns_cluster | ~> 0.1.1 | MIT | https://hex.pm/packages/dns_cluster |
| ecto_sql | ~> 3.10 | Apache-2.0 | https://hex.pm/packages/ecto_sql |
| ex_doc | ~> 0.31 | Apache-2.0 | https://hex.pm/packages/ex_doc |
| finch | ~> 0.16 | MIT | https://hex.pm/packages/finch |
| geohash | ~> 1.0 | Apache-2.0 | https://hex.pm/packages/geohash |
| httpoison | ~> 2.0 | MIT | https://hex.pm/packages/httpoison |
| jason | ~> 1.2 | Apache-2.0 | https://hex.pm/packages/jason |
| makeup_elixir | >= 0.0.0 | BSD-2-Clause | https://hex.pm/packages/makeup_elixir |
| phoenix | ~> 1.7.12 | MIT | https://hex.pm/packages/phoenix |
| phoenix_ecto | ~> 4.4 | MIT | https://hex.pm/packages/phoenix_ecto |
| phoenix_live_dashboard | ~> 0.8.2 | MIT | https://hex.pm/packages/phoenix_live_dashboard |
| phoenix_pubsub | ~> 2.1 | MIT | https://hex.pm/packages/phoenix_pubsub |
| plug_cowboy | ~> 2.5 | Apache-2.0 | https://hex.pm/packages/plug_cowboy |
| postgrex | >= 0.0.0 | Apache-2.0 | https://hex.pm/packages/postgrex |
| rustler | ~> 0.34.0 | Apache-2.0 OR MIT | https://hex.pm/packages/rustler |
| telemetry_metrics | ~> 0.6 | Apache-2.0 | https://hex.pm/packages/telemetry_metrics |
| telemetry_poller | ~> 1.0 | Apache-2.0 | https://hex.pm/packages/telemetry_poller |
| toml | ~> 0.7 | Apache-2.0 | https://hex.pm/packages/toml |
| uuid | ~> 1.1 | Apache-2.0 | https://hex.pm/packages/uuid |
| validate | ~> 1.3 | MIT | https://hex.pm/packages/validate |
| yaml_elixir | ~> 2.9 | MIT | https://hex.pm/packages/yaml_elixir |

---

## Rust Dependencies (Native NIFs)

These Rust crates are compiled into native code via Rustler.

| Crate | Version | License | URL |
|-------|---------|---------|-----|
| rustler | 0.34.0 | Apache-2.0 OR MIT | https://crates.io/crates/rustler |
| tokio | 1.48 | MIT | https://crates.io/crates/tokio |
| futures | 0.3.31 | Apache-2.0 OR MIT | https://crates.io/crates/futures |
| bluer | 0.17 | BSD-2-Clause | https://crates.io/crates/bluer |
| uuid | 1.0 | Apache-2.0 OR MIT | https://crates.io/crates/uuid |
| serde | 1.0 | Apache-2.0 OR MIT | https://crates.io/crates/serde |
| serde_json | 1.0 | Apache-2.0 OR MIT | https://crates.io/crates/serde_json |

---

## License Summary

### Elixir Dependencies by License Type

| License | Count | Packages |
|---------|-------|----------|
| MIT | 13 | absinthe, absinthe_phoenix, absinthe_plug, dns_cluster, finch, httpoison, phoenix, phoenix_ecto, phoenix_live_dashboard, phoenix_pubsub, validate, yaml_elixir, rustler (dual) |
| Apache-2.0 | 11 | ecto_sql, ex_doc, geohash, jason, plug_cowboy, postgrex, telemetry_metrics, telemetry_poller, toml, uuid, rustler (dual) |
| BSD variants | 2 | bcrypt_elixir (BSD-3/ISC/BSD-4), makeup_elixir (BSD-2) |

### Rust Dependencies by License Type

| License | Count | Packages |
|---------|-------|----------|
| MIT | 1 | tokio |
| Apache-2.0 OR MIT (dual) | 5 | rustler, futures, uuid, serde, serde_json |
| BSD-2-Clause | 1 | bluer |

---

## License Obligations Summary

### MIT License
- Include copyright notice and license text in distributions
- No copyleft requirements
- Commercial use permitted

### Apache-2.0 License
- Include copyright notice and license text
- State significant changes made to code
- Include NOTICE file if present
- Provides patent grant
- No copyleft requirements

### BSD Licenses (BSD-2-Clause, BSD-3-Clause)
- Include copyright notice
- BSD-4-Clause requires acknowledgment in advertising (bcrypt_elixir)
- No copyleft requirements

### Development-Only Dependencies
The following are only used during development and do not ship with production builds:
- ex_doc (Apache-2.0)
- makeup_elixir (BSD-2-Clause)

---

## Notes

1. **No copyleft licenses detected** - All dependencies use permissive licenses compatible
   with commercial/proprietary use.

2. **bcrypt_elixir** has multiple license components due to underlying C code from OpenBSD.
   Review the package's LICENSE file for complete terms.

3. **bluer** (Rust Bluetooth library) is listed as BSD-2-Clause on crates.io. The underlying
   BlueZ library has its own licensing terms.

4. Dual-licensed packages (Apache-2.0 OR MIT) allow you to choose either license.
