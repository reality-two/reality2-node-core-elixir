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
    import R2 from "./reality2";

    export let r2_node: R2;
    export let sentants: any[]|any = [];

    let map: any;
    let mapHeight = "400px";

    onMount(() => {
        map = L.map('map').setView([51.505, -0.09], 13);

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
        sentants.foreach((sentant) => {
            r2node
        })
    });

    onDestroy(() => { window.removeEventListener('resize', updateMapHeight); });

    function updateMapHeight() {
        mapHeight = `${window.innerHeight - 100}px`;
        if(map) { map.invalidateSize() }
    }
</script>


<div id="map" style="width: 100%; height: {mapHeight};" />