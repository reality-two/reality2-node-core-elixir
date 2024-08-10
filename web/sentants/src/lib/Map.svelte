<!------------------------------------------------------------------------------------------------------
  A Map

  Author: Dr. Roy C. Davies
  Created: Feb 2024
  Contact: roycdavies.github.io
------------------------------------------------------------------------------------------------------->
<script lang="ts">

    import { onMount } from 'svelte';
    import { onDestroy } from 'svelte';

    import * as L from 'leaflet';
    import 'leaflet/dist/leaflet.css';

    import type { Sentant } from './reality2.js';
    import SentantCard from './SentantCard.svelte';

    import R2 from "./reality2";

    export let r2_node: R2;
    export let sentantData: any[]|any = [];

    let map: any;
    let mapHeight = "400px";

    let markers: {}|any = {};

    onMount(() => {

        console.log("MAP", sentantData);

        map = L.map('map').setView([-36.86365, 174.76023], 13);

        L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
            {
                attribution: `&copy;<a href="https://www.openstreetmap.org/copyright" target="_blank">OpenStreetMap</a>,
                &copy;<a href="https://carto.com/attributions" target="_blank">CARTO</a>`,
                subdomains: 'abcd'
            }).addTo(map);

        // Set the initial map height
        updateMapHeight();

        // Force Leaflet to recalculate the map size after it's rendered
        setTimeout(() => {
            map.invalidateSize();
        }, 0);

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

                    const sentantCard = document.createElement('div');
                    sentantCard.className = "cards ui centered";

                    const _card = new SentantCard({
                        target: sentantCard,
                        props: {
                            sentant: sentant,
                            r2_node: r2_node                            
                        }
                    });

                    markers[sentant.name].bindPopup(sentantCard);

                    markers[sentant.name].on('dragend', function(event:any) {
                        var marker = event.target;
                        var position = marker.getLatLng();
                        marker.setLatLng(new L.LatLng(position.lat, position.lng), {draggable:'true'});

                        r2_node.sentantSend(sentant.id, "set_position", {"latitude": position.lat, "longitude": position.lng});
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
            iconSize: [40, 40],
            iconAnchor: [0, 0],
            popupAnchor: [20, 10],
            shadowUrl: '/images/marker-shadow.svg',
            shadowSize: [40, 40],
            shadowAnchor: [1, 1]
        });
        return myIcon;
    }

    function updateMapHeight() {
        mapHeight = `${window.innerHeight - 100}px`;
        if(map) { map.invalidateSize() }
    }
</script>


<div id="map" style="width: 100%; height: {mapHeight};" />