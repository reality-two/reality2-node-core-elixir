import { defineConfig, Plugin } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { readFileSync } from "fs";
import { execSync } from "child_process";

const pkg = JSON.parse(readFileSync("./package.json", "utf-8"));
const gitCommit = (() => { try { return execSync("git rev-parse --short HEAD").toString().trim(); } catch { return "unknown"; } })();

// Custom plugin to strip TypeScript generics from @xyflow/svelte and @threlte files
function stripLibraryTypeScript(): Plugin {
  return {
    name: 'strip-library-typescript',
    enforce: 'pre',
    transform(code, id) {
      const needsStripping = (id.includes('@xyflow/svelte') || id.includes('@threlte')) && id.endsWith('.svelte');
      if (needsStripping) {
        let transformed = code;

        // Strip generics iteratively (handles nested generics)
        // Key: NO whitespace between identifier and < (distinguishes from comparisons like `i < n`)
        // Only match single-line content inside <> to avoid cross-line disasters
        let prevCode;
        do {
          prevCode = transformed;
          // Match identifier IMMEDIATELY followed by < ... > on same line
          // [^\n<>]* = anything except newline, <, or >
          transformed = transformed.replace(
            /([A-Za-z_]\w*)<([^\n<>]*)>/g,
            '$1'
          );
          // Also strip generic function declarations: = <T extends Foo> or =<T>
          transformed = transformed.replace(
            /=\s*<[^\n<>()]*>\s*\(/g,
            '= ('
          );
        } while (transformed !== prevCode);

        // Strip inline object type annotations like <{ distance?; hysteresis? }>
        transformed = transformed.replace(/<\s*\{[^{}\n]*\}\s*>/g, '');

        // Strip `as Type` casts - but NOT import renames like `import { X as Y }`
        // Only strip when followed by type-only patterns: any, unknown, const, keyof, typeof, or types with [] or <>
        // This is conservative but avoids breaking import renames
        let asPrev;
        do {
          asPrev = transformed;
          // Strip `as any`, `as unknown`, `as const`
          transformed = transformed.replace(/\s+as\s+(any|unknown|const)\b/g, '');
          // Strip `as keyof X` or `as typeof X`
          transformed = transformed.replace(/\s+as\s+(?:keyof|typeof)\s+[A-Za-z_][\w.]*/g, '');
          // Strip `as Type[]` (array types)
          transformed = transformed.replace(/\s+as\s+[A-Za-z_][\w.]*\[\]/g, '');
          // Strip `as Type<...>` (generic types - already simplified by earlier pass)
          transformed = transformed.replace(/\s+as\s+[A-Za-z_][\w.]*<[^\n<>]*>/g, '');
        } while (asPrev !== transformed);

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
    stripLibraryTypeScript(),
    svelte(),
  ],
  optimizeDeps: {
    // Exclude packages that need custom TypeScript stripping from esbuild pre-bundling
    exclude: ['@threlte/core', '@threlte/extras', '@xyflow/svelte'],
  },
});
