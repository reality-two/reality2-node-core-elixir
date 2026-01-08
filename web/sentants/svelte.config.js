import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

export default {
  // Consult https://svelte.dev/docs#compile-time-svelte-preprocess
  // for more information about preprocessors
  preprocess: vitePreprocess(),
  // Note: Accessibility warnings are now enabled.
  // Please address a11y warnings instead of suppressing them to ensure
  // the application is accessible to all users.
  onwarn: (warning, handler) => {
    // Add any specific warnings to suppress here if absolutely necessary
    // Example: if (warning.code === 'specific-warning-code') return;
    handler(warning);
  },
};
