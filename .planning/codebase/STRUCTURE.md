# Codebase Structure

**Analysis Date:** 2026-02-13

## Directory Layout

```
design-ruler/
├── src/                                  # TypeScript: Raycast entry point
│   └── design-ruler.ts                  # Single command handler
├── swift/                               # Swift: All application logic
│   └── Ruler/
│       ├── Package.swift                # SPM package manifest
│       ├── Sources/
│       │   ├── Ruler.swift              # Entry point, orchestration
│       │   ├── RulerWindow.swift        # Fullscreen overlay, event handling
│       │   ├── EdgeDetection/           # Pixel scanning engine
│       │   │   ├── EdgeDetector.swift   # Main detection class
│       │   │   ├── ColorMap.swift       # Pixel buffer + scanning
│       │   │   └── DirectionalEdges.swift  # Edge models
│       │   ├── Rendering/               # UI layers (CALayer-based)
│       │   │   ├── CrosshairView.swift  # Crosshair overlay
│       │   │   ├── SelectionManager.swift  # Selection tracking
│       │   │   ├── SelectionOverlay.swift  # Individual selection boxes
│       │   │   ├── HintBarView.swift    # Keyboard hints
│       │   │   └── HintBarContent.swift # Key cap drawing
│       │   ├── Utilities/               # Helpers
│       │   │   └── CoordinateConverter.swift  # AppKit ↔ AX conversion
│       │   └── Permissions/             # Permission checking
│       │       └── PermissionChecker.swift
│       └── .build/                      # SPM build artifacts (git-ignored)
├── test/                                # Test assets
│   └── calibration.html                 # Manual calibration reference
├── node_modules/                        # npm dependencies (git-ignored)
├── .planning/                           # GSD documentation (generated)
├── assets/                              # Extension icon
├── package.json                         # npm manifest (command, preferences)
├── package-lock.json                    # npm lockfile
├── tsconfig.json                        # TypeScript config
├── CLAUDE.md                            # Implementation blueprint
├── README.md                            # Project overview
└── CHANGELOG.md                         # Version history
```

## Directory Purposes

**src/:**
- Purpose: TypeScript layer — thin wrapper reading preferences and invoking Swift
- Contains: Single command definition, preference interface, async handler
- Key files: `src/design-ruler.ts`

**swift/Ruler/Sources/:**
- Purpose: All application logic
- Contains: Seven subdirectories organizing by concern

**EdgeDetection/:**
- Purpose: Pixel-level analysis — capture, scan, edge detection, selection snapping
- Contains: Screen capture to RGBA pixel buffer; 4-direction color-difference scanning with stabilization; inward-scan snapping
- Key files: `EdgeDetector.swift` (main API), `ColorMap.swift` (scanning engine), `DirectionalEdges.swift` (models)

**Rendering/:**
- Purpose: GPU-composited UI overlays using CALayer
- Contains: Crosshair lines/feet/pill, selection boxes, hint bar
- Key files: `CrosshairView.swift` (main overlay), `SelectionManager.swift` (drag-to-snap), `HintBarView.swift` (keyboard hints)

**Utilities/:**
- Purpose: Coordinate system conversion and OS-level checks
- Contains: AppKit ↔ AX coordinate flipping, screen recording permission API
- Key files: `CoordinateConverter.swift`, `PermissionChecker.swift`

**Permissions/:**
- Purpose: macOS permission handling
- Contains: Screen recording access check and request
- Key files: `PermissionChecker.swift`

## Key File Locations

**Entry Points:**
- `src/design-ruler.ts`: TypeScript → Raycast invocation (reads hideHintBar, corrections prefs)
- `swift/Ruler/Sources/Ruler.swift` (line 4): Swift @raycast macro; warmup, delegate to Ruler.run()
- `swift/Ruler/Sources/Ruler.swift` (line 22): Ruler.run() — main orchestration loop

**Configuration:**
- `package.json`: Command definition, preferences (hideHintBar checkbox, corrections dropdown)
- `swift/Ruler/Package.swift`: SPM manifest (macOS 13+, extensions-swift-tools dependency)
- `tsconfig.json`: TypeScript ES2023, strict mode, commonjs module

**Core Logic:**
- `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift`: Edge detection API (capture, onMouseMoved, incrementSkip, snapSelection)
- `swift/Ruler/Sources/EdgeDetection/ColorMap.swift`: Pixel buffer + scanDirection (stabilization algorithm)
- `swift/Ruler/Sources/RulerWindow.swift`: Event routing (mouseMoved, keyDown, mouseDown/Up/Dragged)

**Rendering:**
- `swift/Ruler/Sources/Rendering/CrosshairView.swift`: CALayer-based crosshair (lines, feet, pill)
- `swift/Ruler/Sources/Rendering/SelectionManager.swift`: Drag-to-snap workflow
- `swift/Ruler/Sources/Rendering/HintBarView.swift`: Keyboard hint slides

**Testing:**
- `test/calibration.html`: Manual reference for verifying measurements (not automated tests)

## Naming Conventions

**Files:**
- PascalCase: `EdgeDetector.swift`, `ColorMap.swift`, `RulerWindow.swift`
- Lowercase: `package.json`, `tsconfig.json`

