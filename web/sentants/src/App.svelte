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
                        "name id description events { event parameters } signals",
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
                        "name id description events { event parameters } signals",
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
                        "name id description events { event parameters } signals",
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
            var sentant_id = R2.JSONPath(updates, "parameters.id");
            var sentant_name = R2.JSONPath(updates, "parameters.name");
            if (sentant_id !== null && sentant_name !== RESERVED_SENTANT_NAMES.VIEW) {
                switch (R2.JSONPath(updates, "parameters.activity")) {
                    case "created":
                        r2_node
                            .sentantGet(
                                sentant_id,
                                {},
                                "name id description events { event parameters } signals",
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
                if (elements.length > 1) {
                    new_location =
                        "https://" +
                        (use_default_url ? "localhost" : elements[0]) +
                        ":" +
                        (use_default_url ? "4005" : window.location.port) +
                        "/?name=" +
                        elements[1] +
                        "&variables=" +
                        encodeURIComponent(JSON.stringify(variables));
                } else {
                    new_location =
                        "https://" +
                        (use_default_url ? "localhost" : elements[0]) +
                        ":" +
                        (use_default_url ? "4005" : window.location.port) +
                        "/?variables=" +
                        encodeURIComponent(JSON.stringify(variables));
                }

                if (elements[0] == "localhost" || elements[0] == "127.0.0.1") {
                    window.location.href = new_location;
                } else {
                    isServerReachable(new_location).then((reachable) => {
                        if (reachable) {
                            window.location.href = new_location;
                        } else {
                            alert(
                                "Reality2 server " +
                                    new_location +
                                    " is not reachable.",
                            );
                        }
                    });
                }
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
            <Item style={"margin: auto; width:" + (windowWidth - 260) + "px;"}>
                <Input ui big style={"width:100%;"}>
                    <Input
                        id="path"
                        text
                        placeholder="Enter Path..."
                        bind:value={path}
                    />
                </Input>
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
                <SentantCards {r2_node} {sentantData} {variables} />
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
