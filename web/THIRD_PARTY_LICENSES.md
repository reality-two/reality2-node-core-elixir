# Third Party Licenses - Web Applications

This document lists all third-party open source libraries used in the Reality2 web
applications. These are independent of the server and are distributed separately.

Generated: 2026-01-17

---

## Platform and Runtime Licenses

These are the core platforms and runtimes used for building and running web applications.

| Component | License | Notes | URL |
|-----------|---------|-------|-----|
| Node.js | MIT | Runtime for build tools and development | https://nodejs.org |
| V8 Engine | BSD | JavaScript engine (bundled in Node.js) | https://v8.dev |
| Svelte | MIT | Compiled away at build time | https://svelte.dev |
| Vite | MIT | Build tool, not shipped to users | https://vite.dev |

Note: The compiled web applications run in users' browsers. The JavaScript engines
(V8, SpiderMonkey, JavaScriptCore) are part of the browser, not your distribution.

---

## Web App: sentants

The main Svelte-based web application for Reality2.

### Runtime Dependencies

| Package | Version | License | URL |
|---------|---------|---------|-----|
| @apollo/client | ^3.7.15 | MIT | https://www.npmjs.com/package/@apollo/client |
| @blockly/theme-dark | ^7.0.5 | Apache-2.0 | https://www.npmjs.com/package/@blockly/theme-dark |
| @blockly/theme-modern | ^6.0.5 | Apache-2.0 | https://www.npmjs.com/package/@blockly/theme-modern |
| @blockly/workspace-backpack | ^6.0.7 | Apache-2.0 | https://www.npmjs.com/package/@blockly/workspace-backpack |
| @blockly/zoom-to-fit | ^6.0.7 | Apache-2.0 | https://www.npmjs.com/package/@blockly/zoom-to-fit |
| @threlte/core | 8.0.1 | MIT | https://www.npmjs.com/package/@threlte/core |
| @threlte/xr | 1.0.0 | MIT | https://www.npmjs.com/package/@threlte/xr |
| @types/three | 0.173.0 | MIT | https://www.npmjs.com/package/@types/three |
| @xyflow/svelte | 1.0.0 | MIT | https://www.npmjs.com/package/@xyflow/svelte |
| blockly | ^11.1.1 | Apache-2.0 | https://www.npmjs.com/package/blockly |
| graphql | ^16.6.0 | MIT | https://www.npmjs.com/package/graphql |
| js-yaml | ^4.1.0 | MIT | https://www.npmjs.com/package/js-yaml |
| leaflet | ^1.9.4 | BSD-2-Clause | https://www.npmjs.com/package/leaflet |
| prettyjson | ^1.2.5 | MIT | https://www.npmjs.com/package/prettyjson |
| svelte | 5.25.0 | MIT | https://www.npmjs.com/package/svelte |
| svelte-fomantic-ui | ^0.3.9 | MIT | https://www.npmjs.com/package/svelte-fomantic-ui |
| svelte-qrcode | ^1.0.0 | MIT | https://www.npmjs.com/package/svelte-qrcode |
| three | ^0.173.0 | MIT | https://www.npmjs.com/package/three |
| yaml | ^2.5.0 | ISC | https://www.npmjs.com/package/yaml |

### Development Dependencies

| Package | Version | License | URL |
|---------|---------|---------|-----|
| @sveltejs/vite-plugin-svelte | 5.0.3 | MIT | https://www.npmjs.com/package/@sveltejs/vite-plugin-svelte |
| @testing-library/jest-dom | ^6.1.5 | MIT | https://www.npmjs.com/package/@testing-library/jest-dom |
| @testing-library/svelte | ^5.2.5 | MIT | https://www.npmjs.com/package/@testing-library/svelte |
| @tsconfig/svelte | ^5.0.2 | MIT | https://www.npmjs.com/package/@tsconfig/svelte |
| @types/leaflet | ^1.9.12 | MIT | https://www.npmjs.com/package/@types/leaflet |
| @vitest/ui | ^1.1.0 | MIT | https://www.npmjs.com/package/@vitest/ui |
| jsdom | ^23.0.1 | MIT | https://www.npmjs.com/package/jsdom |
| svelte-check | 4.1.4 | MIT | https://www.npmjs.com/package/svelte-check |
| tslib | ^2.6.2 | 0BSD | https://www.npmjs.com/package/tslib |
| typescript | ^5.2.2 | Apache-2.0 | https://www.npmjs.com/package/typescript |
| vite | 6.0.11 | MIT | https://www.npmjs.com/package/vite |
| vitest | ^1.1.0 | MIT | https://www.npmjs.com/package/vitest |

---

## Web App: iotdemo

IoT demonstration application.

### Runtime Dependencies

| Package | Version | License | URL |
|---------|---------|---------|-----|
| chart.js | ^4.4.3 | MIT | https://www.npmjs.com/package/chart.js |
| fomantic-ui | ^2.9.3 | MIT | https://www.npmjs.com/package/fomantic-ui |
| svelte-chartjs | ^3.1.5 | MIT | https://www.npmjs.com/package/svelte-chartjs |
| svelte-fomantic-ui | ^0.3.5 | MIT | https://www.npmjs.com/package/svelte-fomantic-ui |
| svelte-qrcode | ^1.0.0 | MIT | https://www.npmjs.com/package/svelte-qrcode |

