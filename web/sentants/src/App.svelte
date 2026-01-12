<!------------------------------------------------------------------------------------------------------
  Simple WebApp for a Reality Node

  Author: Dr. Roy C. Davies
  Created: August 2024
  Contact: roy.c.davies@ieee.org
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import {
        Message,
        Content,
        Cards,
        Menu,
        Icon,
        Segment,
        Button,
        Buttons,
        Item,
        Header,
        Input,
        Dropdown,
        Text,
        Select,
        Option,
    } from "svelte-fomantic-ui";

    import R2 from "./lib/reality2";
    import type { Sentant, Location, GraphQLResponse, LoadState, LoadResult } from "./lib/types";
    import {
        DEFAULT_PORT,
        DEFAULT_LOCATION,
        MONITOR_INIT_DELAY_MS,
        HEADER_HEIGHT_PX,
        RESERVED_SENTANT_NAMES,
    } from "./lib/constants";
    import SentantCard from "./lib/SentantCard.svelte";
    import SentantCards from "./lib/SentantCards.svelte";
    import Login from "./lib/Login.svelte";
    import Construct from "./lib/Construct.svelte";
    import Swarm from "./lib/Swarm.svelte";
    import Map from "./lib/Map.svelte";

    import { getQueryStringVal } from "./lib/Querystring.svelte";

    import { onMount, onDestroy } from "svelte";

    let default_port = DEFAULT_PORT;
    let use_default_url = false;
    let watchId: number | undefined;
    let monitorTimeoutId: number | undefined;

    // Set up the sentant loading
    var loadedData: Sentant[] = [];
    $: sentantData = loadedData;

    // Set up the state
    var set_state: LoadState = "loading";
    $: state = set_state;

    // Set up the geolocation
    var set_location: Location = DEFAULT_LOCATION;
    $: location = set_location;

    // Saved state for constructor
    let savedState: Record<string, unknown> = {};

    // Error state
    let errorMessage: string = "";

    // Local node identity (captured from first sentant loaded)
    let localNodeId: string = "";

    // Node filter for dropdown - defaults to local node
    let selectedNodeId: string = "";

    // Available nodes derived from sentant data
    $: availableNodes = getAvailableNodes(sentantData, localNodeId);

    interface NodeInfo {
        nodeId: string;
        nodeName: string;
        isLocal: boolean;
        sentantCount: number;
    }

    function getAvailableNodes(sentants: Sentant[], localId: string): NodeInfo[] {
        const nodeMap: Record<string, NodeInfo> = {};

        for (const s of sentants) {
            if (s.name === RESERVED_SENTANT_NAMES.MONITOR ||
                s.name === RESERVED_SENTANT_NAMES.DELETED ||
                s.name === RESERVED_SENTANT_NAMES.VIEW) continue;

            const nodeId = s.nodeId || "local";
            const nodeName = s.nodeName || "Local";

            if (!nodeMap[nodeId]) {
                nodeMap[nodeId] = {
                    nodeId,
                    nodeName,
                    isLocal: nodeId === localId,
                    sentantCount: 0
                };
            }
            nodeMap[nodeId].sentantCount++;
        }

        // Sort: local first, then by name
        return Object.values(nodeMap).sort((a, b) => {
            if (a.isLocal && !b.isLocal) return -1;
            if (!a.isLocal && b.isLocal) return 1;
            return a.nodeName.localeCompare(b.nodeName);
        });
    }

    // When localNodeId is set, default selectedNodeId to it
    $: if (localNodeId && !selectedNodeId) {
        selectedNodeId = localNodeId;
    }

    // Filtered sentants based on selected node
    // If no selection yet, show local sentants (filter by localNodeId)
    $: filteredSentantData = selectedNodeId
        ? sentantData.filter(s => (s.nodeId || localNodeId) === selectedNodeId)
        : sentantData.filter(s => (s.nodeId || localNodeId) === localNodeId);

    // -------------------------------------------------------------------------------------------------
    // Query Strings
    // -------------------------------------------------------------------------------------------------
    $: name_query = getQueryStringVal("name");
    $: id_query = getQueryStringVal("id");
    $: map_query = getQueryStringVal("map");
    $: view_query = getQueryStringVal("view");
    $: mr_query = getQueryStringVal("mr");
    $: variables_query = getQueryStringVal("variables");
    $: construct_query = getQueryStringVal("construct");
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // Window width
    // -------------------------------------------------------------------------------------------------
    let windowWidth: number = 0;
    let fullHeight: string = "400px";
    let variables_loader: HTMLInputElement;
    $: variables = variables_query
        ? JSON.parse(decodeURIComponent(variables_query))
        : {};

    const setDimensions = () => {
        windowWidth = window.innerWidth;
        fullHeight = `${window.innerHeight - HEADER_HEIGHT_PX}px`;
    };
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // GraphQL client setup
    // -------------------------------------------------------------------------------------------------
    let r2_node = new R2(
        use_default_url ? "localhost" : window.location.hostname,
        Number(use_default_url ? default_port : window.location.port),
    );
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // On page load
    // -------------------------------------------------------------------------------------------------
    onMount(() => {
        // Set the state depending on the query string
        if (id_query != null) set_state = "id";
        else if (name_query != null) set_state = "name";
        else {
            set_state = "start";
            view_query = "";
        }

        // Set up the variables loader
        variables_loader = document.createElement("input");
        variables_loader.type = "file";

        variables_loader.onchange = (e: Event) => {
            // getting a hold of the file reference
            const target = e.target as HTMLInputElement;
            if (!target.files || target.files.length === 0) return;
            const file = target.files[0];

            // setting up the reader
            const reader = new FileReader();
            reader.readAsText(file, "UTF-8");

            // here we tell the reader what to do when it's done reading...
            reader.onload = (readerEvent: ProgressEvent<FileReader>) => {
                if (readerEvent.target?.result && typeof readerEvent.target.result === "string") {
                    variables = JSON.parse(readerEvent.target.result);
                }
            };
        };

        // Geolocation
        watchId = navigator.geolocation.watchPosition(
            (position) => {
                console.log(position.coords);
                set_location = {
                    latitude: position.coords.latitude,
                    longitude: position.coords.longitude,
                    altitude: position.coords.altitude,
                    accuracy: position.coords.accuracy,
                    altitudeAccuracy: position.coords.altitudeAccuracy,
                    heading: position.coords.heading,
                    speed: position.coords.speed,
                };
            },
            (error) => {
                console.error("Error getting location:", error.message);
                set_location = default_location;
            },
        );

        setDimensions();
        window.addEventListener("resize", setDimensions);
        return () => {
            window.removeEventListener("resize", setDimensions);
        };
    });
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // Unload page
    // -------------------------------------------------------------------------------------------------
    onDestroy(() => {
        if (watchId) navigator.geolocation.clearWatch(watchId);
        if (monitorTimeoutId) clearTimeout(monitorTimeoutId);
    });
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // The Path of this page
    // -------------------------------------------------------------------------------------------------
    $: path =
        window.location.hostname +
        (name_query ? "|" + name_query : "") +
        (id_query ? "|" + id_query : "");
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // Main functionality
    // -------------------------------------------------------------------------------------------------
    // Set up the monitoring of the Reality2 Node
    if (id_query == null && name_query == null) {
        monitorTimeoutId = setTimeout(() => {
            // Set up monitoring callback
            r2_node.monitor((data: GraphQLResponse) => {
                updateSentants(data);
            });

            // Load the Sentants
            loadSentants().then((result) => {
                set_state = result.state;
                loadedData = result.data;
                // Capture local node ID from first sentant (local sentants come first)
                if (result.data.length > 0 && result.data[0].nodeId) {
                    localNodeId = result.data[0].nodeId;
                }
            });
        }, MONITOR_INIT_DELAY_MS);
    }
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // Load the Sentant(s) the first time.
    // -------------------------------------------------------------------------------------------------
    function loadSentants(): Promise<LoadResult> {
        return new Promise((resolve, reject) => {
            if (id_query != null) {
                set_state = "loading";
                r2_node
                    .sentantGet(
                        id_query,
                        {},
                        "name id description events { event parameters } signals nodeId nodeName",
                    )
                    .then((data) => {
                        let result = R2.JSONPath(data, "data.sentantGet");
                        if (result == null) {
                            resolve({ state: "id", data: [] });
                        } else {
                            resolve({ state: "id", data: [result] });
                        }
                    })
                    .catch((error: Error) => {
                        console.error("Error loading sentant by ID:", error);
                        errorMessage = `Failed to load sentant: ${error.message}`;
                        resolve({ state: "error", data: [] });
                    });
            } else if (name_query != null) {
                set_state = "loading";
                r2_node
                    .sentantGetByName(
                        name_query,
                        {},
                        "name id description events { event parameters } signals nodeId nodeName",
                    )
                    .then((data) => {
                        let result = R2.JSONPath(data, "data.sentantGet");
                        if (result == null) {
                            resolve({ state: "name", data: [] });
                        } else {
                            resolve({ state: "name", data: [result] });
                        }
                    })
                    .catch((error: Error) => {
                        console.error("Error loading sentant by name:", error);
                        errorMessage = `Failed to load sentant: ${error.message}`;
                        resolve({ state: "error", data: [] });
                    });
            } else if (
                map_query != null ||
                view_query != null ||
                mr_query != null ||
                construct_query != null
            ) {
                set_state = "loading";
                r2_node
                    .sentantAll(
                        {},
                        "name id description events { event parameters } signals nodeId nodeName",
                    )
                    .then((data) => {
                        let result = R2.JSONPath(data, "data.sentantAll");
                        if (result == null) {
                            resolve({
                                state:
                                    construct_query != null
                                        ? "construct"
                                        : map_query != null
                                          ? "map"
                                          : mr_query != null
                                            ? "mr"
                                            : "view",
                                data: [],
                            });
                        } else {
                            resolve({
                                state:
                                    construct_query != null
                                        ? "construct"
                                        : map_query != null
                                          ? "map"
                                          : mr_query != null
                                            ? "mr"
                                            : "view",
                                data: result,
                            });
                        }
                    })
                    .catch((error: Error) => {
                        console.error("Error loading all sentants:", error);
                        errorMessage = `Failed to load sentants: ${error.message}`;
                        resolve({ state: "error", data: [] });
                    });
            }
        });
    }
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // Update the list of sentants when something changes (can either be create or delete)
    // -------------------------------------------------------------------------------------------------
    function updateSentants(updates: GraphQLResponse): void {
        if (name_query == null && id_query == null) {
            // Check for mesh peer events
            // Mesh events use parameters.event, BLE events use parameters.activity
            var mesh_event = R2.JSONPath(updates, "parameters.event");
            var ble_activity = R2.JSONPath(updates, "parameters.activity");
            var peer_id = R2.JSONPath(updates, "parameters.peer_id") || R2.JSONPath(updates, "parameters.id");

            // For peer disconnected/lost - just remove that peer's sentants locally
            // This preserves message history on remaining sentants
            if (mesh_event === "mesh_peer_disconnected" || ble_activity === "r2_node_lost") {
                console.log("Peer disconnected:", peer_id);
                if (peer_id) {
                    loadedData = sentantData.filter(s => s.nodeId !== peer_id);
                }
                return;
            }

            // For new peer or sentant changes - need to fetch updated data
            // This will refresh but only for remote sentants joining
            var needs_refresh =
                mesh_event === "mesh_peer_connected" ||
                mesh_event === "mesh_peer_sentants_changed" ||
                ble_activity === "r2_node_found";

            if (needs_refresh) {
                console.log("Network event received:", mesh_event || ble_activity, R2.JSONPath(updates, "parameters"));
                r2_node
                    .sentantAll(
                        {},
                        "name id description events { event parameters } signals nodeId nodeName",
                    )
                    .then((data) => {
                        let result = R2.JSONPath(data, "data.sentantAll");
                        if (result != null) {
                            // Merge: keep existing local sentants (preserves messages), add/update remote
                            const localSentants = sentantData.filter(s => s.nodeId === localNodeId);
                            const remoteSentants = result.filter((s: Sentant) => s.nodeId !== localNodeId);
                            loadedData = [...localSentants, ...remoteSentants];

                            // Update localNodeId if we don't have it yet
                            if (!localNodeId && result.length > 0 && result[0].nodeId) {
                                localNodeId = result[0].nodeId;
                                loadedData = result; // First load, use full result
                            }
                        }
                    });
                return;
            }

            // Handle local sentant create/delete events
            var sentant_id = R2.JSONPath(updates, "parameters.id");
            var sentant_name = R2.JSONPath(updates, "parameters.name");
            if (sentant_id !== null && sentant_name !== RESERVED_SENTANT_NAMES.VIEW) {
                switch (R2.JSONPath(updates, "parameters.activity")) {
                    case "created":
                        r2_node
                            .sentantGet(
                                sentant_id,
                                {},
                                "name id description events { event parameters } signals nodeId nodeName",
                            )
                            .then((data) => {
                                // Go through the loaded data and add the new Sentant.
                                loadedData = sentantData.concat(
                                    R2.JSONPath(data, "data.sentantGet"),
                                );
                            });
                        break;
                    case "deleted":
                        // Go through the loaded data, find the deleted sentant and remove it.
                        loadedData = sentantData.map((data) => {
                            if (sentant_id == R2.JSONPath(data, "id")) {
                                data.name = RESERVED_SENTANT_NAMES.DELETED;
                            }
                            return data;
                        });
                        break;
                    default:
                        break;
                }
            }
        }
    }
    // -------------------------------------------------------------------------------------------------

    // -------------------------------------------------------------------------------------------------
    // Functions used in the Layout
    // -------------------------------------------------------------------------------------------------
    function change_state(e: CustomEvent<{ value: string }>): void {
        let newstate = e.detail.value;
        if (newstate == "view" || newstate == "map") {
            loadSentants().then((result) => {
                if (result.state !== "error") {
                    set_state = newstate;
                    loadedData = result.data;
                } else {
                    set_state = result.state;
                }
            });
        } else {
            set_state = newstate;
        }
    }

    // return true if there are no Sentants, or only the one called "monitor"
    function none_or_monitor_only(sentants: Sentant[]): boolean {
        let response = true;

        for (let i = 0; i < sentants.length; i++) {
            if (R2.JSONPath(sentants[i], "name") !== RESERVED_SENTANT_NAMES.MONITOR) {
                response = false;
                break;
            }
        }
        return response;
    }

    // Reload the page
    function reload_page() {
        loadSentants().then((result) => {
            set_state = result.state;
            loadedData = result.data;
        });
    }

    // Check if the proposed url is reachable or not
    async function isServerReachable(url: string) {
        try {
            const response = await fetch(url, {
                method: "HEAD",
                mode: "no-cors",
            });
            // Note: With 'no-cors', status is always 0, so we assume it might be reachable.
            return true;
        } catch (err) {
            return false;
        }
    }

    // Get the keys pressed (so we can process them to determine the path)
    function on_key_down(event: KeyboardEvent): void {
        let new_location = "";
        if (event.key === "Enter" && event.target.id === "path") {
            let elements = path.split("|");
            if (elements.length > 0) {
                // Extract hostname/IP - might include port already
                let host = elements[0].trim();
                let port = window.location.port || "4005";

                // Check if host already includes a port
                if (host.includes(":")) {
                    const parts = host.split(":");
                    host = parts[0];
                    port = parts[1];
                }

                if (elements.length > 1) {
                    new_location =
                        "https://" + host + ":" + port +
                        "/?name=" + elements[1] +
                        "&variables=" + encodeURIComponent(JSON.stringify(variables));
                } else {
                    new_location =
                        "https://" + host + ":" + port +
                        "/?variables=" + encodeURIComponent(JSON.stringify(variables));
                }

                // Navigate directly - let browser handle connection errors
                window.location.href = new_location;
            }
        }
    }
    // -------------------------------------------------------------------------------------------------
