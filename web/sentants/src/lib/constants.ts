/**
 * Application-wide constants
 */

// Network Configuration
export const DEFAULT_PORT = "4005";
export const WEBSOCKET_HEARTBEAT_INTERVAL_MS = 30000; // 30 seconds
export const WEBSOCKET_INIT_DELAY_MS = 100;
export const MONITOR_INIT_DELAY_MS = 100;

// UI Configuration
export const MESSAGE_BUFFER_SIZE = 5;
export const DEFAULT_MAP_HEIGHT_PX = 400;
export const HEADER_HEIGHT_PX = 64;
export const CARDS_HEADER_HEIGHT_PX = 80;

// Default Geographic Location (Wairoa, New Zealand)
export const DEFAULT_LOCATION = {
  latitude: -39.03333,
  longitude: 177.36667,
  altitude: 0,
} as const;

// Map Configuration
export const MAP_ZOOM_LEVEL_DEFAULT = 5;
export const MAP_ZOOM_LEVEL_WITH_LOCATION = 13;

// Mapbox Configuration
export const MAPBOX_TILE_SIZE = 512;
export const MAPBOX_ZOOM_OFFSET = -1;

// Special Sentant Names (reserved/system sentants)
export const RESERVED_SENTANT_NAMES = {
  MONITOR: "monitor",
  DELETED: ".deleted",
  VIEW: "view",
} as const;