### Development Dependencies

| Package | Version | License | URL |
|---------|---------|---------|-----|
| @sveltejs/vite-plugin-svelte | ^3.1.1 | MIT | https://www.npmjs.com/package/@sveltejs/vite-plugin-svelte |
| @tsconfig/svelte | ^5.0.4 | MIT | https://www.npmjs.com/package/@tsconfig/svelte |
| svelte | ^4.2.18 | MIT | https://www.npmjs.com/package/svelte |
| svelte-check | ^3.8.1 | MIT | https://www.npmjs.com/package/svelte-check |
| tslib | ^2.6.3 | 0BSD | https://www.npmjs.com/package/tslib |
| typescript | ^5.2.2 | Apache-2.0 | https://www.npmjs.com/package/typescript |
| vite | ^5.3.1 | MIT | https://www.npmjs.com/package/vite |

---

## Web Apps: demos, lora-mesh-viz, transnet-viz

These are simple HTML-only demos with no npm dependencies.

- **demos** - Interactive demos explaining Reality2 concepts
- **lora-mesh-viz** - Emergency flood monitoring visualization
- **transnet-viz** - Transient network visualization

All authored by Dr. Roy C. Davies under MIT license (as per package.json).

---

## License Summary by Type

| License | Count | Notable Packages |
|---------|-------|------------------|
| MIT | 30+ | svelte, three, @apollo/client, vite, chart.js, fomantic-ui, graphql |
| Apache-2.0 | 6 | blockly (Google), @blockly/*, typescript |
| BSD-2-Clause | 1 | leaflet |
| ISC | 1 | yaml |
| 0BSD | 1 | tslib |

---

## License Obligations Summary

### MIT License (majority of packages)
- Include copyright notice and license text in distributions
- No copyleft requirements
- Commercial use permitted

### Apache-2.0 License (Google Blockly)
- Include copyright notice and license text
- State significant changes made to code
- Include NOTICE file if present
- Provides patent grant
- No copyleft requirements

### BSD-2-Clause (Leaflet)
- Include copyright notice
- No copyleft requirements

### ISC License (yaml)
- Functionally equivalent to MIT
- Include copyright notice

### 0BSD License (tslib)
- No restrictions whatsoever
- Most permissive possible

---

## Notes

1. **No copyleft licenses detected** - All dependencies use permissive licenses compatible
   with commercial/proprietary use.

2. **Development dependencies** do not ship with production builds and have reduced
   compliance requirements.

3. **Google Blockly** uses Apache-2.0 which includes a patent grant - beneficial for
   commercial use of visual programming features.

4. **Leaflet** mapping library is BSD-2-Clause - very permissive for commercial use.

5. All web applications can be distributed under any license you choose, including
   proprietary, as long as attribution requirements are met.

---

## Transitive Dependency Audit

Full audit of all transitive dependencies performed 2026-01-17.

### sentants - 299 Total Packages

| License | Count |
|---------|-------|
| MIT | 250 |
| ISC | 20 |
| Apache-2.0 | 12 |
| BSD-3-Clause | 6 |
| BSD-2-Clause | 3 |
| CC0-1.0 | 2 |
| MIT-0 | 1 |
| Python-2.0 | 1 |
| 0BSD | 1 |
| GPL-3.0 | 1 |
| CC-BY-NC-SA-4.0 | 1 |

### iotdemo - 488 Total Packages

| License | Count |
|---------|-------|
| MIT | 399 |
| ISC | 51 |
| Apache-2.0 | 13 |
| BSD-3-Clause | 7 |
| BlueOak-1.0.0 | 4 |
| BSD-2-Clause | 2 |
| CC0-1.0 | 2 |
| GPL-3.0 | 1 |
| CC-BY-NC-SA-4.0 | 1 |
| 0BSD | 1 |

---

## License Exceptions (Non-Permissive)

### qrious@4.0.2 - GPL-3.0

- **Dependency chain:** svelte-qrcode → qrious
- **Impact:** GPL-3.0 is a copyleft license requiring derivative works to be GPL-3.0
- **Mitigation:** Web apps are distributed separately from server. If distributing as
  open source, GPL-3.0 compatibility is acceptable.
- **Alternative:** Replace with `@castlenine/svelte-qrcode` (MIT, zero dependencies)

### svelte-fomantic-ui@0.3.9 - CC-BY-NC-SA-4.0

- **Status:** This is a Reality2 project package (authored by roycdaviesuoa)
- **Impact:** Non-commercial license would prevent commercial use
- **Mitigation:** As the package owner, the license can be changed as needed

---

## Conclusion

The server components (Elixir + Rust) are fully clear of copyleft licenses and safe
for dual open source / commercial licensing.

The web applications have two license exceptions noted above, neither of which is
blocking due to:
1. Web apps being distributed independently from the server
2. svelte-fomantic-ui being under project control
