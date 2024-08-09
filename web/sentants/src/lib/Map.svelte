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
    // If you're playing with this in the Svelte REPL, import the CSS using the
    // syntax in svelte:head instead. For normal development, this is better.
    import 'leaflet/dist/leaflet.css';

    let map;
    let mapHeight = "400px";


    export let sentants: any[]|any = [];
    export let windowHeight: number = 800;
    export let windowWidth: number = 1024;

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
    });

    onDestroy(() => {
        // Clean up the event listener
        window.removeEventListener('resize', updateMapHeight);
    });

    function updateMapHeight() {
        const windowHeight = window.innerHeight;
        mapHeight = `${windowHeight - 100}px`;

        if(map) { map.invalidateSize() }
    }
</script>


<div id="map" style="width: 100%; height: {mapHeight};" />