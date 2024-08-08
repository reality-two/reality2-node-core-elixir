<script lang="ts">
    import { Bar } from 'svelte-chartjs';
    import { Chart, Title, Tooltip, Legend, BarElement, CategoryScale, LinearScale } from 'chart.js';

    export let liveData: any[] = [];

    let options = {
        responsive: true,
        animation: false,
        scales: {
            y: { ticks: { font: { size: 40 } } },
            x: { ticks: { font: { size: 40 } } }
        },
        plugins: {
            legend: { display: false },
            title: {
                display: true,
                text: 'Live Data',
                font: { size: 40 }
            }
        }
    }

    $: data = {
            labels: ['red', 'yellow', 'green', 'blue', 'purple'],
            datasets: [
            {
                data: liveData,
                backgroundColor: [
                    'rgba(255, 134, 159, 1)',
                    'rgba(255, 218, 128, 1)',
                    'rgba(113, 250, 113, 1)',
                    'rgba(98,  182, 239, 1)',
                    'rgba(170, 128, 252, 1)',
                ],
                borderWidth: 2,
                borderColor: [
                    'rgba(255, 134, 159, 1)',
                    'rgba(255, 218, 128, 1)',
                    'rgba(113, 250, 113, 1)',
                    'rgba(98,  182, 239, 1)',
                    'rgba(170, 128, 252, 1)',
                ]
            }
        ]
    }

    Chart.register( Title, Tooltip, Legend, BarElement, CategoryScale, LinearScale );
  
</script>

<Bar {data} {options} />