**Directories:**
- PascalCase for feature groups: `EdgeDetection/`, `Rendering/`, `Utilities/`, `Permissions/`
- Lowercase for project root: `src/`, `swift/`, `test/`, `assets/`, `node_modules/`

**Classes/Structs:**
- PascalCase: `EdgeDetector`, `ColorMap`, `EdgeHit`, `DirectionalEdges`, `CrosshairView`, `RulerWindow`

**Functions/Methods:**
- camelCase: `onMouseMoved()`, `scanDirection()`, `incrementSkip()`, `snapSelection()`, `hideForDrag()`, `updatePosition()`

**Variables:**
- camelCase: `skipCounts`, `colorMap`, `cursorPosition`, `screenFrame`, `pillIsOnLeft`

**Constants:**
- UPPER_SNAKE_CASE (rarely used; most constants are inline): `stabilizationNeeded = 3`
- PascalCase enum cases: `case .smart`, `case .include`, `case .none` (CorrectionMode)

## Where to Add New Code

**New Feature (e.g., grid overlay):**
- Primary code: `swift/Ruler/Sources/Rendering/GridView.swift` (new NSView subclass)
- Integration point: Add to RulerWindow.setupViews(), add layer to container
- Related: Update CrosshairView if grid needs to interact with crosshair
- Tests: Manual testing via Raycast dev extension

**New Rendering Component (e.g., distance labels):**
- Implementation: `swift/Ruler/Sources/Rendering/DistanceLabels.swift` (CATextLayer-based)
- Integration: Create in RulerWindow.setupViews(), update on CrosshairView.update() via callback
- Pattern: Follow CrosshairView design — CALayers, no draw() override, animations via CATransaction

**New Edge Detection Algorithm (e.g., edge-following):**
- Implementation: `swift/Ruler/Sources/EdgeDetection/EdgeFollower.swift` (new struct/class)
- Integration: Call from EdgeDetector after current scan, return alternative edges
- Pattern: Return DirectionalEdges, respect coordinate systems (input AppKit → convert to AX → scan → return to AppKit)

**New Preference:**
- package.json: Add to preferences array (checkbox, dropdown, text, etc.)
- src/design-ruler.ts: Add to Preferences interface, destructure, pass to Swift
- swift/Ruler/Sources/Ruler.swift: Add parameter to @raycast func inspect(), pass to RulerWindow.create()

**Utilities (shared helpers):**
- Coordinate conversion: `swift/Ruler/Sources/Utilities/CoordinateConverter.swift`
- OS-level checks: `swift/Ruler/Sources/Permissions/PermissionChecker.swift`
- New domain-specific helpers: Create new file in `Utilities/` (e.g., `GeometryHelpers.swift`)

## Special Directories

**swift/Ruler/.build/:**
- Purpose: SPM build artifacts
- Generated: Yes (by `swift build`)
- Committed: No (in .gitignore)

**swift/Ruler/.raycast-swift-build/:**
- Purpose: Raycast CLI build cache for extension
- Generated: Yes (by `ray build`)
- Committed: No (in .gitignore)
- Note: If build fails, delete this directory and rebuild

**node_modules/:**
- Purpose: npm dependencies
- Generated: Yes (by `npm install`)
- Committed: No (in .gitignore)
- Note: package-lock.json IS committed for reproducible installs

**assets/:**
- Purpose: Extension icon and other static assets
- Generated: No
- Committed: Yes
- Contains: `extension-icon.png` and other promotional images

## Architecture by File Dependency

**Tier 1 (No dependencies):**
- `DirectionalEdges.swift`: Defines EdgeHit, DirectionalEdges structs
- `CoordinateConverter.swift`: Enum with static conversion methods
- `PermissionChecker.swift`: Enum with static permission APIs

**Tier 2 (Depends on Tier 1):**
- `ColorMap.swift`: Uses DirectionalEdges
- `EdgeDetector.swift`: Uses ColorMap, DirectionalEdges, CorrectionMode

**Tier 3 (Depends on Tier 2):**
- `SelectionManager.swift`: Uses EdgeDetector
- `HintBarContent.swift`: Standalone rendering

**Tier 4 (Depends on Tier 3):**
- `CrosshairView.swift`: Uses DirectionalEdges (for pill dimensions)
- `SelectionOverlay.swift`: Standalone rendering
- `HintBarView.swift`: Uses HintBarContent

**Tier 5 (Depends on Tier 4):**
- `RulerWindow.swift`: Uses EdgeDetector, CrosshairView, HintBarView, SelectionManager, CoordinateConverter

**Tier 6 (Top-level):**
- `Ruler.swift`: Uses RulerWindow, EdgeDetector, PermissionChecker, CoordinateConverter
- `design-ruler.ts`: Uses Swift inspect() function

## Build Configuration

**TypeScript:**
- Compiler: TypeScript 5.8.2
- Target: ES2023
- Module: commonjs
- Strict mode: On
- Output: Transpiled by Raycast build tool

**Swift:**
- Language: Swift 5.9+
- Platform: macOS 13+
- Build system: Swift Package Manager (SPM)
- Dependencies: RaycastSwiftMacros (for @raycast macro), extensions-swift-tools
- Build command: `swift build` (used by Raycast)

**Raycast:**
- Build: `ray build` (CLI tool)
- Dev: `ray develop`
- Publishes: Binary from swift/.build/release/Ruler, does NOT include .bundle resources
