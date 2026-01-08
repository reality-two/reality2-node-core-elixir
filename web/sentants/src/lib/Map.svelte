<!------------------------------------------------------------------------------------------------------
  A Map

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io

  Wairoa: -39.060257, 177.406370
------------------------------------------------------------------------------------------------------->
<script lang="ts">
    import { onMount } from "svelte";
    import { onDestroy } from "svelte";

    // @ts-ignore - Leaflet doesn't have proper TypeScript support for all methods
    import * as L from "leaflet";
    import "leaflet/dist/leaflet.css";

    import type { Sentant, Location, SignalData } from "./types";
    import {
        DEFAULT_MAP_HEIGHT_PX,
        MAP_ZOOM_LEVEL_DEFAULT,
        MAP_ZOOM_LEVEL_WITH_LOCATION,
        MAPBOX_TILE_SIZE,
        MAPBOX_ZOOM_OFFSET,
        HEADER_HEIGHT_PX,
    } from "./constants";
    import R2 from "./reality2";

    export let r2_node: R2;
    export let sentantData: Sentant[] = [];
    export let location: Location = { latitude: 0, longitude: 0 };

    let map: L.Map;
    let mapHeight = `${DEFAULT_MAP_HEIGHT_PX}px`;

    let markers: Record<string, L.Marker> = {};

    onMount(() => {
        console.log(location);
        map = L.map("map").setView(
            [
                location.latitude == undefined ? 0 : location.latitude,
                location.longitude == undefined ? 0 : location.longitude,
            ],
            location.latitude == undefined ? MAP_ZOOM_LEVEL_DEFAULT : MAP_ZOOM_LEVEL_WITH_LOCATION,
        );

        // Use Mapbox tile layer with access token from environment
        const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;

        L.tileLayer(
            "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={accessToken}",
            {
                attribution:
                    '&copy; <a href="https://www.mapbox.com/about/maps/">Mapbox</a> &copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
                accessToken: mapboxToken,
                tileSize: MAPBOX_TILE_SIZE,
                zoomOffset: MAPBOX_ZOOM_OFFSET,
            },
        ).addTo(map);

        // Set the initial map height
        updateMapHeight();

        // Force Leaflet to recalculate the map size after it's rendered
        setTimeout(() => {
            map.invalidateSize();
        }, 0);

        // Add resize event listener
        window.addEventListener("resize", updateMapHeight);

        // Go through each Sentant and send an AwaitSignal (even if invalid)
        sentantData.forEach((sentant: Sentant) => {
            if (markers.hasOwnProperty(sentant.name)) {
                if (map.hasLayer(markers[sentant.name])) {
                    map.removeLayer(markers[sentant.name]);
                }
            }

            r2_node.awaitSignal(sentant.id, "get", (data: SignalData) => {
                if (R2.JSONPath(data, "status") == "connected") {
                    r2_node.sentantSend(sentant.id, "get_position", {});
                } else {
                    if (!(sentant.name in markers)) {
                        let location = R2.JSONPath(data, "parameters");
                        let icon = markerIcon();
                        let marker = L.marker(
                            [location.latitude, location.longitude],
                            { icon, draggable: true },
                        );

                        markers[sentant.name] = marker;
                        markers[sentant.name].addTo(map);
                    }

                    markers[sentant.name].on("click", () => {
                        // Create popup content safely using DOM APIs to prevent XSS
                        const card = document.createElement("div");
                        card.className = "card ui";
                        card.style.width = "250px";
                        card.style.padding = "0px";

                        const imageDiv = document.createElement("div");
                        imageDiv.className = "image";
                        const img = document.createElement("img");
                        img.src = "/images/bee_blue.png";
                        imageDiv.appendChild(img);

                        const contentDiv = document.createElement("div");
                        contentDiv.className = "content";
                        contentDiv.style.textAlign = "center";

                        const header = document.createElement("div");
                        header.className = "header";
                        header.textContent = sentant.name;

                        const idPara = document.createElement("p");
                        const idText = document.createElement("span");
                        idText.className = "ui tiny blue text";
                        idText.textContent = sentant.id;
                        idPara.appendChild(idText);

                        const descPara = document.createElement("p");
                        descPara.textContent = sentant.description;

                        contentDiv.appendChild(header);
                        contentDiv.appendChild(idPara);
                        contentDiv.appendChild(descPara);

                        card.appendChild(imageDiv);
                        card.appendChild(contentDiv);

                        const popup = L.popup({ offset: [30, 20] })
                            .setLatLng(markers[sentant.name].getLatLng())
                            .setContent(card)
                            .openOn(map);
                    });

                    markers[sentant.name].on("dragend", function (event: L.DragEndEvent) {
                        var marker = event.target;
                        var position = marker.getLatLng();
                        marker.setLatLng(
                            new L.LatLng(position.lat, position.lng),
                            { draggable: "true" },
                        );
                        var result = r2_node.sentantSend(
                            sentant.id,
                            "set_position",
                            { latitude: position.lat, longitude: position.lng },
                        );
                    });
                }
            });
        });
    });

    onDestroy(() => {
        window.removeEventListener("resize", updateMapHeight);
        map.remove();
    });

    function markerIcon() {
        // let html = `<div class="map-marker"><div><img style="width:60px;height:60px" src="/images/marker-icon.svg"/></div></div>`;
        // return L.divIcon({
        //     html,
        //     className: 'map-marker',
        // });

        var myIcon = L.icon({
            iconUrl: "/images/marker-icon.svg",
            iconSize: [60, 60],
            iconAnchor: [30, 30],
            shadowUrl: "/images/marker-shadow.svg",
            shadowSize: [60, 60],
            shadowAnchor: [31, 31],
        });
        return myIcon;
    }

    function updateMapHeight() {
        mapHeight = `${window.innerHeight - HEADER_HEIGHT_PX}px`;
        if (map) {
            map.invalidateSize();
        }
    }
</script>

<div
    id="map"
    style="width: 100%; height: {mapHeight}; position: absolute"
></div>
