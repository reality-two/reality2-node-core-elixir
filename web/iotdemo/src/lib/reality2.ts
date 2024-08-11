export type Event = {
    event: string,
    parameters: {[key:string]: any}
};

export type Sentant = {
    id: string,
    name: string,
    description: string,
    events: Event[],
    signals: string[]
};

export default class R2 {
    _secure: boolean = false;
    _graphql_http_url: string = "https://localhost:4005/reality2";
    _graphql_webs_url: string = "wss://localhost:4005/reality2/websocket";

    _sockets: {[index:string]: {ws: WebSocket, connected: boolean, timer: any}} = {};

    // ----------------------------------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------------------------------
    constructor(domain_name: String, port: number, ssl = true) {
        this._secure = ssl;
        if (ssl) {
            this._graphql_http_url = "https://" + domain_name + ":" + port + "/reality2"
            this._graphql_webs_url = "wss://" + domain_name + ":" + port + "/reality2/websocket"
        }
        else {
            this._graphql_http_url = "http://" + domain_name + ":" + port + "/reality2"
            this._graphql_webs_url = "ws://" + domain_name + ":" + port + "/reality2/websocket"
        }
    }
    // ----------------------------------------------------------------------------------------------------



    // ----------------------------------------------------------------------------------------------------
    // Public API
    // ----------------------------------------------------------------------------------------------------
    sentantAll(passthrough = {}, details: string = "id name") : Promise<object> {
        return new Promise((resolve, reject) => {
            this._graphql_post ( this._sentantAll(details), {} ).then((data: any) => {
                resolve({...passthrough, ...data});
            }, (error: any) => {
                reject(error);
            });
        });
    }
    sentantGet(id: string, passthrough = {}, details: string = "id name") : Promise<object> {
        return new Promise((resolve, reject) => {
            this._graphql_post ( this._sentantGet(details), {id: id} ).then((data: any) => {
                resolve({...passthrough, ...data});
            }, (error: any) => {
                reject(error);
            });
        });
    }
    sentantGetByName(name: string, passthrough = {}, details: string = "id name") : Promise<object> {
        return new Promise((resolve, reject) => {
            this._graphql_post ( this._sentantGetByName(details), {name: name} ).then((data: any) => {
                resolve({...passthrough, ...data});
            }, (error: any) => {
                reject(error);
            });
        });
    }
    sentantLoad(definition: string, passthrough = {}, details: string = "id name") : Promise<object> {
        return new Promise((resolve, reject) => {
            this._graphql_post ( this._sentantLoad(details), {definition: definition} ).then((data: any) => {
                resolve({...passthrough, ...data});
            }, (error: any) => {
                reject(error);
            });
        });
    }
    sentantUnload(id: string, passthrough = {}, details: string = "id name") : Promise<object> {
        return new Promise((resolve, reject) => {
            this._graphql_post ( this._sentantUnload(details), {id: id} ).then((data: any) => {
                resolve({...passthrough, ...data});
            }, (error: any) => {
                reject(error);
            });
        });
    }
    swarmLoad(definition: string, passthrough = {}, details: string = "id name") : Promise<object> {
        return new Promise((resolve, reject) => {
            this._graphql_post ( this._swarmLoad(details), {definition: definition} ).then((data: any) => {
                resolve({...passthrough, ...data});
            }, (error: any) => {
                reject(error);
            });
        });
    }
    sentantSend(id: string, event: string, params: object, passthrough: object = {}, details: string = "id name") : Promise<object> {
        return this._graphql_post ( this._sentandSend(details), {id: id, event: event, parameters: JSON.stringify(params), passthrough: JSON.stringify(passthrough)} );
    }
    awaitSignal(id: string, signal: string, callback: Function = () => {}) : void {
        this._subscribe(id, signal, callback)
    }
    monitor(callback: Function = () => {}) : void {
        this._set_up_node_monitoring(callback);
    }

    public static JSONPath(data: object, path: string, none:any = null) : any {
        if (data == null || path == null) {
            return none;
        }
        else {
            let parts = path.split(".");
            let result: any = data;
            for (let i = 0; i < parts.length; i++) {
                let index = parseInt(parts[i]);
                if (isNaN(index)) {
                    if (result.hasOwnProperty(parts[i])) {
                        result = result[parts[i]];
                    } else {
                        return none;
                    }
                } else {
                    if (Array.isArray(result)) {
                        result = result[index];
                    } else {
                        return none;
                    }
                }
            }
            return result;
        }
    }
    // ----------------------------------------------------------------------------------------------------



