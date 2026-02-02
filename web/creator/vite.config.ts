import { defineConfig, Plugin } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { readFileSync } from "fs";
import { execSync } from "child_process";

const pkg = JSON.parse(readFileSync("./package.json", "utf-8"));
const gitCommit = (() => { try { return execSync("git rev-parse --short HEAD").toString().trim(); } catch { return "unknown"; } })();

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
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
    __GIT_COMMIT__: JSON.stringify(gitCommit),
  },
  plugins: [
    stripXyflowTypeScript(),
    svelte(),
  ],
});
