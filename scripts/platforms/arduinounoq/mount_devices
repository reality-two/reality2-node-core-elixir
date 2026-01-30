#!/usr/bin/env bash
set -euo pipefail

# Local base directory for mounts
BASE_MOUNT="${BASE_MOUNT:-$HOME/adb-mount}"

# Remote root on the device to expose (your requirement)
REMOTE_ROOT="${REMOTE_ROOT:-/home/arduino}"

# Optional: log directory
LOG_DIR="${LOG_DIR:-$HOME/.cache/adbfs}"
mkdir -p "$LOG_DIR"

# Ensure base mount directory exists
mkdir -p "$BASE_MOUNT"

# Helper: check if a mountpoint is currently mounted
is_mounted() {
  local mp="$1"
  # mountpoint(1) is common; fall back to findmnt if needed
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$mp"
  else
    findmnt -rno TARGET "$mp" >/dev/null 2>&1
  fi
}

# Get serials for devices in "device" state
mapfile -t SERIALS < <(
  adb devices | awk 'NR>1 && $2=="device" {print $1}'
)

if [[ ${#SERIALS[@]} -eq 0 ]]; then
  echo "No ADB devices in 'device' state."
  echo "If you see 'unauthorized' or 'offline', resolve that first (unlock device / replug / accept RSA prompt)."
  exit 0
fi

echo "Mount base:   $BASE_MOUNT"
echo "Remote root:  $REMOTE_ROOT"
echo "Devices:      ${SERIALS[*]}"
echo

for serial in "${SERIALS[@]}"; do
  mp="$BASE_MOUNT/$serial"
  mkdir -p "$mp"

  if is_mounted "$mp"; then
    echo "Already mounted: $serial -> $mp"
    continue
  fi

  echo "Mounting: $serial -> $mp"
  # Run in background; log per device
  # NOTE: adbfs stays in foreground normally; backgrounding keeps the shell usable.
  nohup adbfs --device "$serial" --mountpoint "$mp" --device-root "$REMOTE_ROOT" \
    >"$LOG_DIR/adbfs-$serial.log" 2>&1 &
done

echo
echo "Done. Mounts should appear under: $BASE_MOUNT/<serial>/"

