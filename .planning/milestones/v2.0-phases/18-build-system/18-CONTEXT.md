# Phase 18: Build System - Context

**Gathered:** 2026-02-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract all shared Swift overlay/detection/rendering code into a `DesignRulerCore` library. Create an Xcode project for the standalone macOS app that references this library. Ensure the Raycast extension build (`ray build`) continues to pass unchanged. This phase is purely build infrastructure — no new features, no UI, no app behavior.

</domain>

<decisions>
## Implementation Decisions

### App Identity
- App name: **Design Ruler** (with space)
- Bundle identifier: **cv.haythem.designruler**

### Raycast Source Separation
- Raycast-specific Swift files (`@raycast` entry points) move to a dedicated subfolder (e.g. `swift/RaycastBridge/`)
- This cleanly separates Raycast bridge code from shared overlay logic

### macOS Compatibility
- Minimum deployment target: **macOS 14 Sonoma**
- Liquid glass: same fallback strategy as the Raycast extension (liquid glass on macOS 26+, NSVisualEffectView on older)
- Architecture: **Universal binary** (Apple Silicon + Intel)

### Claude's Discretion
- Xcode project name and structure (e.g. `DesignRulerApp.xcodeproj` or `Design Ruler.xcodeproj`)
- Organization name for copyright headers
- Where in the repo the Xcode project lives (alongside swift/, at root, etc.)
- Where shared library sources live (e.g. `Sources/DesignRulerCore/` structure)
- Whether to use local SPM package dependency or embed sources directly
- Swift language version for the Xcode project

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 18-build-system*
*Context gathered: 2026-02-18*
