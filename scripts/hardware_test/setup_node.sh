#!/bin/bash
# setup_node.sh - Start a Reality2 node on the device with hardware test sentants
#
# Usage: setup_node.sh <node_name> [env]
#   node_name - Name for this node (e.g., SBC1, SBC2, Unihiker)
#   env       - Mix environment (default: dev)
#
# Run this script ON the device itself after cloning/pulling the repo.

set -euo pipefail

NODE_NAME="${1:?Usage: setup_node.sh <node_name> [env]}"
MIX_ENV="${2:-dev}"

echo "=== Setting up Reality2 node: ${NODE_NAME} (${MIX_ENV}) ==="

# Navigate to project root (resolve symlinks first)
SCRIPT_PATH="$(readlink -f "$0")"
cd "$(dirname "$SCRIPT_PATH")/../.."

echo "Working directory: $(pwd)"

# Environment variables
export R2_NODE_NAME="${NODE_NAME}"
export MIX_ENV="${MIX_ENV}"
export PLUGINS="ai.reality2.vars"
export LOCKED="remote"

echo "  R2_NODE_NAME: ${R2_NODE_NAME}"
echo "  MIX_ENV:      ${MIX_ENV}"
echo "  PLUGINS:      ${PLUGINS}"
echo "  LOCKED:       ${LOCKED}"

# Copy hardware test sentants into autostart/
echo ""
echo "--- Copying hardware test sentants ---"
if [ -d "autostart/hardware_test" ]; then
    cp -v autostart/hardware_test/*.bee.yaml autostart/
    echo "  Hardware test sentants copied to autostart/"
else
    echo "  WARN: autostart/hardware_test/ not found, skipping sentant copy"
fi

# Create mnesia directory
echo ""
echo "--- Creating mnesia directory ---"
mkdir -p ".mnesia/${MIX_ENV}"
echo "  Created .mnesia/${MIX_ENV}"

# Fetch dependencies if needed
echo ""
echo "--- Checking dependencies ---"
mix deps.get

# Start the node
echo ""
echo "=== Starting Reality2 node: ${NODE_NAME} ==="
echo "    URL: https://localhost:4005"
echo ""
iex -S mix phx.server
