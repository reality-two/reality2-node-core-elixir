import type {
  Event,
  Sentant,
  GraphQLResponse,
  SignalData,
  WebSocketMessage,
  SocketState,
  JoinRequestNotification,
  ProximityNotification,
  BackupPromptNotification,
} from "./types";
import {
  DEFAULT_PORT,
  WEBSOCKET_HEARTBEAT_INTERVAL_MS,
  WEBSOCKET_INIT_DELAY_MS,
  RESERVED_SENTANT_NAMES,
} from "./constants";

export type { Event, Sentant };

/**
 * Reality2 GraphQL Client
 *
 * Provides a client interface for interacting with Reality2 Sentants via GraphQL.
 * Supports queries, mutations, and WebSocket subscriptions for real-time updates.
 *
 * @example
 * ```typescript
 * const r2 = new R2("localhost", 4005, true);
 * const result = await r2.sentantAll({}, "id name description");
 * ```
 */
export default class R2 {
  _secure: boolean = false;
  _graphql_http_url: string = `https://localhost:${DEFAULT_PORT}/reality2`;
  _graphql_webs_url: string = `wss://localhost:${DEFAULT_PORT}/reality2/websocket`;

  _sockets: {
    [index: string]: SocketState;
  } = {};

  /**
   * Creates a new Reality2 client instance
   *
   * @param domain_name - The hostname or IP address of the Reality2 server
   * @param port - The port number the Reality2 server is listening on
   * @param ssl - Whether to use SSL/TLS for connections (default: true)
   *
   * @example
   * ```typescript
   * const r2 = new R2("localhost", 4005);  // HTTPS/WSS
   * const r2_insecure = new R2("192.168.1.100", 4005, false);  // HTTP/WS
   * ```
   */
  constructor(domain_name: string, port: number, ssl = true) {
    this._secure = ssl;
    if (ssl) {
      this._graphql_http_url =
        "https://" + domain_name + ":" + port + "/reality2";
      this._graphql_webs_url =
        "wss://" + domain_name + ":" + port + "/reality2/websocket";
    } else {
      this._graphql_http_url =
        "http://" + domain_name + ":" + port + "/reality2";
      this._graphql_webs_url =
        "ws://" + domain_name + ":" + port + "/reality2/websocket";
    }
  }
  // ----------------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------------
  // Public API
  // ----------------------------------------------------------------------------------------------------

