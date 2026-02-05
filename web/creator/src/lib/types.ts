// Core Reality2 Types

export type Event = {
  event: string;
  parameters: Record<string, unknown>;
};

export type Sentant = {
  id: string;
  name: string;
  description: string;
  events: Event[];
  signals: string[];
  // Node attribution - identifies which R2 node owns this sentant
  // Note: Uses camelCase to match GraphQL response (Absinthe converts snake_case to camelCase)
  nodeId?: string;   // UUID of the owning node
  nodeName?: string; // Human-readable name (e.g., "R2Node_A0BC")
};

export type Location = {
  latitude: number;
  longitude: number;
  altitude?: number | null;
  accuracy?: number | null;
  altitudeAccuracy?: number | null;
  heading?: number | null;
  speed?: number | null;
};

export type GraphQLResponse<T = unknown> = {
  data?: T;
  errors?: Array<{
    message: string;
    locations?: Array<{ line: number; column: number }>;
    path?: Array<string | number>;
  }>;
};

export type SentantGetResponse = {
  data?: {
    sentantGet: Sentant | null;
  };
};

export type SentantAllResponse = {
  data?: {
    sentantAll: Sentant[];
  };
};

export type SentantLoadResponse = {
  data?: {
    sentantLoad: Sentant | null;
  };
};

export type SignalData = {
  status?: string;
  event?: string;
  parameters?: Record<string, unknown>;
};

export type JoinRequestNotification = {
  status?: string;
  requestId?: string;
  nodeId?: string;
  nodeName?: string;
  nodePublicKey?: string;
  submittedAt?: number;
  source?: string;
};

export type ProximityNotification = {
  status?: string;
  nodeId?: string;
  nodeName?: string;
  rssi?: number;
  proximity?: string;
  timestamp?: number;
};

export type BackupPromptNotification = {
  status?: string;
  deviceName?: string;
  trustGroupName?: string;
  trustGroupId?: string;
  timestamp?: number;
};

export type WebSocketMessage = {
  topic: string;
  event: string;
  payload: Record<string, unknown>;
  ref: number;
};

export type SocketState = {
  ws: WebSocket;
  connected: boolean;
  timer: number | null;
};

export type LoadState = "loading" | "start" | "id" | "name" | "error" | "grid" | "map" | "construct" | "swarm" | "mr";

export type LoadResult = {
  state: LoadState;
  data: Sentant[] | Sentant | [];
};

// File System Access API types (for browser file picker)
export interface FileSystemFileHandle {
  getFile(): Promise<File>;
  createWritable(): Promise<FileSystemWritableFileStream>;
}

export interface FileSystemWritableFileStream extends WritableStream {
  write(data: string | BufferSource | Blob): Promise<void>;
  close(): Promise<void>;
}

// Window extensions
declare global {
  interface Window {
    showSaveFilePicker?: (options?: {
      suggestedName?: string;
      types?: Array<{
        description: string;
        accept: Record<string, string[]>;
      }>;
    }) => Promise<FileSystemFileHandle>;
  }
}
