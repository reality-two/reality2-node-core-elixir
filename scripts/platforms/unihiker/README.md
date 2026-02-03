# Reality2 / reality2_transnet — Build on Debian Buster (glibc 2.28) arm64 using Podman on AMD (x86_64) Linux

This is a single, end-to-end, copy/paste guide to build an Elixir project (including Rustler NIFs) in a Debian Buster arm64 environment on an AMD x86_64 Linux workstation using Podman. The purpose is to produce binaries compatible with Debian Buster devices (e.g., Unihiker) and avoid runtime errors such as `GLIBC_2.34 not found` by compiling inside a Buster userspace (glibc 2.28) and on the correct architecture (arm64/aarch64).

Run commands from a terminal. Where you see `...`, adjust to your own repo paths as needed.

---

## Confirm host architecture (AMD workstation)

```bash
uname -m
# expected: x86_64
```

---

## Install Podman (Ubuntu/Debian/TUXEDO OS)

```bash
sudo apt-get update
sudo apt-get install -y podman
podman --version
```

---

## Enable running arm64 containers on x86_64 (QEMU + binfmt)

Because we will execute an arm64 container on an x86_64 host, you must enable user-mode emulation.

```bash
sudo apt-get update
sudo apt-get install -y qemu-user-static binfmt-support

# Enable/restart binfmt handler service (systemd-based distros)
sudo systemctl enable --now systemd-binfmt 2>/dev/null || true
sudo systemctl restart systemd-binfmt 2>/dev/null || true

# Confirm binfmt_misc is enabled
cat /proc/sys/fs/binfmt_misc/status
# expected: enabled
```

Smoke test that arm64 execution works:

```bash
podman run --rm --platform linux/arm64 docker.io/library/alpine:3.19 uname -m
# expected: aarch64
```

If you get `Exec format error`, binfmt/QEMU is not working; fix that before continuing.

---

## Create the build Containerfile (Debian Buster arm64 + Rust + CMake>=3.21 + deps)

From your Elixir project root (same directory as `mix.exs`), create `Containerfile`:

```bash
cat > Containerfile <<'EOF'
FROM docker.io/hexpm/elixir:1.18.2-erlang-27.2.2-debian-buster-20240612

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Configure archived Debian Buster repositories (explicitly) + disable Valid-Until checks
RUN set -eux; \
    rm -f /etc/apt/sources.list.d/*.list || true; \
    printf '%s\n' \
      'deb http://archive.debian.org/debian buster main contrib non-free' \
      'deb http://archive.debian.org/debian buster-updates main contrib non-free' \
      'deb http://archive.debian.org/debian-security buster/updates main contrib non-free' \
      > /etc/apt/sources.list; \
    printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99no-check-valid-until; \
    apt-get update

# Tooling for Rustler builds + Python for pip-based CMake + SimpleBLE deps
RUN set -eux; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git zip \
      build-essential pkg-config \
      python3 python3-pip \
      libdbus-1-dev libudev-dev; \
    rm -rf /var/lib/apt/lists/*

# Rust toolchain (minimal)
RUN set -eux; \
    curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH=/usr/local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

# Install CMake >= 3.21 from PyPI and force it to be used
RUN set -eux; \
    python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel; \
    python3 -m pip install --no-cache-dir "cmake==3.21.4"; \
    /usr/local/bin/cmake --version; \
    ln -sf /usr/local/bin/cmake /usr/bin/cmake; \
    cmake --version

ENV CMAKE=/usr/local/bin/cmake
EOF
```

---

## Build the container image (arm64)

```bash
podman build --no-cache --platform linux/arm64 \
  -t elixir-buster-rust-cmake:latest \
  -f Containerfile .
```

Quick sanity check that the image contains the right toolchain and is arm64:

```bash
podman run --rm --platform linux/arm64 elixir-buster-rust-cmake:latest \
  bash -lc 'uname -m; cmake --version; pkg-config --modversion dbus-1; rustc -V; cargo -V; elixir -v'
```

Expected highlights:
- `uname -m` -> `aarch64`
- `cmake --version` -> `3.21.4`
- `pkg-config --modversion dbus-1` prints a version
- `rustc`/`cargo` are present
- `elixir` is present

---

## Run the container to build your Elixir project (recommended: interactive + caches)

From the project root (usually the Reality2 folder which has at least the `reality2-node-core-elixir` and `reality2-definitions` github repositories):

```bash
podman run --rm -it --platform linux/arm64 \
  -v "$PWD":/app -w /app \
  -v "$HOME/.hex:/root/.hex" \
  -v "$HOME/.mix:/root/.mix" \
  -v "$HOME/.cache/cargo/registry:/root/.cargo/registry" \
  -v "$HOME/.cache/cargo/git:/root/.cargo/git" \
  elixir-buster-rust-cmake:latest \
  bash
```

Inside the container, run the build:

```bash
cd reality2-node-core-elixir/scripts
./make_runtime
```
