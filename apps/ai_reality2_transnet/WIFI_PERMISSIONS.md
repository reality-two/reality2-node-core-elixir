# WiFi Mesh Permissions Guide

## Problem

WiFi mesh operations require elevated privileges because they:
- Create/destroy network interfaces
- Configure wireless settings
- Join mesh networks
- Modify routing tables

The `iw` and `ip` commands need root/sudo access for these operations.

## Error Messages

### Permission Denied
```
[error] [WifiServer] Failed to list WiFi adapters: "permission_denied: iw requires elevated privileges - see WIFI_PERMISSIONS.md for solutions"
```

### Operation Not Permitted
```
Error: Operation not permitted
```

## Solutions

Choose the solution that best fits your deployment scenario.

### Solution 1: Add User to `netdev` Group (Recommended for Development)

This gives the user permission to manage network devices without sudo.

```bash
# Add your user to the netdev group
sudo usermod -aG netdev $USER

# Verify group membership
groups $USER

# Log out and log back in for changes to take effect
# Or use: newgrp netdev
```

**Verification:**
```bash
# Should work without sudo now
iw dev
```

**Pros:**
- ✅ No need to run entire application as root
- ✅ Permanent solution
- ✅ Standard Linux group for network operations

**Cons:**
- ⚠️ Requires logout/login
- ⚠️ Not available on all distributions
- ⚠️ May not work for all operations (depends on polkit rules)

### Solution 2: Grant Capabilities to `iw` Binary (Recommended for Production)

Use Linux capabilities to grant specific privileges to the `iw` command without full root access.

```bash
# Find the iw binary location
which iw
# Output: /usr/sbin/iw

# Grant CAP_NET_ADMIN capability
sudo setcap cap_net_admin=eip /usr/sbin/iw

# Verify capabilities set
getcap /usr/sbin/iw
# Output: /usr/sbin/iw = cap_net_admin+eip
```

**For `ip` command as well:**
```bash
which ip
# Output: /usr/sbin/ip or /sbin/ip

sudo setcap cap_net_admin,cap_net_raw=eip $(which ip)
```

**Verification:**
```bash
# Should work without sudo now
iw dev
ip link show
```

**Pros:**
- ✅ Most secure - only specific binary gets capabilities
- ✅ No need to run entire application as root
- ✅ Persists across reboots
- ✅ Works immediately (no logout required)

**Cons:**
- ⚠️ Capabilities may be lost on package updates (need to reapply)
- ⚠️ Requires CAP_NET_ADMIN which is powerful

**To remove capabilities (if needed):**
```bash
sudo setcap -r /usr/sbin/iw
sudo setcap -r $(which ip)
```

### Solution 3: Configure Sudo with NOPASSWD (For Automation)

Allow specific commands to run with sudo without password prompts.

```bash
# Edit sudoers file (use visudo for safety)
sudo visudo

# Add these lines (replace 'youruser' with your username):
youruser ALL=(ALL) NOPASSWD: /usr/sbin/iw
youruser ALL=(ALL) NOPASSWD: /usr/sbin/ip
youruser ALL=(ALL) NOPASSWD: /sbin/ip
```

Then update the Elixir code to use sudo:

```elixir
# In wifi.ex, modify System.cmd calls:
System.cmd("sudo", ["iw", "dev"], stderr_to_stdout: true)
System.cmd("sudo", ["ip", "-6", "addr", "show", interface], stderr_to_stdout: true)
```

**Pros:**
- ✅ Works for automated deployments
- ✅ Can be specific about which commands are allowed
- ✅ No application restart needed

**Cons:**
- ⚠️ Requires modifying Reality2 code
- ⚠️ Sudoers file errors can lock you out (use visudo!)
- ⚠️ Still requires sudo configuration

### Solution 4: Run Application as Root (Not Recommended for Production)

Only use this for quick testing or development.

```bash
# Run with sudo
sudo mix phx.server

# Or for releases:
sudo _build/prod/rel/reality2/bin/reality2 start
```

