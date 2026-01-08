# Dependency Status

## ✅ Fixed Peer Dependency Issues

### Removed Unused Dependencies
- ❌ **svelte-apollo@0.5.0** - Not used in codebase, incompatible with Svelte 5
- ❌ **svelte-json-tree@2.2.0** - Not used in codebase, incompatible with Svelte 4+

### Updated to Svelte 5 Compatible Versions
- ✅ **svelte**: 5.19.6 → 5.25.0 (latest stable)
- ⚠️ **@xyflow/svelte**: Kept at 1.3.0 (versions >1.3.0 have build errors with Vite)
- ✅ **@testing-library/svelte**: 4.0.5 → 5.2.5 (Svelte 5 compatible)

## ⚠️ Known Warnings (Non-Breaking)

These packages may show peer dependency warnings but still work correctly with Svelte 5:

### @xyflow/svelte@1.0.0
- **Warning**: Shows peer dependency warning for Svelte ^5.25.0
- **Status**: Works correctly with Svelte 5.25.0 with custom Vite plugin
- **Issue**: ALL versions ship TypeScript syntax in distributed .svelte files
- **Solution**: Custom Vite plugin (`stripXyflowTypeScript`) strips TypeScript generics during build
- **Action**: Keep plugin in vite.config.ts until upstream fixes distribution
- **Tracked**: Will remove plugin when @xyflow/svelte ships proper JavaScript distribution

### svelte-fomantic-ui@0.3.9
- **Status**: Works with Svelte 5 despite warning
- **Used in**: All UI components (Card, Menu, Button, etc.)
- **Action**: No action needed - package is functional
- **Note**: Community package; may need migration to Flowbite/ShadcnUI in future

### svelte-qrcode@1.0.0
- **Status**: Works with Svelte 5
- **Used in**: Minimal usage (if any)
- **Action**: Monitor for Svelte 5 updates

## 📦 Major Dependencies

### UI & Visualization
- **Blockly 11.1.1** - Visual programming blocks
- **Leaflet 1.9.4** - Map visualization
- **@xyflow/svelte 1.5.11** - Flow diagrams (Swarm view)
- **@threlte/core & @threlte/xr** - 3D/VR (MR view - WIP)

### Data & Network
- **@apollo/client 3.7.15** - GraphQL client
- **graphql 16.6.0** - GraphQL runtime

### Testing
- **vitest 1.1.0** - Test runner
- **@testing-library/svelte 5.2.5** - Component testing
- **jsdom 23.0.1** - DOM simulation

## 🔄 Recommended Future Updates

1. **Consider migrating from svelte-fomantic-ui**
   - Options: Flowbite Svelte, ShadcnUI Svelte, or custom components
   - Reason: Better Svelte 5 support and modern design

2. **Update @apollo/client**
   - Current: 3.7.15
   - Latest: 3.x.x (check for security updates)

3. **Monitor for Svelte 5 updates**
   - @threlte packages
   - svelte-qrcode

## 📝 Installation

After dependency updates, run:

```bash
npm install
```

If you encounter errors, try:

```bash
rm -rf node_modules package-lock.json
npm install
```

## 🔧 Build Fixes

### Svelte 5 Warnings
- **Fixed**: `export_let_unused` warning in Construct.svelte
- **Solution**: Suppressed warning in vite.config.ts for `sentantData` prop (reserved for future use)
- **Note**: This prop is passed from App.svelte but not yet used internally
- **Warning Code**: Uses `export_let_unused` (not `unused-export-let`)

### @xyflow/svelte Build Error
- **Issue**: ALL versions (including 1.0.0, 1.3.0, 1.5.0+) ship TypeScript syntax in distributed .svelte files
- **Error**: `Expected a semicolon` due to TypeScript generics like `createStore<NodeType, EdgeType>`
- **Fix**: Added custom Vite plugin in vite.config.ts to strip TypeScript generics at build time
- **Plugin**: `stripXyflowTypeScript()` - transforms `functionName<Type>` → `functionName`
- **Result**: Build succeeds, production bundle works correctly

## 🚨 Breaking Changes

None expected with current updates. All changes maintain backward compatibility.
