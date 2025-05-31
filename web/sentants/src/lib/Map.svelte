<!------------------------------------------------------------------------------------------------------
  A Map

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io

  Wairoa: -39.060257, 177.406370
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    import { onMount } from 'svelte';
    import { onDestroy } from 'svelte';

    // @ts-ignore
    import * as L from 'leaflet';
    import 'leaflet/dist/leaflet.css';

    import type { Sentant } from './reality2.js';

    import R2 from "./reality2";

    export let r2_node: R2;
    export let sentantData: any[]|any = [];
    export let location: any = {};

    let map: any;
    let mapHeight = "400px";

    let markers: {}|any = {};

    onMount(() => {

        console.log(location);
        map = L.map('map').setView([location.latitude == undefined ? 0 : location.latitude, location.longitude == undefined ? 0 : location.longitude], location.latitude == undefined ? 5 : 13);

        L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png?access_token={token}', {
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
            token: 'pk.eyJ1Ijoicm95LWMtZGF2aWVzIiwiYSI6ImNtYmJjM216cjB5MjMyanBvYW50YnJuYmkifQ.4ZIRqPo0xg1h0i68wfNcBw'
        }).addTo(map);

        // Set the initial map height
        updateMapHeight();

        // Force Leaflet to recalculate the map size after it's rendered
        setTimeout(() => { map.invalidateSize(); }, 0);

        // Add resize event listener
        window.addEventListener('resize', updateMapHeight);

        // Go through each Sentant and send an AwaitSignal (even if invalid)
        sentantData.forEach((sentant:Sentant) => {
            if (markers.hasOwnProperty(sentant.name)) {
                if (map.hasLayer(markers[sentant.name])) {
                    map.removeLayer(markers[sentant.name]);
                }
            }

            r2_node.awaitSignal(sentant.id, "get", (data: any) => {
                if (R2.JSONPath(data, "status") == "connected") {
                    r2_node.sentantSend(sentant.id, "get_position", {});
                }
                else
                {
                    if (! (sentant.name in markers)) {
                        let location = R2.JSONPath(data, "parameters");
                        let icon = markerIcon();
                        let marker = L.marker([location.latitude, location.longitude], {icon, draggable: true});

                        markers[sentant.name] = marker;
                        markers[sentant.name].addTo(map);
                    }

                    markers[sentant.name].on("click", () => {
                        const popupContent = document.createElement("div");
                        popupContent.innerHTML = `
                            <div class="card ui" style="width: 250px; padding: 0px;">
                                <div class="image">
                                    <img src="/images/bee_blue.png">
                                </div>
                                <div class="content" style="text-align: center;">
                                    <div class="header">${sentant.name}</div>
                                    <p><Text ui tiny blue>${sentant.id}</Text></p>
                                    <p>${sentant.description}</p>
                                </div>
                            </div>
                        `;

                        const popup = L.popup({offset: [30, 20]})
                            .setLatLng(markers[sentant.name].getLatLng())
                            .setContent(popupContent)
                            .openOn(map);      
                    });

                    markers[sentant.name].on('dragend', function(event:any) {
                        var marker = event.target;
                        var position = marker.getLatLng();
                        marker.setLatLng(new L.LatLng(position.lat, position.lng), {draggable:'true'});
                        var result = r2_node.sentantSend(sentant.id, "set_position", {"latitude": position.lat, "longitude": position.lng});
                    });
                }
            });
        })
    });

    onDestroy(() => { 
        window.removeEventListener('resize', updateMapHeight); 
        map.remove();
    });

    function markerIcon() {
        // let html = `<div class="map-marker"><div><img style="width:60px;height:60px" src="/images/marker-icon.svg"/></div></div>`;
        // return L.divIcon({
        //     html,
        //     className: 'map-marker',
        // });

        var myIcon = L.icon({
            iconUrl: '/images/marker-icon.svg',
            iconSize: [60, 60],
            iconAnchor: [30, 30],
            shadowUrl: '/images/marker-shadow.svg',
            shadowSize: [60, 60],
            shadowAnchor: [31, 31]
        });
        return myIcon;
    }

    function updateMapHeight() {
        mapHeight = `${window.innerHeight - 64}px`;
        if(map) { map.invalidateSize() }
    }
</script>


<div id="map" style="width: 100%; height: {mapHeight}; position: absolute"></div>