  /**
   * Retrieve all sentants from the Reality2 server
   *
   * @param passthrough - Additional data to merge into the response
   * @param details - GraphQL fields to retrieve (default: "id name")
   * @returns Promise resolving to GraphQL response merged with passthrough data
   *
   * @example
   * ```typescript
   * const result = await r2.sentantAll({}, "id name description events { event }");
   * const sentants = result.data.sentantAll;
   * ```
   */
  sentantAll(passthrough = {}, details: string = "id name nodeId nodeName"): Promise<object> {
    return this._graphql_post(this._sentantAll(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Retrieve this node's identity and trust group information.
   */
  nodeInfo(passthrough = {}, details: string = "nodeId nodeName trustGroupId trustGroupName trustGroupMode trustGroupCompressedId version buildId"): Promise<object> {
    return this._graphql_post(this._nodeInfo(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Retrieve discovered peers from the mesh.
   */
  peers(passthrough = {}, details: string = "nodeId nodeName transport address rssi connectionState trustGroupId isSameTrustGroup trustGroupVerified sentantCount lastSeen reachability { ble { lastSeen confidence rssi } wifi { lastSeen confidence ip } lora { lastSeen confidence } }"): Promise<object> {
    return this._graphql_post(this._peers(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Retrieve the trust group directory.
   */
  trustGroupDirectory(passthrough = {}, details: string = "trustGroupId trustGroupName myNodeId directoryVersion nodes { nodeId name status trustGroupId sentants { id name } reachability { ble { lastSeen confidence rssi } wifi { lastSeen confidence ip } lora { lastSeen confidence } } updatedAt }"): Promise<object> {
    return this._graphql_post(this._trustGroupDirectory(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Create (or reset) a trust group with the given name.
   */
  trustGroupCreate(name: string, passthrough = {}, details: string = "trustGroupId trustGroupName trustGroupMode isProvisional"): Promise<object> {
    return this._graphql_post(this._trustGroupCreate(details), { name })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Mark the current provisional trust group as established.
   */
  trustGroupMarkEstablished(passthrough = {}, details: string = "trustGroupId trustGroupName trustGroupMode isProvisional"): Promise<object> {
    return this._graphql_post(this._trustGroupMarkEstablished(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Generate a 4-character join code for other nodes.
   */
  trustGroupGenerateJoinCode(passthrough = {}, details: string = "code expiresIn"): Promise<object> {
    return this._graphql_post(this._trustGroupGenerateJoinCode(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Export the trust group key encrypted with a passphrase.
   */
  trustGroupExportKey(passphrase: string, passthrough = {}, details: string = "encryptedData"): Promise<object> {
    return this._graphql_post(this._trustGroupExportKey(details), { passphrase })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Import an encrypted trust group key.
   */
  trustGroupImportKey(encryptedData: string, passphrase: string, passthrough = {}, details: string = "trustGroupId trustGroupName trustGroupMode isProvisional"): Promise<object> {
    return this._graphql_post(this._trustGroupImportKey(details), { encryptedData, passphrase })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Get this node's public key (base64-encoded).
   */
  trustGroupGetPublicKey(passthrough = {}): Promise<object> {
    return this._graphql_post(this._trustGroupGetPublicKey(), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Process a join request (called on key holder node).
   */
  trustGroupProcessJoinRequest(code: string, nodeName: string, nodePublicKey: string, passthrough = {}, details: string = "certificate trustGroupPublicInfo"): Promise<object> {
    return this._graphql_post(this._trustGroupProcessJoinRequest(details), { code, nodeName, nodePublicKey })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Finalize joining a trust group as a member (called on joining node).
   */
  trustGroupJoinAsMember(trustGroupPublicInfo: object, certificate: object, passthrough = {}, details: string = "trustGroupId trustGroupName trustGroupMode isProvisional"): Promise<object> {
    return this._graphql_post(this._trustGroupJoinAsMember(details), { trustGroupPublicInfo: JSON.stringify(trustGroupPublicInfo), certificate: JSON.stringify(certificate) })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Submit a join request to a key holder node.
   */
  trustGroupSubmitJoinRequest(nodeName: string, nodePublicKey: string, passthrough = {}, details: string = "id nodeName nodePublicKey status submittedAt"): Promise<object> {
    return this._graphql_post(this._trustGroupSubmitJoinRequest(details), { nodeName, nodePublicKey })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Get pending join requests (key holder).
   */
  trustGroupPendingJoinRequests(passthrough = {}, details: string = "id nodeName nodePublicKey status submittedAt"): Promise<object> {
    return this._graphql_post(this._trustGroupPendingJoinRequests(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Get all approved trust group members (nodes and viewers).
   */
  trustGroupMembers(memberType: string | null = null, passthrough = {}, details: string = "nodeId nodeName nodePublicKey memberType approvedAt"): Promise<object> {
    return this._graphql_post(this._trustGroupMembers(details, memberType), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Clear stale entries from the trust group directory.
   * Removes entries not updated in over 1 hour.
   */
  trustGroupDirectoryClearStale(passthrough = {}): Promise<object> {
    return this._graphql_post(this._trustGroupDirectoryClearStale(), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Remove a member from the trust group (key holder only).
   */
  trustGroupRemoveMember(nodeId: string, passthrough = {}): Promise<object> {
    return this._graphql_post(this._trustGroupRemoveMember(), { nodeId })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * List known trust group key holders.
   */
  keyHolders(passthrough = {}, details: string = "nodeId nodeName deviceName registeredAt lastSeen isLocal"): Promise<object> {
    return this._graphql_post(this._keyHolders(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * List trusted groups (inter-group federation).
   */
  trustedGroups(passthrough = {}, details: string = "trustGroupId name publicKey permissions establishedAt expiresAt sentantFilter status"): Promise<object> {
    return this._graphql_post(this._trustedGroups(details), {})
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Generate a trust token to share with another trust group.
   */
  trustGenerateToken(permissions: string[] = ["read_only"], passthrough = {}, details: string = "token trustGroupId trustGroupName expiresAt expiresIn"): Promise<object> {
    return this._graphql_post(this._trustGenerateToken(details), { permissions })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Establish trust with another trust group.
   */
  trustEstablish(trustGroupId: string, trustGroupPublicKey: string, trustGroupName?: string, permissions: string[] = ["read_only"], passthrough = {}): Promise<object> {
    return this._graphql_post(this._trustEstablish(), { trustGroupId, trustGroupPublicKey, trustGroupName, permissions })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Revoke trust with another trust group.
   */
  trustRevoke(trustGroupId: string, passthrough = {}): Promise<object> {
    return this._graphql_post(this._trustRevoke(), { trustGroupId })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Approve a join request (key holder).
   */
  trustGroupApproveJoinRequest(requestId: string, passthrough = {}, details: string = "certificate trustGroupPublicInfo"): Promise<object> {
    return this._graphql_post(this._trustGroupApproveJoinRequest(details), { requestId })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Deny a join request (key holder).
   */
  trustGroupDenyJoinRequest(requestId: string, passthrough = {}): Promise<object> {
    return this._graphql_post(this._trustGroupDenyJoinRequest(), { requestId })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Check status of a join request (joiner polls this on key holder).
   */
  trustGroupJoinRequestStatus(requestId: string, passthrough = {}, details: string = "status certificate trustGroupPublicInfo"): Promise<object> {
    return this._graphql_post(this._trustGroupJoinRequestStatus(details), { requestId })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Submit a trust group join request via BLE GATT (called on the joiner node).
   */
  trustGroupBleSubmitJoinRequest(peerId: string, nodeName: string, passthrough = {}, details: string = "status trustGroupId message"): Promise<object> {
    return this._graphql_post(this._trustGroupBleSubmitJoinRequest(details), { peerId, nodeName })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Check the status of a BLE-based trust group join request.
   */
  trustGroupBleJoinRequestStatus(peerId: string, passthrough = {}, details: string = "status trustGroupId message"): Promise<object> {
    return this._graphql_post(this._trustGroupBleJoinRequestStatus(details), { peerId })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  /**
   * Retrieve a specific sentant by ID
   *
   * @param id - The unique identifier of the sentant
   * @param passthrough - Additional data to merge into the response
   * @param details - GraphQL fields to retrieve (default: "id name")
   * @returns Promise resolving to GraphQL response merged with passthrough data
   *
   * @example
   * ```typescript
   * const result = await r2.sentantGet("abc123", {}, "id name description signals");
   * const sentant = result.data.sentantGet;
   * ```
   */
  sentantGet(id: string, passthrough = {}, details: string = "id name"): Promise<object> {
    return this._graphql_post(this._sentantGet(details), { id })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  sentantGetByName(name: string, passthrough = {}, details: string = "id name"): Promise<object> {
    return this._graphql_post(this._sentantGetByName(details), { name })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  sentantLoad(definition: string, passthrough = {}, details: string = "id name"): Promise<object> {
    return this._graphql_post(this._sentantLoad(details), { definition })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  sentantUnload(id: string, passthrough = {}, details: string = "id name"): Promise<object> {
    return this._graphql_post(this._sentantUnload(details), { id })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }

  swarmLoad(definition: string, passthrough = {}, details: string = "id name"): Promise<object> {
    return this._graphql_post(this._swarmLoad(details), { definition })
      .then((data: GraphQLResponse) => ({ ...passthrough, ...data }));
  }
  sentantSend(
    path: string,
    event: string,
    params: object,
    passthrough: object = {},
    details: string = "id name",
  ): Promise<object> {
    return this._graphql_post(this._sentandSend(details), {
      path: path,
      event: event,
      parameters: JSON.stringify(params),
      passthrough: JSON.stringify(passthrough),
    });
  }

  /**
   * Subscribe to signals from a sentant via WebSocket
   *
   * Creates a persistent WebSocket connection to listen for signals from a specific sentant.
   * The callback will be invoked each time the sentant emits the specified signal.
   *
   * @param id - The unique identifier of the sentant to listen to
   * @param signal - The name of the signal to await
   * @param callback - Function to call when signal is received
   *
   * @example
   * ```typescript
   * r2.awaitSignal("abc123", "position_update", (data) => {
   *   console.log("Position:", data.parameters);
   * });
   * ```
   */
  awaitSignal(id: string, signal: string, callback: (data: SignalData) => void = () => {}): void {
    this._subscribe(id, signal, callback);
  }

  /**
   * Unsubscribe from a signal subscription
   *
   * Closes the websocket connection and cleans up resources for the specified
   * sentant/signal combination.
   *
   * @param id - The sentant UUID to unsubscribe from
   * @param signal - The signal name to unsubscribe from
   */
  unsubscribe(id: string, signal: string): void {
    const key = id + "|" + signal;
    if (this._sockets[key]) {
      if (this._sockets[key].timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
      if (this._sockets[key].ws) {
        this._sockets[key].ws.close();
      }
      delete this._sockets[key];
    }
  }

  /**
   * Subscribe to join request notifications (key holder only)
   *
   * Creates a persistent WebSocket connection to listen for incoming join requests.
   * The callback will be invoked each time a new join request arrives.
   *
   * @param callback - Function to call when a join request is received
   *
   * @example
   * ```typescript
   * r2.onJoinRequestReceived((data) => {
   *   console.log("Join request from:", data.nodeName);
   * });
   * ```
   */
  onJoinRequestReceived(callback: (data: JoinRequestNotification) => void = () => {}): void {
    this._subscribeJoinRequests(callback);
  }

  /**
   * Unsubscribe from join request notifications
   */
  unsubscribeJoinRequests(): void {
    const key = "trust_group:join_requests";
    if (this._sockets[key]) {
      if (this._sockets[key].timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
      if (this._sockets[key].ws) {
        this._sockets[key].ws.close();
      }
      delete this._sockets[key];
    }
  }

  /**
   * Subscribe to proximity device notifications (key holder only)
   *
   * Creates a persistent WebSocket connection to listen for nearby devices.
   * The callback will be invoked when a device comes very close (RSSI > -50dBm).
   *
   * @param callback - Function to call when a proximity event is received
   */
  onProximityDeviceDetected(callback: (data: ProximityNotification) => void = () => {}): void {
    this._subscribeProximity(callback);
  }

  /**
   * Unsubscribe from proximity notifications
   */
  unsubscribeProximity(): void {
    const key = "trust_group:proximity";
    if (this._sockets[key]) {
      if (this._sockets[key].timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
      if (this._sockets[key].ws) {
        this._sockets[key].ws.close();
      }
      delete this._sockets[key];
    }
  }

  /**
   * Subscribe to backup prompt notifications (key holder only)
   *
   * Creates a persistent WebSocket connection to listen for backup prompts.
   * The callback will be invoked when the first device is approved, prompting
   * the key holder to back up their trust group key.
   *
   * @param callback - Function to call when a backup prompt is received
   */
  onBackupPromptReceived(callback: (data: BackupPromptNotification) => void = () => {}): void {
    this._subscribeBackupPrompt(callback);
  }

  /**
   * Unsubscribe from backup prompt notifications
   */
  unsubscribeBackupPrompt(): void {
    const key = "trust_group:backup_prompt";
    if (this._sockets[key]) {
      if (this._sockets[key].timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
      if (this._sockets[key].ws) {
        this._sockets[key].ws.close();
      }
      delete this._sockets[key];
    }
  }

  /**
   * Monitor the Reality2 node for sentant lifecycle events
   *
   * Sets up monitoring for sentant creation/deletion events at the node level.
   * Useful for keeping UI in sync with server-side changes.
   *
   * @param callback - Function to call when sentants are created/deleted
   *
   * @example
   * ```typescript
   * r2.monitor((data) => {
   *   if (data.parameters?.activity === "created") {
   *     console.log("New sentant:", data.parameters.name);
   *   }
   * });
   * ```
   */
  monitor(callback: (data: GraphQLResponse) => void = () => {}): void {
    this._set_up_node_monitoring(callback);
  }

  /**
   * Navigate a JSON object using dot notation path
   *
   * @param data - The object to navigate
   * @param path - Dot-separated path (e.g., "data.sentantGet.name")
   * @returns The value at the path, or null if not found
   *
   * @example
   * ```typescript
   * const obj = { data: { sentantGet: { name: "test" } } };
   * R2.JSONPath(obj, "data.sentantGet.name");  // Returns: "test"
   * ```
   */
  public static JSONPath(data: object, path: string): unknown {
    let parts = path.split(".");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let result: any = data;
    for (let i = 0; i < parts.length; i++) {
      let index = parseInt(parts[i]);
      if (isNaN(index)) {
        if (result.hasOwnProperty(parts[i])) {
          result = result[parts[i]];
        } else {
          return null;
        }
      } else {
        if (Array.isArray(result)) {
          result = result[index];
        } else {
          return null;
        }
      }
    }
    return result;
  }

  public static ToSimple(variable: unknown): unknown {
    return this.convert(variable, true);
  }
  public static ToJSON(variable: unknown): unknown {
    return this.convert(variable, false);
  }

  public static convert(variable: unknown, no_json = true): unknown {
    if (variable == null) return null;

    if (typeof variable === "number") {
      return variable; // It's already a number
    }

    if (typeof variable === "boolean") {
      return variable; // It's already a boolean
    }

    if (typeof variable === "string") {
      variable = variable.replace(/^['"]+|['"]+$/g, "");

      // First, check if it's a boolean string
      if (variable.toLowerCase() === "true") {
        return true;
      }
      if (variable.toLowerCase() === "false") {
        return false;
      }

      // Next, check if it's a numeric string
      const num = Number(variable);
      if (!isNaN(num)) {
        return num; // Convert string to number if it's a valid number
      }

      // Finally, try to parse it as JSON
      try {
        const parsed = JSON.parse(variable);

        if (typeof parsed === "object" && parsed !== null) {
          if (no_json)
            return JSON.stringify(parsed); // Return the parsed JSON object or array back as a string
          else return parsed; // Return as JSON
        }
      } catch (e) {
        // If it's not valid JSON, return the string as is
      }

      return variable; // Return the original string if none of the above
    }

    if (Array.isArray(variable)) {
      if (no_json)
        return JSON.stringify(variable); // Convert the array to a JSON string
      else return variable;
    }

    if (typeof variable === "object" && variable !== null) {
      if (no_json) return JSON.stringify(variable);
      else return variable; // Return the object as is
    }

    // Fallback: return the variable as a string
    return String(variable);
  }
  // ----------------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------------
  // Monitoring Sentant
  // ----------------------------------------------------------------------------------------------------
  _set_up_node_monitoring(callback: (data: GraphQLResponse) => void = () => {}): void {
    let details = {
      sentant: {
        name: "monitor",
        automations: [
          {
            name: "Monitor",
            transitions: [
              {
                event: "__internal",
                actions: [
                  {
                    command: "signal",
                    parameters: { public: true, event: "internal" },
                  },
                ],
              },
            ],
          },
        ],
      },
    };

    this.sentantGetByName("monitor").then((data1: GraphQLResponse) => {
      const sentantGet = R2.JSONPath(data1, "data.sentantGet") as Sentant | null;
      if (sentantGet == null) {
        this.sentantLoad(JSON.stringify(details)).then((data2: GraphQLResponse) => {
          const sentantLoad = R2.JSONPath(data2, "data.sentantLoad") as Sentant;
          this.awaitSignal(
            sentantLoad.id,
            "internal",
            (data3: SignalData) => {
              callback(data3);
            },
          );
          console.log("Monitor Sentant Loaded");
        });
      } else {
        this.awaitSignal(sentantGet.id, "internal", (data4: SignalData) => {
          callback(data4);
        });
        console.log("Monitor Sentant Loaded");
      }
    });
  }
  // ----------------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------------
  // GraphQL POST
  // ----------------------------------------------------------------------------------------------------
  _graphql_post(query: string, variables: object): Promise<object> {
    let body = {
      query: query,
      variables: variables,
    };

    let parameters = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "*/*",
      },
      body: JSON.stringify(body),
    };

    return fetch(this._graphql_http_url, parameters)
      .then((response) => {
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return response.json();
      });
  }
  // ----------------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------------
  // Websocket Subscription
  // ----------------------------------------------------------------------------------------------------
  _subscribe(id: string, signal: string, callback: (data: SignalData) => void): void {
    let join_message = {
      topic: "__absinthe__:control",
      event: "phx_join",
      payload: {},
      ref: 0,
    };

    let subscribe = {
      topic: "__absinthe__:control",
      event: "doc",
      payload: {
        query: this._awaitSignal("event parameters"),
        variables: {
          id: id,
          signal: signal,
        },
      },
      ref: 0,
    };

    let heartbeat = {
      topic: "phoenix",
      event: "heartbeat",
      payload: {},
      ref: 0,
    };

    this._sockets[id + "|" + signal] = {
      ws: new WebSocket(this._graphql_webs_url),
      connected: false,
      timer: null,
    };

    this._sockets[id + "|" + signal].ws.onopen = () => {
      setTimeout(() => {
        this._sockets[id + "|" + signal].ws.send(JSON.stringify(join_message));
      }, WEBSOCKET_INIT_DELAY_MS);
    };

    this._sockets[id + "|" + signal].ws.onmessage = (event: MessageEvent) => {
      let data = JSON.parse(event.data);
      let payload = data.payload;

      if (this._sockets[id + "|" + signal].connected) {
        if (payload.result) {
          let result = payload.result;
          if (result.hasOwnProperty("data")) {
            let data = result.data.awaitSignal;
            callback(data);
          }
        }
      } else {
        if (data.event == "phx_reply" && data.payload.status == "ok") {
          console.log("Websocket connected");
          this._sockets[id + "|" + signal].ws.send(JSON.stringify(subscribe));
          this._sockets[id + "|" + signal].connected = true;

          this._sockets[id + "|" + signal].timer = setInterval(() => {
            this._sockets[id + "|" + signal].ws.send(JSON.stringify(heartbeat));
          }, WEBSOCKET_HEARTBEAT_INTERVAL_MS);

          callback({ status: "connected" });
        }
      }
    };

    // Clean up timer when websocket closes
    this._sockets[id + "|" + signal].ws.onclose = () => {
      console.log("Websocket closed");
      if (this._sockets[id + "|" + signal]?.timer) {
        clearInterval(this._sockets[id + "|" + signal].timer);
        this._sockets[id + "|" + signal].timer = null;
      }
    };

    // Clean up timer on websocket error
    this._sockets[id + "|" + signal].ws.onerror = (error: Event) => {
      console.error("Websocket error:", error);
      if (this._sockets[id + "|" + signal]?.timer) {
        clearInterval(this._sockets[id + "|" + signal].timer);
        this._sockets[id + "|" + signal].timer = null;
      }
    };
  }

  _subscribeJoinRequests(callback: (data: JoinRequestNotification) => void): void {
    const key = "trust_group:join_requests";

    let join_message = {
      topic: "__absinthe__:control",
      event: "phx_join",
      payload: {},
      ref: 0,
    };

    let subscribe = {
      topic: "__absinthe__:control",
      event: "doc",
      payload: {
        query: this._joinRequestReceivedSubscription(),
        variables: {},
      },
      ref: 0,
    };

    let heartbeat = {
      topic: "phoenix",
      event: "heartbeat",
      payload: {},
      ref: 0,
    };

    this._sockets[key] = {
      ws: new WebSocket(this._graphql_webs_url),
      connected: false,
      timer: null,
    };

    this._sockets[key].ws.onopen = () => {
      setTimeout(() => {
        this._sockets[key].ws.send(JSON.stringify(join_message));
      }, WEBSOCKET_INIT_DELAY_MS);
    };

    this._sockets[key].ws.onmessage = (event: MessageEvent) => {
      let data = JSON.parse(event.data);
      let payload = data.payload;

      if (this._sockets[key].connected) {
        if (payload.result) {
          let result = payload.result;
          if (result.hasOwnProperty("data")) {
            let notification = result.data.joinRequestReceived;
            callback(notification);
          }
        }
      } else {
        if (data.event == "phx_reply" && data.payload.status == "ok") {
          console.log("Join request subscription connected");
          this._sockets[key].ws.send(JSON.stringify(subscribe));
          this._sockets[key].connected = true;

          this._sockets[key].timer = setInterval(() => {
            this._sockets[key].ws.send(JSON.stringify(heartbeat));
          }, WEBSOCKET_HEARTBEAT_INTERVAL_MS);

          callback({ status: "connected" });
        }
      }
    };

    this._sockets[key].ws.onclose = () => {
      console.log("Join request subscription closed");
      if (this._sockets[key]?.timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
    };

    this._sockets[key].ws.onerror = (error: Event) => {
      console.error("Join request subscription error:", error);
      if (this._sockets[key]?.timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
    };
  }
  // ----------------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------------
  // GraphQL Queries and Mutations
  // ----------------------------------------------------------------------------------------------------
  _nodeInfo(details: string): string {
    return `{
            nodeInfo {
                ${details}
            }
        }`;
  }

  _peers(details: string): string {
    return `{
            peers {
                ${details}
            }
        }`;
  }

  _trustGroupDirectory(details: string): string {
    return `{
            trustGroupDirectory {
                ${details}
            }
        }`;
  }

  _sentantAll(details: string): string {
    return `{
            sentantAll {
                ${details}
            }
        }`;
  }

  _sentantGet(details: string): string {
    return `query SentantGet($id: UUID4!) {
            sentantGet(id: $id) {
                ${details}
            }
        }`;
  }

  _sentantGetByName(details: string): string {
    return `query SentantGet($name: String!) {
            sentantGet(name: $name) {
                ${details}
            }
        }`;
  }

  _sentantLoad(details: string): string {
    return `mutation SentantLoad($definition: String!) {
            sentantLoad(definition: $definition) {
                ${details}
            }
        }`;
  }

  _sentantUnload(details: string): string {
    return `mutation SentantUnload($id: UUID4!) {
            sentantUnload(id: $id) {
                ${details}
            }
        }`;
  }

  _swarmLoad(details: string): string {
    return `mutation SwarmLoad($definition: String!) {
            swarmLoad(definition: $definition) {
                description
                name
                sentants {
                    ${details}
                }
            }
        }`;
  }

  _sentandSend(details: string): string {
    return `mutation SentantSend($path: String!, $event: String!, $parameters: Json, $passthrough: Json) {
            sentantSend(path: $path, event: $event, parameters: $parameters, passthrough: $passthrough) {
                ${details}
            }
        }`;
  }

  _awaitSignal(details: string = "id name"): string {
    return `subscription AwaitSignal($id: UUID4!, $signal: String!) {
            awaitSignal(id: $id, signal: $signal) {
                ${details}
            }
        }`;
  }

  _trustGroupCreate(details: string): string {
    return `mutation TrustGroupCreate($name: String!) {
            trustGroupCreate(name: $name) {
                ${details}
            }
        }`;
  }

  _trustGroupMarkEstablished(details: string): string {
    return `mutation TrustGroupMarkEstablished {
            trustGroupMarkEstablished {
                ${details}
            }
        }`;
  }

  _trustGroupGenerateJoinCode(details: string): string {
    return `mutation TrustGroupGenerateJoinCode {
            trustGroupGenerateJoinCode {
                ${details}
            }
        }`;
  }

  _trustGroupExportKey(details: string): string {
    return `mutation TrustGroupExportKey($passphrase: String!) {
            trustGroupExportKey(passphrase: $passphrase) {
                ${details}
            }
        }`;
  }

  _trustGroupImportKey(details: string): string {
    return `mutation TrustGroupImportKey($encryptedData: String!, $passphrase: String!) {
            trustGroupImportKey(encryptedData: $encryptedData, passphrase: $passphrase) {
                ${details}
            }
        }`;
  }

  _trustGroupGetPublicKey(): string {
    return `mutation TrustGroupGetPublicKey {
            trustGroupGetPublicKey
        }`;
  }

  _trustGroupProcessJoinRequest(details: string): string {
    return `mutation TrustGroupProcessJoinRequest($code: String!, $nodeName: String!, $nodePublicKey: String!) {
            trustGroupProcessJoinRequest(code: $code, nodeName: $nodeName, nodePublicKey: $nodePublicKey) {
                ${details}
            }
        }`;
  }

  _trustGroupJoinAsMember(details: string): string {
    return `mutation TrustGroupJoinAsMember($trustGroupPublicInfo: Json!, $certificate: Json!) {
            trustGroupJoinAsMember(trustGroupPublicInfo: $trustGroupPublicInfo, certificate: $certificate) {
                ${details}
            }
        }`;
  }

  _trustGroupSubmitJoinRequest(details: string): string {
    return `mutation TrustGroupSubmitJoinRequest($nodeName: String!, $nodePublicKey: String!) {
            trustGroupSubmitJoinRequest(nodeName: $nodeName, nodePublicKey: $nodePublicKey) {
                ${details}
            }
        }`;
  }

  _trustGroupPendingJoinRequests(details: string): string {
    return `{
            trustGroupPendingJoinRequests {
                ${details}
            }
        }`;
  }

  _trustGroupMembers(details: string, memberType: string | null): string {
    if (memberType) {
      return `{
            trustGroupMembers(memberType: "${memberType}") {
                ${details}
            }
        }`;
    }
    return `{
            trustGroupMembers {
                ${details}
            }
        }`;
  }

  _trustGroupDirectoryClearStale(): string {
    return `mutation { trustGroupDirectoryClearStale }`;
  }

  _trustGroupRemoveMember(): string {
    return `mutation TrustGroupRemoveMember($nodeId: String!) {
            trustGroupRemoveMember(nodeId: $nodeId)
        }`;
  }

  _keyHolders(details: string): string {
    return `{
            keyHolders {
                ${details}
            }
        }`;
  }

  _trustedGroups(details: string): string {
    return `{
            trustedGroups {
                ${details}
            }
        }`;
  }

  _trustGenerateToken(details: string): string {
    return `mutation TrustGenerateToken($permissions: [String]) {
            trustGenerateToken(permissions: $permissions) {
                ${details}
            }
        }`;
  }

  _trustEstablish(): string {
    return `mutation TrustEstablish($trustGroupId: String!, $trustGroupPublicKey: String!, $trustGroupName: String, $permissions: [String]) {
            trustEstablish(trustGroupId: $trustGroupId, trustGroupPublicKey: $trustGroupPublicKey, trustGroupName: $trustGroupName, permissions: $permissions) {
                trustGroupId
                name
                status
            }
        }`;
  }

  _trustRevoke(): string {
    return `mutation TrustRevoke($trustGroupId: String!) {
            trustRevoke(trustGroupId: $trustGroupId)
        }`;
  }

  _trustGroupApproveJoinRequest(details: string): string {
    return `mutation TrustGroupApproveJoinRequest($requestId: String!) {
            trustGroupApproveJoinRequest(requestId: $requestId) {
                ${details}
            }
        }`;
  }

  _trustGroupDenyJoinRequest(): string {
    return `mutation TrustGroupDenyJoinRequest($requestId: String!) {
            trustGroupDenyJoinRequest(requestId: $requestId)
        }`;
  }

  _trustGroupJoinRequestStatus(details: string): string {
    return `query TrustGroupJoinRequestStatus($requestId: String!) {
            trustGroupJoinRequestStatus(requestId: $requestId) {
                ${details}
            }
        }`;
  }

  _trustGroupBleSubmitJoinRequest(details: string): string {
    return `mutation TrustGroupBleSubmitJoinRequest($peerId: ID!, $nodeName: String!) {
            trustGroupBleSubmitJoinRequest(peerId: $peerId, nodeName: $nodeName) {
                ${details}
            }
        }`;
  }

  _trustGroupBleJoinRequestStatus(details: string): string {
    return `query TrustGroupBleJoinRequestStatus($peerId: ID!) {
            trustGroupBleJoinRequestStatus(peerId: $peerId) {
                ${details}
            }
        }`;
  }

  _joinRequestReceivedSubscription(): string {
    return `subscription JoinRequestReceived {
            joinRequestReceived {
                requestId
                nodeId
                nodeName
                nodePublicKey
                submittedAt
                source
            }
        }`;
  }

  _proximityDeviceDetectedSubscription(): string {
    return `subscription ProximityDeviceDetected {
            proximityDeviceDetected {
                nodeId
                nodeName
                rssi
                proximity
                timestamp
            }
        }`;
  }

  _backupPromptReceivedSubscription(): string {
    return `subscription BackupPromptReceived {
            backupPromptReceived {
                deviceName
                trustGroupName
                trustGroupId
                timestamp
            }
        }`;
  }

  _subscribeBackupPrompt(callback: (data: BackupPromptNotification) => void): void {
    const key = "trust_group:backup_prompt";

    let join_message = {
      topic: "__absinthe__:control",
      event: "phx_join",
      payload: {},
      ref: 0,
    };

    let subscribe = {
      topic: "__absinthe__:control",
      event: "doc",
      payload: {
        query: this._backupPromptReceivedSubscription(),
        variables: {},
      },
      ref: 0,
    };

    let heartbeat = {
      topic: "phoenix",
      event: "heartbeat",
      payload: {},
      ref: 0,
    };

    this._sockets[key] = {
      ws: new WebSocket(this._graphql_webs_url),
      connected: false,
      timer: null,
    };

    this._sockets[key].ws.onopen = () => {
      setTimeout(() => {
        this._sockets[key].ws.send(JSON.stringify(join_message));
      }, WEBSOCKET_INIT_DELAY_MS);
    };

    this._sockets[key].ws.onmessage = (event: MessageEvent) => {
      let data = JSON.parse(event.data);
      let payload = data.payload;

      if (this._sockets[key].connected) {
        if (payload.result) {
          let result = payload.result;
          if (result.hasOwnProperty("data")) {
            let notification = result.data.backupPromptReceived;
            callback(notification);
          }
        }
      } else {
        if (data.event == "phx_reply" && data.payload.status == "ok") {
          console.log("Backup prompt subscription connected");
          this._sockets[key].ws.send(JSON.stringify(subscribe));
          this._sockets[key].connected = true;

          this._sockets[key].timer = setInterval(() => {
            this._sockets[key].ws.send(JSON.stringify(heartbeat));
          }, WEBSOCKET_HEARTBEAT_INTERVAL_MS);

          callback({ status: "connected" });
        }
      }
    };

    this._sockets[key].ws.onclose = () => {
      console.log("Backup prompt subscription closed");
      if (this._sockets[key]?.timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
    };

    this._sockets[key].ws.onerror = (error: Event) => {
      console.error("Backup prompt subscription error:", error);
      if (this._sockets[key]?.timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
    };
  }

  _subscribeProximity(callback: (data: ProximityNotification) => void): void {
    const key = "trust_group:proximity";

    let join_message = {
      topic: "__absinthe__:control",
      event: "phx_join",
      payload: {},
      ref: 0,
    };

    let subscribe = {
      topic: "__absinthe__:control",
      event: "doc",
      payload: {
        query: this._proximityDeviceDetectedSubscription(),
        variables: {},
      },
      ref: 0,
    };

    let heartbeat = {
      topic: "phoenix",
      event: "heartbeat",
      payload: {},
      ref: 0,
    };

    this._sockets[key] = {
      ws: new WebSocket(this._graphql_webs_url),
      connected: false,
      timer: null,
    };

    this._sockets[key].ws.onopen = () => {
      setTimeout(() => {
        this._sockets[key].ws.send(JSON.stringify(join_message));
      }, WEBSOCKET_INIT_DELAY_MS);
    };

    this._sockets[key].ws.onmessage = (event: MessageEvent) => {
      let data = JSON.parse(event.data);
      let payload = data.payload;

      if (this._sockets[key].connected) {
        if (payload.result) {
          let result = payload.result;
          if (result.hasOwnProperty("data")) {
            let notification = result.data.proximityDeviceDetected;
            callback(notification);
          }
        }
      } else {
        if (data.event == "phx_reply" && data.payload.status == "ok") {
          console.log("Proximity subscription connected");
          this._sockets[key].ws.send(JSON.stringify(subscribe));
          this._sockets[key].connected = true;

          this._sockets[key].timer = setInterval(() => {
            this._sockets[key].ws.send(JSON.stringify(heartbeat));
          }, WEBSOCKET_HEARTBEAT_INTERVAL_MS);

          callback({ status: "connected" });
        }
      }
    };

    this._sockets[key].ws.onclose = () => {
      console.log("Proximity subscription closed");
      if (this._sockets[key]?.timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
    };

    this._sockets[key].ws.onerror = (error: Event) => {
      console.error("Proximity subscription error:", error);
      if (this._sockets[key]?.timer) {
        clearInterval(this._sockets[key].timer);
        this._sockets[key].timer = null;
      }
    };
  }
  // ----------------------------------------------------------------------------------------------------
}
