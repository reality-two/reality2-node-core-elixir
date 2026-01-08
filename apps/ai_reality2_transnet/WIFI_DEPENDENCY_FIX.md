# WiFi Dependency Error Fix - :enoent

## Problem

When running on another Linux device, the application failed with:
```
08:05:02.519 [error] [WifiServer] Failed to list WiFi adapters: "exception: %ErlangError{original: :enoent, reason: nil}"
```

## Root Cause

The `:enoent` error means "Error NO ENTry" - the system couldn't find the `iw` command. This is **not a permissions issue**, but a **missing dependency issue**.

The `iw` command is part of the wireless tools package and is not installed by default on all Linux distributions.

## Solution

### 1. Improved Error Handling

Added specific error handling for `:enoent` in `lib/ai_reality2_transnet/wifi.ex`:

```elixir
def list_adapters do
  case System.cmd("iw", ["dev"], stderr_to_stdout: true) do
    {output, 0} ->
      adapters = parse_iw_dev(output)
      {:ok, adapters}

    {error, _} ->
      {:error, "iw_dev_failed: #{error}"}
  end
rescue
  %ErlangError{original: :enoent} ->
    {:error, "iw command not found - install with: sudo apt install iw (Debian/Ubuntu) or sudo dnf install iw (Fedora)"}

  error ->
    {:error, "exception: #{inspect(error)}"}
end
```

Now instead of cryptic `:enoent` error, users get:
```
iw command not found - install with: sudo apt install iw (Debian/Ubuntu) or sudo dnf install iw (Fedora)
```

### 2. Dependency Check Function

Added `check_dependencies/0` function to verify required commands:

```elixir
@doc """
Checks if required system commands are available.

## Returns
- `{:ok, :all_available}` - All required commands found
- `{:error, missing_commands}` - List of missing commands with installation instructions
"""
def check_dependencies do
  required_commands = [
    %{
      command: "iw",
      debian: "sudo apt install iw",
      fedora: "sudo dnf install iw",
      arch: "sudo pacman -S iw"
    },
    %{
      command: "ip",
      debian: "sudo apt install iproute2",
      fedora: "sudo dnf install iproute2",
      arch: "sudo pacman -S iproute2"
    }
  ]

  missing =
    Enum.filter(required_commands, fn %{command: cmd} ->
      case System.cmd("which", [cmd], stderr_to_stdout: true) do
        {_output, 0} -> false
        _ -> true
      end
    end)

  case missing do
    [] -> {:ok, :all_available}
    commands -> {:error, commands}
  end
end
```

### 3. Startup Dependency Verification

Updated `WifiServer.init/1` to check dependencies at startup:

```elixir
def init(_opts) do
  # Check system dependencies first
  case AiReality2Transnet.Wifi.check_dependencies() do
    {:error, missing} ->
      Logger.error("[WifiServer] Missing required system commands:")

      Enum.each(missing, fn cmd ->
        Logger.error("  - #{cmd.command} not found")
        Logger.error("    Install: #{cmd.debian} (Debian/Ubuntu)")
        Logger.error("           #{cmd.fedora} (Fedora/RHEL)")
        Logger.error("           #{cmd.arch} (Arch Linux)")
      end)

      {:ok, %{status: :missing_dependencies, missing: missing}}

    {:ok, :all_available} ->
      # Proceed with WiFi adapter detection and server startup
      # ...
  end
end
```

## Required System Dependencies

WiFi mesh functionality requires these Linux commands:

### 1. `iw` - Wireless configuration utility

**Debian/Ubuntu:**
```bash
sudo apt update
sudo apt install iw
```

**Fedora/RHEL/CentOS:**
```bash
sudo dnf install iw
```

**Arch Linux:**
```bash
sudo pacman -S iw
```

**Alpine Linux:**
```bash
sudo apk add iw
```

### 2. `ip` - Network configuration utility

Usually already installed, but if missing:

**Debian/Ubuntu:**
```bash
sudo apt install iproute2
```

**Fedora/RHEL/CentOS:**
```bash
sudo dnf install iproute2
```

**Arch Linux:**
```bash
sudo pacman -S iproute2
```

**Alpine Linux:**
```bash
sudo apk add iproute2
```

## Verification

### Check if commands are available

```bash
# Check iw
which iw
iw --version

# Check ip
which ip
ip -V
```

### Test from IEx

```elixir
# Start the application
iex -S mix

# Check dependencies
iex> AiReality2Transnet.Wifi.check_dependencies()
{:ok, :all_available}

# Or if missing:
{:error, [
  %{
    command: "iw",
    debian: "sudo apt install iw",
    fedora: "sudo dnf install iw",
    arch: "sudo pacman -S iw"
  }
]}

# Check WifiServer status
iex> AiReality2Transnet.WifiServer.get_status()
```