</script>

<!----------------------------------------------------------------------------------------------------->

<!----------------------------------------------------------------------------------------------------->
<!----------------------------------------------------------------------------------------------------->
<svelte:window on:keydown={on_key_down} />
<!----------------------------------------------------------------------------------------------------->

<!------------------------------------------------------------------------------------------------------
Layout
------------------------------------------------------------------------------------------------------->
<main style={"padding: 0px;"}>
    {#if state == "login"}
        <Login></Login>
    {:else}
        <Menu ui top attached grey inverted borderless>
            <Item>
                <Buttons ui icon>
                    <Button ui grey on:click={() => history.back()}>
                        <Icon arrow left />
                    </Button>
                    <Button ui grey on:click={() => history.forward()}>
                        <Icon arrow right />
                    </Button>
                    <Button ui grey on:click={reload_page}>
                        <Icon redo />
                    </Button>
                </Buttons>
            </Item>
            <Item style={"margin: auto; width:" + (windowWidth - 260) + "px; display: flex; gap: 5px;"}>
                <Input ui big style={"flex: 1;"}>
                    <Input
                        id="path"
                        text
                        placeholder="Enter Path..."
                        bind:value={path}
                    />
                </Input>
                {#if availableNodes.length > 0}
                    <select class="ui selection dropdown" style="min-width: 180px; padding: 0.67857143em 1em; font-size: 1.14285714em;" bind:value={selectedNodeId}>
                        {#each availableNodes as node}
                            <option value={node.nodeId}>{node.nodeName} ({node.sentantCount}){node.isLocal ? " - local" : ""}</option>
                        {/each}
                    </select>
                {/if}
            </Item>
            <Menu right>
                <Dropdown ui item style="position: relative; z-index:1010">
                    <Icon sidebar />
                    <Menu vertical ui style="width: 350px;">
                        <Header ui>View</Header>
                        <Item icon value="view" on:click={change_state}>
                            <Icon ui th />
                            Grid
                        </Item>
                        <Item icon value="map" on:click={change_state}>
                            <Icon ui map outline />
                            Map
                        </Item>
                        <Item icon value="construct" on:click={change_state}>
                            <Icon ui hammer />
                            Construct
                        </Item>
                        <Item icon value="swarm" on:click={change_state}>
                            <Icon ui exclamation />
                            Swarm (WIP)
                        </Item>
                    </Menu>
                </Dropdown>
            </Menu>
        </Menu>
        {#if errorMessage}
            <Message ui error onClose={() => (errorMessage = "")}>
                <Icon close />
                <Header>Error</Header>
                <p>{errorMessage}</p>
            </Message>
        {/if}
        <Segment
            ui
            bottom
            attached
            grey
            compact
            style="height: {fullHeight}px; width:{windowWidth}px; padding: 0px;"
        >
            <!--------------------------------------------------------------------------------------------->
            {#if state == "start"}
                <!--------------------------------------------------------------------------------------------->
                <Message
                    ui
                    centered
                    blue
                    massive
                    style="position: fixed; top: 100; left: 0; right: 0; z-index: 1000;"
                >
                    <Content ui>Loading ...</Content>
                </Message>
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "error"}
                <!--------------------------------------------------------------------------------------------->
                <Message
                    ui
                    centered
                    red
                    massive
                    style="position: fixed; top: 100; left: 0; right: 0; z-index: 1000;"
                >
                    <Content ui>Something bad happened</Content>
                </Message>
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "loading"}
                <!--------------------------------------------------------------------------------------------->
                <Message
                    ui
                    centered
                    blue
                    massive
                    style="position: fixed; top: 100; left: 0; right: 0; z-index: 1000;"
                >
                    <Content ui>Loading ...</Content>
                </Message>
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "construct"}
                <!--------------------------------------------------------------------------------------------->
                <Construct
                    {r2_node}
                    {sentantData}
                    {location}
                    bind:savedState
                    bind:variables
                />
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "swarm"}
                <!--------------------------------------------------------------------------------------------->
                <Swarm
                    {r2_node}
                    {sentantData}
                    {location}
                    bind:savedState
                    bind:variables
                />
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "id"}
                <!--------------------------------------------------------------------------------------------->
                <Cards ui centered>
                    <SentantCard
                        sentant={sentantData[0]}
                        {r2_node}
                        {variables}
                    />
                </Cards>
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "name"}
                <!--------------------------------------------------------------------------------------------->
                <Cards ui centered>
                    <SentantCard
                        sentant={sentantData[0]}
                        {r2_node}
                        {variables}
                    />
                </Cards>
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "map"}
                <!--------------------------------------------------------------------------------------------->
                <Map {r2_node} {sentantData} {location} />
                <!--------------------------------------------------------------------------------------------->
            {:else if none_or_monitor_only(sentantData)}
                <!--------------------------------------------------------------------------------------------->
                <Message
                    ui
                    centered
                    green
                    massive
                    style="position: fixed; top: 100; left: 0; right: 0; z-index: 1000;"
                >
                    <Content ui>No Sentants</Content>
                </Message>
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "view"}
                <!--------------------------------------------------------------------------------------------->
                <SentantCards {r2_node} sentantData={filteredSentantData} {variables} {localNodeId} />
                <!--------------------------------------------------------------------------------------------->
            {:else if state == "mr"}
                <!--------------------------------------------------------------------------------------------->
                <!-- TODO: Implement Mixed Reality View
                     - Add WebXR integration using @threlte/xr
                     - Display sentants in 3D space
                     - Enable AR/VR modes
                     - Add hand tracking and controllers
                     - Implement spatial audio
                -->
                <Message
                    ui
                    centered
                    blue
                    massive
                    style="position: fixed; top: 100; left: 0; right: 0; z-index: 1000;"
                >
                    <Header>Mixed Reality View - In Development</Header>
                    <Content ui>
                        <p>3D/AR/VR visualization of sentants will be available in a future release.</p>
                        <p>This feature will use @threlte/xr for WebXR integration.</p>
                    </Content>
                </Message>
                <!--------------------------------------------------------------------------------------------->
            {/if}
        </Segment>
    {/if}
</main>
<!----------------------------------------------------------------------------------------------------->