**Pros:**
- ✅ Works immediately
- ✅ No configuration needed

**Cons:**
- ❌ **Security risk** - entire application runs as root
- ❌ File ownership issues (logs, uploads owned by root)
- ❌ Not recommended for production

### Solution 5: Polkit Rules (Advanced, Distribution-Specific)

Create polkit rules to allow network operations without sudo.

**Create `/etc/polkit-1/rules.d/50-reality2-network.rules`:**
```javascript
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.NetworkManager.network-control" &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});

polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.network-manager") == 0 &&
        subject.user == "reality2") {
        return polkit.Result.YES;
    }
});
```

**Reload polkit:**
```bash
sudo systemctl restart polkit
```

**Pros:**
- ✅ Fine-grained control
- ✅ Integrates with system security policies
- ✅ Can be user-specific or group-specific

**Cons:**
- ⚠️ Complex configuration
- ⚠️ Distribution-specific
- ⚠️ Requires understanding of polkit

## Verification Steps

After applying any solution, verify permissions work:

### 1. Test iw command
```bash
# List wireless devices (should work without sudo)
iw dev

# Expected output:
# phy#0
# 	Interface wlan0
# 		ifindex 3
# 		wdev 0x1
# 		addr aa:bb:cc:dd:ee:ff
# 		type managed
```

### 2. Test ip command
```bash
# Show network interfaces (should work without sudo)
ip link show

# Expected output:
# 1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 ...
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
# 3: wlan0: <BROADCAST,MULTICAST> ...
```

### 3. Test from Reality2

```elixir
# Start application
iex -S mix

# Check WiFi adapters
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

# Check WifiServer status
iex> AiReality2Transnet.WifiServer.get_status()
%{
  port: 8080,
  started_at: ~U[2026-01-09 08:05:02.519Z],
  requests_handled: 0,
  errors: 0,
  adapters: [...]
}
```

### 4. Check logs

**Success:**
```
[info] [WifiServer] HTTP server started on port 8080
[info] [WifiServer] Found 1 WiFi adapter(s)
```

**Permission denied:**
```
[error] [WifiServer] Failed to list WiFi adapters: "permission_denied: iw requires elevated privileges - see WIFI_PERMISSIONS.md for solutions"
```

## Common Operations and Required Permissions

| Operation | Command | Requires | Capability Needed |
|-----------|---------|----------|-------------------|
| List adapters | `iw dev` | root/netdev | CAP_NET_ADMIN |
| Create mesh interface | `iw dev wlan0 interface add mesh0 type mp` | root | CAP_NET_ADMIN |
| Join mesh | `iw dev mesh0 mesh join R2MESH freq 2437` | root | CAP_NET_ADMIN |
| Get IPv6 address | `ip -6 addr show mesh0` | user | None (read-only) |
| Bring interface up | `ip link set mesh0 up` | root | CAP_NET_ADMIN |
| Destroy interface | `iw dev mesh0 del` | root | CAP_NET_ADMIN |
| List mesh peers | `iw dev mesh0 station dump` | user/root | CAP_NET_ADMIN (some systems) |

## Recommended Setup by Environment

### Development (Local Machine)
**Recommended:** Solution 1 (netdev group) + Solution 2 (setcap)

```bash
# Add to netdev group
sudo usermod -aG netdev $USER

# Grant capabilities
sudo setcap cap_net_admin=eip $(which iw)
sudo setcap cap_net_admin,cap_net_raw=eip $(which ip)

# Log out and back in
```

### Production (Server/Embedded Device)
**Recommended:** Solution 2 (setcap) as application user

```bash
# Create dedicated user
sudo useradd -r -s /bin/false reality2

# Grant capabilities to binaries
sudo setcap cap_net_admin=eip /usr/sbin/iw
sudo setcap cap_net_admin,cap_net_raw=eip /sbin/ip

# Run application as reality2 user
sudo -u reality2 /opt/reality2/bin/reality2 start
```

