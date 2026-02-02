import type {
  Event,
  Sentant,
  GraphQLResponse,
  SignalData,
  WebSocketMessage,
  SocketState,
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
  constructor(domain_name: String, port: number, ssl = true) {
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
    return new Promise((resolve, reject) => {
      this._graphql_post(this._sentantAll(details), {}).then(
        (data: GraphQLResponse) => {
          resolve({ ...passthrough, ...data });
        },
        (error: Error) => {
          reject(error);
        },
      );
    });
  }

  /**
   * Retrieve this node's identity and hive information.
   */
  nodeInfo(passthrough = {}, details: string = "nodeId nodeName hiveId hiveName hiveMode hiveCompressedId version buildTime"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._nodeInfo(details), {}).then(
        (data: GraphQLResponse) => {
          resolve({ ...passthrough, ...data });
        },
        (error: Error) => {
          reject(error);
        },
      );
    });
  }

  /**
   * Retrieve discovered peers from the mesh.
   */
  peers(passthrough = {}, details: string = "nodeId nodeName transport address rssi connectionState hiveId isSameHive hiveVerified sentantCount lastSeen reachability { ble { lastSeen confidence rssi } wifi { lastSeen confidence ip } lora { lastSeen confidence } }"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._peers(details), {}).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Retrieve the hive directory.
   */
  hiveDirectory(passthrough = {}, details: string = "hiveId hiveName myNodeId directoryVersion nodes { nodeId name status hiveId sentants { id name } reachability { ble { lastSeen confidence rssi } wifi { lastSeen confidence ip } lora { lastSeen confidence } } updatedAt }"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveDirectory(details), {}).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Create (or reset) a hive with the given name.
   */
  hiveCreate(name: string, passthrough = {}, details: string = "hiveId hiveName hiveMode isProvisional"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveCreate(details), { name }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Mark the current provisional hive as established.
   */
  hiveMarkEstablished(passthrough = {}, details: string = "hiveId hiveName hiveMode isProvisional"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveMarkEstablished(details), {}).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Generate a 4-character join code for other nodes.
   */
  hiveGenerateJoinCode(passthrough = {}, details: string = "code expiresIn"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveGenerateJoinCode(details), {}).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Export the hive key encrypted with a passphrase.
   */
  hiveExportKey(passphrase: string, passthrough = {}, details: string = "encryptedData"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveExportKey(details), { passphrase }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Import an encrypted hive key.
   */
  hiveImportKey(encryptedData: string, passphrase: string, passthrough = {}, details: string = "hiveId hiveName hiveMode isProvisional"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveImportKey(details), { encryptedData, passphrase }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Get this node's public key (base64-encoded).
   */
  hiveGetPublicKey(passthrough = {}): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveGetPublicKey(), {}).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Process a join request (called on key holder node).
   */
  hiveProcessJoinRequest(code: string, nodeName: string, nodePublicKey: string, passthrough = {}, details: string = "certificate hivePublicInfo"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveProcessJoinRequest(details), { code, nodeName, nodePublicKey }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Finalize joining a hive as a member (called on joining node).
   */
  hiveJoinAsMember(hivePublicInfo: object, certificate: object, passthrough = {}, details: string = "hiveId hiveName hiveMode isProvisional"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveJoinAsMember(details), { hivePublicInfo: JSON.stringify(hivePublicInfo), certificate: JSON.stringify(certificate) }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Submit a join request to a key holder node.
   */
  hiveSubmitJoinRequest(nodeName: string, nodePublicKey: string, passthrough = {}, details: string = "id nodeName nodePublicKey status submittedAt"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveSubmitJoinRequest(details), { nodeName, nodePublicKey }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Get pending join requests (key holder).
   */
  hivePendingJoinRequests(passthrough = {}, details: string = "id nodeName nodePublicKey status submittedAt"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hivePendingJoinRequests(details), {}).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Approve a join request (key holder).
   */
  hiveApproveJoinRequest(requestId: string, passthrough = {}, details: string = "certificate hivePublicInfo"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveApproveJoinRequest(details), { requestId }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Deny a join request (key holder).
   */
  hiveDenyJoinRequest(requestId: string, passthrough = {}): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveDenyJoinRequest(), { requestId }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
  }

  /**
   * Check status of a join request (joiner polls this on key holder).
   */
  hiveJoinRequestStatus(requestId: string, passthrough = {}, details: string = "status certificate hivePublicInfo"): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._hiveJoinRequestStatus(details), { requestId }).then(
        (data: GraphQLResponse) => { resolve({ ...passthrough, ...data }); },
        (error: Error) => { reject(error); },
      );
    });
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
  sentantGet(
    id: string,
    passthrough = {},
    details: string = "id name",
  ): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._sentantGet(details), { id: id }).then(
        (data: GraphQLResponse) => {
          resolve({ ...passthrough, ...data });
        },
        (error: Error) => {
          reject(error);
        },
      );
    });
  }
  sentantGetByName(
    name: string,
    passthrough = {},
    details: string = "id name",
  ): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._sentantGetByName(details), { name: name }).then(
        (data: GraphQLResponse) => {
          resolve({ ...passthrough, ...data });
        },
        (error: Error) => {
          reject(error);
        },
      );
    });
  }
  sentantLoad(
    definition: string,
    passthrough = {},
    details: string = "id name",
  ): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._sentantLoad(details), {
        definition: definition,
      }).then(
        (data: GraphQLResponse) => {
          resolve({ ...passthrough, ...data });
        },
        (error: Error) => {
          reject(error);
        },
      );
    });
  }
  sentantUnload(
    id: string,
    passthrough = {},
    details: string = "id name",
  ): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._sentantUnload(details), { id: id }).then(
        (data: GraphQLResponse) => {
          resolve({ ...passthrough, ...data });
        },
        (error: Error) => {
          reject(error);
        },
      );
    });
  }
  swarmLoad(
    definition: string,
    passthrough = {},
    details: string = "id name",
  ): Promise<object> {
    return new Promise((resolve, reject) => {
      this._graphql_post(this._swarmLoad(details), {
        definition: definition,
      }).then(
        (data: GraphQLResponse) => {
          resolve({ ...passthrough, ...data });
        },
        (error: Error) => {
          reject(error);
        },
      );
    });
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
      variables: JSON.stringify(variables),
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
      .then((response) => response.json())
      .then((data) => {
        return data;
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
            console.log("heartbeat");
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

  _hiveDirectory(details: string): string {
    return `{
            hiveDirectory {
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

  _hiveCreate(details: string): string {
    return `mutation HiveCreate($name: String!) {
            hiveCreate(name: $name) {
                ${details}
            }
        }`;
  }

  _hiveMarkEstablished(details: string): string {
    return `mutation HiveMarkEstablished {
            hiveMarkEstablished {
                ${details}
            }
        }`;
  }

  _hiveGenerateJoinCode(details: string): string {
    return `mutation HiveGenerateJoinCode {
            hiveGenerateJoinCode {
                ${details}
            }
        }`;
  }

  _hiveExportKey(details: string): string {
    return `mutation HiveExportKey($passphrase: String!) {
            hiveExportKey(passphrase: $passphrase) {
                ${details}
            }
        }`;
  }

  _hiveImportKey(details: string): string {
    return `mutation HiveImportKey($encryptedData: String!, $passphrase: String!) {
            hiveImportKey(encryptedData: $encryptedData, passphrase: $passphrase) {
                ${details}
            }
        }`;
  }

  _hiveGetPublicKey(): string {
    return `mutation HiveGetPublicKey {
            hiveGetPublicKey
        }`;
  }

  _hiveProcessJoinRequest(details: string): string {
    return `mutation HiveProcessJoinRequest($code: String!, $nodeName: String!, $nodePublicKey: String!) {
            hiveProcessJoinRequest(code: $code, nodeName: $nodeName, nodePublicKey: $nodePublicKey) {
                ${details}
            }
        }`;
  }

  _hiveJoinAsMember(details: string): string {
    return `mutation HiveJoinAsMember($hivePublicInfo: Json!, $certificate: Json!) {
            hiveJoinAsMember(hivePublicInfo: $hivePublicInfo, certificate: $certificate) {
                ${details}
            }
        }`;
  }

  _hiveSubmitJoinRequest(details: string): string {
    return `mutation HiveSubmitJoinRequest($nodeName: String!, $nodePublicKey: String!) {
            hiveSubmitJoinRequest(nodeName: $nodeName, nodePublicKey: $nodePublicKey) {
                ${details}
            }
        }`;
  }

  _hivePendingJoinRequests(details: string): string {
    return `{
            hivePendingJoinRequests {
                ${details}
            }
        }`;
  }

  _hiveApproveJoinRequest(details: string): string {
    return `mutation HiveApproveJoinRequest($requestId: String!) {
            hiveApproveJoinRequest(requestId: $requestId) {
                ${details}
            }
        }`;
  }

  _hiveDenyJoinRequest(): string {
    return `mutation HiveDenyJoinRequest($requestId: String!) {
            hiveDenyJoinRequest(requestId: $requestId)
        }`;
  }

  _hiveJoinRequestStatus(details: string): string {
    return `query HiveJoinRequestStatus($requestId: String!) {
            hiveJoinRequestStatus(requestId: $requestId) {
                ${details}
            }
        }`;
  }
  // ----------------------------------------------------------------------------------------------------
}
