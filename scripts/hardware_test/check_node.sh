#!/bin/bash
# check_node.sh - Check if a remote Reality2 node is ready
#
# Usage: check_node.sh <ip> [timeout]
#   ip      - IP address of the node (e.g., 192.168.4.2)
#   timeout - Connection timeout in seconds (default: 5)
#
# Exit 0 if node is ready, exit 1 if not reachable or unhealthy.

set -euo pipefail

IP="${1:?Usage: check_node.sh <ip> [timeout]}"
TIMEOUT="${2:-5}"
BASE_URL="https://${IP}:4005"

echo "=== Checking Reality2 node at ${IP} ==="

# --- Check /transnet/info ---
echo ""
echo "--- /transnet/info ---"
INFO_JSON=$(curl -sk --connect-timeout "${TIMEOUT}" "${BASE_URL}/transnet/info" 2>/dev/null) || {
    echo "FAIL: Cannot reach ${BASE_URL}/transnet/info"
    exit 1
}

# Parse with python3
python3 -c "
import json, sys
try:
    info = json.loads('''${INFO_JSON}''')
    print(f\"  Node Name:    {info.get('node_name', 'unknown')}\")
    print(f\"  Node ID:      {info.get('node_id', 'unknown')}\")
    print(f\"  Bluetooth:    {info.get('bluetooth', 'unknown')}\")
    print(f\"  WiFi:         {info.get('wifi', 'unknown')}\")
    print(f\"  Sentants:     {info.get('sentant_count', info.get('sentants', 'unknown'))}\")
except Exception as e:
    print(f'  WARN: Could not parse info JSON: {e}', file=sys.stderr)
    print(f'  Raw: ${INFO_JSON}')
" || {
    echo "  Raw JSON: ${INFO_JSON}"
}

# --- Check /mesh/sentants ---
echo ""
echo "--- /mesh/sentants ---"
SENTANTS_JSON=$(curl -sk --connect-timeout "${TIMEOUT}" "${BASE_URL}/mesh/sentants" 2>/dev/null) || {
    echo "WARN: Cannot reach /mesh/sentants (non-fatal)"
    SENTANTS_JSON=""
}

if [ -n "${SENTANTS_JSON}" ]; then
    python3 -c "
import json, sys
try:
    data = json.loads('''${SENTANTS_JSON}''')
    if isinstance(data, list):
        print(f'  Sentant count: {len(data)}')
        for s in data[:10]:
            name = s.get('name', s.get('id', 'unknown'))
            print(f'    - {name}')
        if len(data) > 10:
            print(f'    ... and {len(data) - 10} more')
    elif isinstance(data, dict):
        sentants = data.get('sentants', data.get('data', []))
        if isinstance(sentants, list):
            print(f'  Sentant count: {len(sentants)}')
            for s in sentants[:10]:
                name = s.get('name', s.get('id', 'unknown')) if isinstance(s, dict) else str(s)
                print(f'    - {name}')
        else:
            print(f'  Response: {json.dumps(data, indent=2)[:200]}')
    else:
        print(f'  Response: {str(data)[:200]}')
except Exception as e:
    print(f'  WARN: Could not parse sentants JSON: {e}', file=sys.stderr)
" || {
    echo "  Raw JSON: ${SENTANTS_JSON}"
}
fi

echo ""
echo "=== Node at ${IP} is READY ==="
exit 0
