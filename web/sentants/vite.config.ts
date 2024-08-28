import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// https://vitejs.dev/config/
export default defineConfig({
  base: "/sentants/",
  plugins: [svelte()]
})


declare global {
    interface Window {
      showSaveFilePicker?: () => Promise<any>;
    }
  }