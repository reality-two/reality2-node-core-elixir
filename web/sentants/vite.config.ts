import { defineConfig, Plugin } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

// Custom plugin to strip TypeScript generics from @xyflow/svelte files
function stripXyflowTypeScript(): Plugin {
  return {
    name: 'strip-xyflow-typescript',
    transform(code, id) {
      // Only process @xyflow/svelte .svelte files
      if (id.includes('@xyflow/svelte') && id.endsWith('.svelte')) {
        // Strip ALL TypeScript generic syntax: functionName<Type> becomes functionName
        // This handles nested generics like Context<Provider<NodeType, EdgeType>>
        let transformed = code;
        // Keep stripping until no more generics are found
        let prevCode;
        do {
          prevCode = transformed;
          transformed = transformed.replace(
            /(\w+)<[^<>]+>/g,
            '$1'
          );
        } while (transformed !== prevCode);

        return {
          code: transformed,
          map: null,
        };
      }
      return null;
    },
  };
}

// https://vitejs.dev/config/
export default defineConfig({
  base: "/sentants/",
  plugins: [
    stripXyflowTypeScript(),
    svelte({
      onwarn(warning, defaultHandler) {
        // Suppress unused export warnings for sentantData (reserved for future use)
        if (warning.code === 'export_let_unused' && warning.message?.includes('sentantData')) return;
        // Handle all other warnings
        if (defaultHandler) defaultHandler(warning);
      },
    }),
  ],
});

declare global {
  interface Window {
    showSaveFilePicker?: () => Promise<any>;
  }
}