### Docker/Container
**Recommended:** Host networking + capabilities

**docker-compose.yml:**
```yaml
services:
  reality2:
    image: reality2:latest
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun
    privileged: false  # Only use if cap_add doesn't work
```

**Dockerfile:**
```dockerfile
FROM elixir:1.19

# Install dependencies
RUN apt-get update && \
    apt-get install -y iw iproute2 wireless-tools && \
    rm -rf /var/lib/apt/lists/*

# Grant capabilities (done at runtime via cap_add instead)
# RUN setcap cap_net_admin=eip /usr/sbin/iw
# RUN setcap cap_net_admin,cap_net_raw=eip /sbin/ip

# ... rest of Dockerfile
```

### CI/CD Testing
**Recommended:** Solution 4 (run as root) - only for testing!

```yaml
# .github/workflows/test.yml
- name: Test WiFi mesh
  run: |
    sudo mix test
```

## Security Considerations

### CAP_NET_ADMIN Capability

This is a powerful capability that allows:
- ✅ Create/destroy network interfaces
- ✅ Configure network settings
- ✅ Modify routing tables
- ⚠️ **Also allows:** ARP spoofing, packet injection, etc.

**Mitigation:**
- Only grant to specific binaries (iw, ip)
- Don't grant to the entire application
- Use AppArmor or SELinux for additional restrictions

### netdev Group

Adding users to `netdev` group grants broad network permissions:
- ✅ Manage WiFi networks
- ✅ Configure interfaces
- ⚠️ May allow other network operations depending on polkit rules

**Mitigation:**
- Only add trusted users
- Combine with polkit rules for fine-grained control
- Review group permissions on your distribution

### Running as Root

**Never do this in production unless absolutely necessary!**

If you must:
- Use a container with resource limits
- Enable AppArmor/SELinux profiles
- Monitor for suspicious activity
- Consider using user namespaces

## Troubleshooting

### setcap doesn't persist after package update

Some package managers reset capabilities during updates.

**Solution:** Create a systemd service or cron job to reapply:

```bash
# Create /usr/local/bin/restore-network-caps.sh
#!/bin/bash
setcap cap_net_admin=eip /usr/sbin/iw
setcap cap_net_admin,cap_net_raw=eip /sbin/ip
echo "Network capabilities restored"

# Make executable
sudo chmod +x /usr/local/bin/restore-network-caps.sh

# Create systemd service
sudo tee /etc/systemd/system/restore-network-caps.service <<EOF
[Unit]
Description=Restore network capabilities for Reality2
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restore-network-caps.sh

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl enable restore-network-caps
sudo systemctl start restore-network-caps
```

### netdev group doesn't exist

Some distributions don't have a `netdev` group.

**Solution:** Create it:
```bash
sudo groupadd netdev
sudo usermod -aG netdev $USER
```

### Operations still fail with "Permission denied"

**Check:**
1. Did you log out and back in after adding to group?
   ```bash
   groups  # Should show netdev
   ```

2. Are capabilities set on the binary?
   ```bash
   getcap $(which iw)
   getcap $(which ip)
   ```

3. Is SELinux/AppArmor blocking operations?
   ```bash
   # Check SELinux status
   sestatus

   # Check AppArmor status
   sudo aa-status
   ```

4. Try with sudo to confirm it's a permission issue:
   ```bash
   sudo iw dev  # Should work
   ```

## References

- [Linux Capabilities man page](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [iw documentation](https://wireless.wiki.kernel.org/en/users/documentation/iw)
- [Polkit documentation](https://www.freedesktop.org/software/polkit/docs/latest/)
- [IEEE 802.11s mesh networking](https://wireless.wiki.kernel.org/en/developers/documentation/ieee80211/802.11s)

**Author:**
- Dr. Roy C. Davies
- [roycdavies.github.io](https://roycdavies.github.io/)
