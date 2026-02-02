import { defineConfig, Plugin } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

// Custom plugin to strip TypeScript generics from @xyflow/svelte files
function stripXyflowTypeScript(): Plugin {
  return {
    name: 'strip-xyflow-typescript',
    transform(code, id) {
      if (id.includes('@xyflow/svelte') && id.endsWith('.svelte')) {
        let transformed = code;
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

export default defineConfig({
  base: "/creator/",
  plugins: [
    stripXyflowTypeScript(),
    svelte(),
  ],
});