## Error Messages

### Before Fix

```
08:05:02.519 [error] [WifiServer] Failed to list WiFi adapters: "exception: %ErlangError{original: :enoent, reason: nil}"
```

**Problem:** Unclear what `:enoent` means or how to fix it.

### After Fix

```
[error] [WifiServer] Missing required system commands:
[error]   - iw not found
[error]     Install: sudo apt install iw (Debian/Ubuntu)
[error]            sudo dnf install iw (Fedora/RHEL)
[error]            sudo pacman -S iw (Arch Linux)
```

**Benefit:** Clear, actionable error message with installation instructions.

## Common Errors and Solutions

### Error: `:enoent`
**Meaning:** Command not found
**Solution:** Install the missing package (see above)

### Error: `:eacces` or "Operation not permitted" or "Permission denied"
**Meaning:** Permission denied - need elevated privileges
**Solution:** See `WIFI_PERMISSIONS.md` for complete solutions

**Quick fix for development:**
```bash
# Option 1: Grant capabilities (recommended)
sudo setcap cap_net_admin=eip $(which iw)
sudo setcap cap_net_admin,cap_net_raw=eip $(which ip)

# Option 2: Add user to netdev group
sudo usermod -aG netdev $USER
# Log out and back in for changes to take effect

# Option 3: Run with sudo (not recommended for production)
sudo mix phx.server
```

**See `WIFI_PERMISSIONS.md` for:**
- Detailed permission solutions
- Security considerations
- Production deployment recommendations
- Docker/container configuration
- Troubleshooting permission issues

### Error: "No such device"
**Meaning:** WiFi adapter not found
**Solution:** Check available adapters:
```bash
iw dev
# or
ip link show
```

## Docker/Container Considerations

If running in a container, you need:

1. **Host networking** or **privileged mode** to access network interfaces
2. **Required packages** installed in container
3. **Capabilities** for network operations

Example Dockerfile:
```dockerfile
FROM elixir:1.19

# Install WiFi tools
RUN apt-get update && \
    apt-get install -y \
        iw \
        iproute2 \
        wireless-tools && \
    rm -rf /var/lib/apt/lists/*

# ... rest of Dockerfile
```

Example docker-compose.yml:
```yaml
services:
  reality2:
    # ...
    network_mode: host  # Required for WiFi mesh
    cap_add:
      - NET_ADMIN      # Required for network configuration
      - NET_RAW        # Required for raw sockets
```

## Testing

### 1. Verify dependencies installed

```bash
# Should show version
iw --version
# Output: iw version 5.19

ip -V
# Output: ip utility, iproute2-ss220328
```

### 2. Test WiFi adapter detection

```elixir
iex> AiReality2Transnet.Wifi.list_adapters()
{:ok, [
  %{
    transport: "wifi",
    interface: "wlan0",
    mesh_interface: "mesh0",
    address: "aa:bb:cc:dd:ee:ff",
    ip_address: nil
  }
]}
```

### 3. Check WifiServer startup logs

```
[info] [WifiServer] HTTP server started on port 8080
[info] [WifiServer] Found 1 WiFi adapter(s)
```

Or if dependencies missing:
```
[error] [WifiServer] Missing required system commands:
[error]   - iw not found
[error]     Install: sudo apt install iw (Debian/Ubuntu)
```

## Files Modified

1. **`lib/ai_reality2_transnet/wifi.ex`**
   - Added specific `:enoent` error handling in `list_adapters/0`
   - Added `check_dependencies/0` function
   - Better error messages with installation instructions

2. **`lib/ai_reality2_transnet/wifi_server.ex`**
   - Added dependency check in `init/1`
   - Logs installation instructions if dependencies missing
   - Gracefully handles missing dependencies

## Benefits

1. **Clear error messages** - Users know exactly what's missing and how to fix it
2. **Startup validation** - Dependencies checked before attempting operations
3. **Multi-distribution support** - Installation instructions for Debian, Fedora, Arch
4. **Graceful degradation** - Server starts but WiFi functionality unavailable if commands missing
5. **Better debugging** - Easy to identify missing system dependencies

## Related Documentation

- `WIFI_MESH_TESTING.md` - Complete testing guide (includes system requirements)
- `WIFI_MESH_QUICKSTART.md` - Quick reference
- `wifi.ex` module documentation - Detailed function docs

**Author:**
- Dr. Roy C. Davies
- [roycdavies.github.io](https://roycdavies.github.io/)
