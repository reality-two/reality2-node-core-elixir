# Transient Network Visualization

Interactive visualization demonstrating how Reality2 nodes discover each other and form a transient network.

## What It Shows

1. **Idle State** - Devices with their local Sentants
2. **BLE Beacons** - Devices broadcasting their presence
3. **Discovery** - Nodes detecting each other
4. **Host Negotiation** - Best candidate becomes WiFi host (based on priority)
5. **WiFi Connection** - Devices connect to the host's hotspot
6. **Sentant Exchange** - Capabilities are shared across the network
7. **Dynamic Joining** - New device joins seamlessly

## Usage

Open `index.html` in any browser, or access via the Reality2 server at:
```
http://localhost:4005/transnet-viz
```

### Controls
- **Next Step** - Progress through the animation manually
- **Auto Play** - Automatic progression (3 second intervals)
- **Reset** - Start over

## Deployment

```bash
# From the scripts folder:
cd scripts
./build_webapp transnet-viz
```

## Technical Notes

- Pure HTML/CSS/JavaScript - no dependencies
- Works offline
- Responsive design for mobile/desktop
- No build step required