    // ----------------------------------------------------------------------------------------------------
    // Monitoring Sentant
    // ----------------------------------------------------------------------------------------------------
    _set_up_node_monitoring (callback: Function = () => {}) : void {
        let details = {
            "sentant": { "name": "monitor", "automations": [ { "name": "Monitor", "transitions": [ { "event": "__internal", "actions": [ { "command": "signal", "parameters": { "public": true, "event": "internal" } } ] } ] } ] }
        }

        this.sentantGetByName("monitor").then((data1: any) => {
            if (data1.data.sentantGet == null) {
                this.sentantLoad(JSON.stringify(details)).then((data2: any) => {
                    this.awaitSignal(data2.data.sentantLoad.id, "internal", (data3: any) => {
                        callback(data3);
                    });
                    console.log("Monitor Sentant Loaded");
                });
            } else {
                this.awaitSignal(data1.data.sentantGet.id, "internal", (data4: any) => {
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
    _graphql_post(query: string, variables: object) : Promise<object> {
        let body = {
            "query": query,
            "variables": JSON.stringify(variables)
        }

        let parameters = {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': '*/*',
            },
            body: JSON.stringify(body)
        };

        return fetch(this._graphql_http_url, parameters)
            .then(response => response.json())
            .then(data => {
                return data;
            });
    }
    // ----------------------------------------------------------------------------------------------------



    // ----------------------------------------------------------------------------------------------------
    // Websocket Subscription
    // ----------------------------------------------------------------------------------------------------
    _subscribe(id: string, signal: string, callback: Function ) : void {
        let join_message = {
            "topic": "__absinthe__:control",
            "event": "phx_join",
            "payload": {},
            "ref": 0
        }
        
        let subscribe = {
            "topic": "__absinthe__:control",
            "event": "doc",
            "payload": {
                "query": this._awaitSignal("event parameters"),
                "variables": {
                    "id": id,
                    "signal": signal
                }
            },
            "ref": 0
        }

        let heartbeat = {
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": {},
            "ref": 0
        }

        this._sockets[id+"|"+signal] = {ws: new WebSocket(this._graphql_webs_url), connected: false, timer: null};

        this._sockets[id+"|"+signal].ws.onopen = () => {
            this._sockets[id+"|"+signal].ws.send(JSON.stringify(join_message));
        };

        this._sockets[id+"|"+signal].ws.onmessage = (event: any) => {
            let data = JSON.parse(event.data);
            let payload = data.payload;

            if (this._sockets[id+"|"+signal].connected) {
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
                    this._sockets[id+"|"+signal].ws.send(JSON.stringify(subscribe));
                    this._sockets[id+"|"+signal].connected = true

                    this._sockets[id+"|"+signal].timer = setInterval(() => {
                        console.log("heartbeat");
                        this._sockets[id+"|"+signal].ws.send(JSON.stringify(heartbeat));
                    }, 30000);

                    callback({"status":"connected"})
                }
            }
        };
    }
    // ----------------------------------------------------------------------------------------------------



    // ----------------------------------------------------------------------------------------------------
    // GraphQL Queries and Mutations
    // ----------------------------------------------------------------------------------------------------
    _sentantAll(details: string) : string {
        return `{
            sentantAll {
                ${details}
            }
        }`;
    }

    _sentantGet(details: string) : string {
        return `query SentantGet($id: UUID4!) {
            sentantGet(id: $id) {
                ${details}
            }
        }`;
    }

    _sentantGetByName(details: string) : string {
        return `query SentantGet($name: String!) {
            sentantGet(name: $name) {
                ${details}
            }
        }`;
    }

    _sentantLoad(details: string) : string {
        return `mutation SentantLoad($definition: String!) {
            sentantLoad(definition: $definition) {
                ${details}
            }
        }`;
    }

    _sentantUnload(details: string) : string {
        return `mutation SentantUnload($id: UUID4!) {
            sentantUnload(id: $id) {
                ${details}
            }
        }`;
    }

    _swarmLoad(details: string) : string {
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

    _sentandSend(details: string) : string {
        return `mutation SentantSend($id: UUID4!, $event: String!, $parameters: Json, $passthrough: Json) {
            sentantSend(id: $id, event: $event, parameters: $parameters, passthrough: $passthrough) {
                ${details}
            }
        }`;
    }

    _awaitSignal(details: string = "id name") : string {
        return `subscription AwaitSignal($id: UUID4!, $signal: String!) {
            awaitSignal(id: $id, signal: $signal) {
                ${details}
            }
        }`
    }
    // ----------------------------------------------------------------------------------------------------
}