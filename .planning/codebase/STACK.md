# Technology Stack

**Analysis Date:** 2026-02-13

## Languages

**Primary:**
- TypeScript 5.8.2 - Thin wrapper layer for Raycast extension entry point
- Swift 5.9+ (via swiftToolsVersion 5.9) - All application logic and UI rendering

**Secondary:**
- JavaScript - ESLint configuration (`eslint.config.js`)

## Runtime

**Environment:**
- macOS 13+ (minimum deployment target: `platforms: [.macOS(.v13)]`)
- TypeScript compiled to CommonJS (ES2023 target)
- Swift compiled to native macOS binary

**Package Managers:**
- npm 10+ (inferred from package.json) - TypeScript dependencies
- Swift Package Manager (swiftpm) - Swift dependencies
- Lockfile: `package-lock.json` present for npm

## Frameworks

**Core:**
- @raycast/api 1.104.5 - Raycast extension API and main window management
- @raycast/utils 1.17.0 - Raycast utilities
- RaycastSwiftMacros (from extensions-swift-tools 1.0.4+) - Swift macro for @raycast function decorator
- RaycastSwiftPlugin (from extensions-swift-tools 1.0.4+) - Swift build plugin for Raycast
- RaycastTypeScriptPlugin (from extensions-swift-tools 1.0.4+) - TypeScript build plugin for Raycast bridge

**UI & Graphics:**
- AppKit - Native macOS window management, events, and views (`NSWindow`, `NSView`, `NSEvent`)
- QuartzCore - Core Animation layers for GPU-composited rendering (`CAShapeLayer`, `CATextLayer`, `CAAnimationGroup`)
- CoreGraphics - Screen capture and pixel manipulation (`CGWindowListCreateImage`, color scanning)
- CoreText - Text rendering in Core Animation layers
- SwiftUI - Declarative UI framework (imported but minimal usage)

**Build & Development:**
- eslint 9.22.0 - JavaScript linting
- prettier 3.5.3 - Code formatting (120 char line width)
- @raycast/eslint-config 2.0.4 - Raycast-specific ESLint rules
- @types/node 22.13.10 - Node.js type definitions
- @types/react 19.0.10 - React type definitions

## Key Dependencies

**Critical:**
- extensions-swift-tools 1.0.4+ - Raycast's Swift/TypeScript bridge. Provides macros and build plugins that enable Swift functions to be callable from TypeScript. Without this, the Swift ↔ TypeScript communication layer doesn't exist.
- @raycast/api 1.104.5 - Entry point for command execution, preference reading, and window management. All Raycast-specific APIs route through this package.

**Infrastructure:**
- CoreGraphics (built-in to macOS) - Provides `CGWindowListCreateImage()` for fullscreen screenshot capture before window creation (critical for "frozen frame" effect)
- AppKit (built-in to macOS) - Event wiring, NSWindow subclass, NSScreen coordinate management
- QuartzCore (built-in to macOS) - CAShapeLayer, CATextLayer, CAAnimationGroup for GPU-composited rendering (critical for low-CPU performance)

## Configuration

**Environment:**
- Raycast command configuration in `package.json`: single `design-ruler` command, mode `no-view`
- User preferences passed to Swift: `hideHintBar` (boolean, default false), `corrections` (dropdown: smart/include/none, default smart)
- No external API keys or secrets required

**Build:**
- `tsconfig.json`: CommonJS module output, ES2023 target, strict TypeScript checking, JSX support, JSON module resolution
- `.prettierrc`: 120 char print width, double quotes (singleQuote: false)
- `eslint.config.js`: Uses @raycast/eslint-config preset (no custom rules)
- `package.json` scripts: `build` (ray build), `dev` (ray develop), `lint` (ray lint), `publish` (npx @raycast/api publish)

**Swift Build:**
- `Package.swift`: macOS 13+ deployment target, single executable target `Ruler`, dependencies on extensions-swift-tools 1.0.4+

## Platform Requirements

**Development:**
- macOS 13 or later
- Xcode or Command Line Tools (for Swift compilation)
- npm 10+ (for TypeScript/Raycast tooling)
- Raycast installed (for `ray` CLI commands)

**Production:**
- macOS 13 or later (minimum per Package.swift)
- Raycast application installed and running
- Screen recording permission granted at runtime (macOS security requirement, checked via `CGPreflightScreenCaptureAccess()`)
- Raycast permissions for clipboard/window management (if accessing Raycast APIs)

**Deployment:**
- Raycast Store (via `npm run publish`)
- Binary deployment: Only the compiled Swift binary is deployed (no `.bundle` directories, no resources)

---

*Stack analysis: 2026-02-13*
