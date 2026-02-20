# Phase 18: Build System - Research

**Researched:** 2026-02-18
**Domain:** Swift Package Manager restructuring + Xcode project creation (macOS)
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- App name: **Design Ruler** (with space)
- Bundle identifier: **cv.haythem.designruler**
- Raycast-specific Swift files (`@raycast` entry points) move to a dedicated subfolder (e.g. `swift/RaycastBridge/`)
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

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

This phase extracts shared Swift code into a `DesignRulerCore` library target inside the existing `Package.swift`, moves the two `@raycast`-annotated entry point files into a `Sources/RaycastBridge/` subdirectory (the new executable target), and creates a minimal Xcode project for the standalone macOS app that references `DesignRulerCore` as a local package dependency.

The critical constraint is Raycast's build system: it parses the `Package.swift` via `swift package dump-package` and **errors if it finds more than one executable target**. Library targets (type `"regular"`) are invisible to this check and can coexist safely. This means the DesignRulerCore library can live in the same `Package.swift` as the DesignRuler executable without breaking `ray build`.

Access modifiers need upgrading from implicit `internal` to `package` (Swift 5.9+) on all shared types, since the executable target and library target become separate Swift modules. The Xcode app stub in Phase 18 does not call any `DesignRulerCore` APIs, so `package` access is sufficient for Phase 18 (Phase 19+ will selectively add `public` as the app's coordinators are built).

**Primary recommendation:** Keep `DesignRulerCore` as a second target inside the existing `Package.swift`, use xcodegen to create the standalone app's Xcode project, and use the `package` access modifier on all shared types.

---

## Standard Stack

### Core
| Tool/Library | Version | Purpose | Why Standard |
|---|---|---|---|
| Swift Package Manager | Built-in (swift 6.2) | Library target management | Native toolchain, zero config |
| xcodegen | 2.44.1 | Generate `.xcodeproj` from YAML spec | Keeps project.pbxproj out of manual editing; version-controlled as YAML |

### Supporting
| Tool | Version | Purpose | When to Use |
|---|---|---|---|
| xcodebuild | Xcode 26.2 | Build the Xcode app target | CI and local verification |
| brew | system | Install xcodegen | One-time setup |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|---|---|---|
| xcodegen (YAML) | Hand-written project.pbxproj | xcodegen is far less error-prone; pbxproj is notoriously fragile |
| xcodegen (YAML) | Separate Package.swift for the app | An app that IS a Package cannot link against another Package without a workspace; Xcode project (.xcodeproj) + local package reference is the standard pattern |
| `package` access modifier | `public` everywhere | `public` exposes everything to the Xcode app immediately; `package` is cleaner for Phase 18 and Phase 19 adds `public` only where needed |
| Same Package.swift | Separate Package.swift for DesignRulerCore | Same Package.swift is simpler — one `Package.resolved`, one build cache, fewer files |

**Installation:**
```bash
brew install xcodegen
```

---

## Architecture Patterns

### Recommended Project Structure

```
porto/
├── swift/
│   └── DesignRuler/                     # existing SPM package (updated)
│       ├── Package.swift                # updated: 2 targets
│       ├── Package.resolved             # unchanged
│       └── Sources/
│           ├── DesignRulerCore/         # NEW library target (23 files)
│           │   ├── AlignmentGuides/     # 5 files (NOT AlignmentGuides.swift)
│           │   ├── Cursor/
│           │   ├── Measure/             # 7 files (NOT Measure.swift)
│           │   ├── Permissions/
│           │   ├── Rendering/
│           │   └── Utilities/
│           └── RaycastBridge/           # NEW executable target (2 files)
│               ├── Measure.swift        # @raycast func inspect + Measure class
│               └── AlignmentGuides.swift # @raycast func alignmentGuides + AlignmentGuides class
└── App/                                 # NEW Xcode app project
    ├── project.yml                      # xcodegen spec (source of truth)
    ├── "Design Ruler.xcodeproj"/        # generated by xcodegen (committed)
    └── Sources/
        ├── AppDelegate.swift            # minimal stub
        └── Info.plist                   # LSUIElement=YES, bundle ID, etc.
```

### Pattern 1: Two Targets in One Package.swift (Raycast-compatible)

**What:** A library target (`DesignRulerCore`) and executable target (`DesignRuler`) coexist in the same `Package.swift`. Raycast only errors on multiple executable targets; library targets are ignored.

**When to use:** Always — this is the only structure that satisfies all three constraints: `ray build` passes, Xcode app links DesignRulerCore, and there is a single `Package.resolved`.

**Verified by:** Source inspection of Raycast's esbuild plugin (`@raycast/api/dist/utils/esbuild-plugins/swift-files.js`), which contains:
```javascript
for (let _ of $.targets || [])
  if (_.type === "executable") {
    if (D) throw new Error("expected one executable target but found more than one");
    D = _.name;
    _.path && (d = _.path);
  }
```
Library targets have `_.type === "regular"` in `swift package dump-package` output — they never enter this branch.

**Example Package.swift:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesignRuler",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesignRulerCore", targets: ["DesignRulerCore"]),
        // Executable product is auto-discovered; no explicit product entry needed
    ],
    dependencies: [
        .package(url: "https://github.com/raycast/extensions-swift-tools", from: "1.0.4"),
    ],
    targets: [
        .target(
            name: "DesignRulerCore",
            path: "Sources/DesignRulerCore"
        ),
        .executableTarget(
            name: "DesignRuler",
            dependencies: [
                "DesignRulerCore",
                .product(name: "RaycastSwiftMacros", package: "extensions-swift-tools"),
                .product(name: "RaycastSwiftPlugin", package: "extensions-swift-tools"),
                .product(name: "RaycastTypeScriptPlugin", package: "extensions-swift-tools"),
            ],
            path: "Sources/RaycastBridge"
        ),
    ]
)
```

### Pattern 2: `package` Access Modifier for Cross-Target Visibility

**What:** Swift 5.9+ `package` access modifier allows symbols in one target to be visible to other targets in the same SPM package, without exposing them to external consumers (like the Xcode app).

**When to use:** For all types and members in `DesignRulerCore` that the `DesignRuler` executable target uses. The Xcode app stub in Phase 18 does not call DesignRulerCore APIs, so `public` is not required until Phase 19.

**Example:**
```swift
// OverlayCoordinator.swift (in DesignRulerCore)
package protocol OverlayWindowProtocol: AnyObject {
    var targetScreen: NSScreen! { get }
    func showInitialState()
    func collapseHintBar()
    func deactivate()
}

package class OverlayCoordinator {
    package var windows: [NSWindow] = []
    package weak var activeWindow: NSWindow?
    package var firstMoveReceived = false

    package init() {}

    package func run(hideHintBar: Bool) { ... }
    package func captureAllScreens() -> [(screen: NSScreen, image: CGImage?)] { ... }
    package func createWindow(for screen: NSScreen, image: CGImage?, isCursorScreen: Bool, hideHintBar: Bool) -> NSWindow { ... }
    package func wireCallbacks(for window: NSWindow) { }
    package func activateWindow(_ window: NSWindow) { ... }
    package func resetCommandState() { }
    package func handleExit() { ... }
    package func handleFirstMove() { ... }
    package func setupSignalHandler() { ... }
    package func resetInactivityTimer() { ... }
}
```

**Note:** In `Measure.swift` and `AlignmentGuides.swift` (now in `Sources/RaycastBridge/`), add `import DesignRulerCore` because they are now in a different module.

### Pattern 3: xcodegen Project Spec for macOS Agent App

**What:** `project.yml` defines the Xcode project declaratively. The `.xcodeproj` is generated from it and committed.

**Example `App/project.yml`:**
```yaml
name: "Design Ruler"
options:
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

packages:
  DesignRuler:
    path: ../swift/DesignRuler

targets:
  "Design Ruler":
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - Sources
    dependencies:
      - package: DesignRuler
        product: DesignRulerCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: cv.haythem.designruler
        PRODUCT_NAME: "Design Ruler"
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        ARCHS: "$(ARCHS_STANDARD)"
        CODE_SIGN_STYLE: Automatic
      configs:
        Debug:
          CODE_SIGN_IDENTITY: "-"
    info:
      path: Sources/Info.plist
      properties:
        CFBundleName: "Design Ruler"
        CFBundleDisplayName: "Design Ruler"
        CFBundleVersion: "1"
        CFBundleShortVersionString: "1.0.0"
        LSUIElement: true
        NSHighResolutionCapable: true
        NSPrincipalClass: NSApplication
        NSApplicationSupportsSecureRestorableState: true
```

**Generate project:**
```bash
cd App && xcodegen generate
```

**No entitlements file** = App Sandbox disabled. Xcode defaults to no sandbox when no entitlements file is present for a non-App-Store app.

### Pattern 4: Minimal App Stub (Phase 18)

```swift
// App/Sources/AppDelegate.swift
import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Phase 18: Build system stub — features come in Phase 19+
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
```

### Anti-Patterns to Avoid

- **Two executable targets in Package.swift:** Raycast build fails with "expected one executable target but found more than one". Library targets are safe.
- **No `import DesignRulerCore` in bridge files:** Measure.swift and AlignmentGuides.swift will fail to compile after the module split.
- **Forgetting `package` access modifier:** Internal members of DesignRulerCore are invisible to the executable target. Every class, struct, enum, protocol, func, var, let, and init that crosses the module boundary needs `package`.
- **Mismatched `path:` in Package.swift:** If `path: "Sources/RaycastBridge"` doesn't match the physical directory, SPM build fails.
- **`products` entry missing for library:** Without `.library(name: "DesignRulerCore", targets: ["DesignRulerCore"])` in the `products` array, xcodegen cannot reference the product by name.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Xcode project file | Hand-edited project.pbxproj | xcodegen | pbxproj is binary-format-ish, fragile, causes constant merge conflicts |
| Package dump parsing | Custom script | `swift package dump-package` | SPM's canonical JSON output; already used by Raycast |
| Build verification | Custom CI script | `xcodebuild build -scheme "Design Ruler"` | Standard Xcode toolchain |

**Key insight:** The Xcode project format (`.xcodeproj`) is not designed for hand-editing. xcodegen is the industry standard for generating it from a clean YAML specification.

---

## Common Pitfalls

### Pitfall 1: Raycast Rejects Multiple Executable Targets
**What goes wrong:** Adding a second `executableTarget` to `Package.swift` causes Raycast's build plugin to throw "expected one executable target but found more than one" at `ray build` time — even if the second executable has nothing to do with Raycast.

**Why it happens:** The Raycast esbuild plugin (`swift-files.js`) runs `swift package dump-package`, iterates targets, counts `type === "executable"`, and errors on count > 1.

**How to avoid:** Only one `executableTarget` in the package. Use `.target()` (library) for `DesignRulerCore`. Library targets have `type === "regular"` in dump output and are ignored.

**Warning signs:** `ray build` errors before xcodebuild even runs.

### Pitfall 2: Access Modifiers Not Added to All Used Members
**What goes wrong:** The compiler errors on hundreds of symbols: `'SomeMember' is inaccessible due to 'internal' protection level`.

**Why it happens:** Swift modules have `internal` as the default access level. Splitting into two modules means `internal` in `DesignRulerCore` is not visible to the `DesignRuler` executable.

**How to avoid:** Add `package` to every type and every member of those types that is referenced from `Measure.swift` or `AlignmentGuides.swift`. The key types are: `OverlayCoordinator` (and all its properties/methods), `OverlayWindow`, `OverlayWindowProtocol`, `MeasureWindow`, `AlignmentGuidesWindow`, `EdgeDetector`, `CorrectionMode`, `GuideLineStyle`, `Direction`, `CursorManager`, `HintBarView`, `HintBarMode`, `PermissionChecker`, and all rendering/utility types used transitively.

**Warning signs:** Long list of "inaccessible due to 'internal' protection level" errors after adding the library target.

### Pitfall 3: Missing `import DesignRulerCore` in Bridge Files
**What goes wrong:** `Measure.swift` and `AlignmentGuides.swift` fail to compile with "use of undeclared type" errors for all DesignRulerCore types.

**Why it happens:** Before the split, all code was in one module. After the split, the bridge files must explicitly import their dependency.

**How to avoid:** Add `import DesignRulerCore` at the top of both `Sources/RaycastBridge/Measure.swift` and `Sources/RaycastBridge/AlignmentGuides.swift`.

### Pitfall 4: Stale `.raycast-swift-build` Cache
**What goes wrong:** `ray build` fails with confusing errors about missing symbols or wrong paths after restructuring.

**Why it happens:** The `.raycast-swift-build/` directory caches xcodebuild's derived data. After moving source files, the cache may have stale path references.

**How to avoid:** Delete `.raycast-swift-build/` before running `ray build` after any source restructure.

**Warning signs:** Build errors that reference old paths (`Sources/AlignmentGuides/`, `Sources/Measure/`) after restructuring.

### Pitfall 5: xcodegen Package Path Relative to project.yml
**What goes wrong:** xcodegen cannot find the package; fails with "invalid path" or similar.

**Why it happens:** `path:` in `project.yml` packages section is relative to `project.yml`'s location. If `project.yml` is at `App/project.yml` and the package is at `swift/DesignRuler/`, the correct path is `../swift/DesignRuler`.

**How to avoid:** Verify relative path before running xcodegen:
```bash
ls App/../swift/DesignRuler/Package.swift  # must exist
```

### Pitfall 6: Platform Target Still at macOS 13
**What goes wrong:** Builds succeed but deployment target is wrong for Phase 18 decision (macOS 14).

**Why it happens:** Current `Package.swift` specifies `.macOS(.v13)`. The decision locked macOS 14 as minimum.

**How to avoid:** Change `platforms: [.macOS(.v13)]` to `platforms: [.macOS(.v14)]` in `Package.swift`.

---

## Code Examples

Verified patterns from analysis:

### How Raycast Resolves the `swift:` Import
```javascript
// Source: @raycast/api/dist/utils/esbuild-plugins/swift-files.js
// The swift: import resolves to a directory containing Package.swift
// Then: swift package dump-package is run to parse targets
// Only executable targets are counted; library targets are ignored
for (let _ of $.targets || [])
  if (_.type === "executable") {
    if (D) throw new Error("expected one executable target but found more than one");
    D = _.name;       // D = executable target name
    _.path && (d = _.path);  // d = sources directory (falls back to "Sources")
  }

// Then xcodebuild is called with scheme = package name:
let j = `xcodebuild build -skipMacroValidation -skipPackagePluginValidation \
  -configuration ${n} -scheme ${f} \
  -destination "generic/platform=macOS,name=Any Mac" \
  -derivedDataPath ${p}`;
```

### Package.swift After Restructure
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesignRuler",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesignRulerCore", targets: ["DesignRulerCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/raycast/extensions-swift-tools", from: "1.0.4"),
    ],
    targets: [
        .target(
            name: "DesignRulerCore",
            path: "Sources/DesignRulerCore"
        ),
        .executableTarget(
            name: "DesignRuler",
            dependencies: [
                "DesignRulerCore",
                .product(name: "RaycastSwiftMacros", package: "extensions-swift-tools"),
                .product(name: "RaycastSwiftPlugin", package: "extensions-swift-tools"),
                .product(name: "RaycastTypeScriptPlugin", package: "extensions-swift-tools"),
            ],
            path: "Sources/RaycastBridge"
        ),
    ]
)
```

### File-by-File Movement Map
```
MOVE TO Sources/DesignRulerCore/ (keep subdirectory structure):
  Sources/AlignmentGuides/AlignmentGuidesWindow.swift
  Sources/AlignmentGuides/ColorCircleIndicator.swift
  Sources/AlignmentGuides/GuideLine.swift
  Sources/AlignmentGuides/GuideLineManager.swift
  Sources/AlignmentGuides/GuideLineStyle.swift
  Sources/Cursor/CursorManager.swift
  Sources/Measure/ColorMap.swift
  Sources/Measure/CrosshairView.swift
  Sources/Measure/DirectionalEdges.swift
  Sources/Measure/EdgeDetector.swift
  Sources/Measure/MeasureWindow.swift
  Sources/Measure/SelectionManager.swift
  Sources/Measure/SelectionOverlay.swift
  Sources/Permissions/PermissionChecker.swift
  Sources/Rendering/HintBarContent.swift
  Sources/Rendering/HintBarView.swift
  Sources/Rendering/PillRenderer.swift
  Sources/Utilities/CoordinateConverter.swift
  Sources/Utilities/DesignTokens.swift
  Sources/Utilities/OverlayCoordinator.swift
  Sources/Utilities/OverlayWindow.swift
  Sources/Utilities/ScreenCapture.swift
  Sources/Utilities/TransactionHelpers.swift

MOVE TO Sources/RaycastBridge/:
  Sources/AlignmentGuides/AlignmentGuides.swift
  Sources/Measure/Measure.swift
```

### Access Modifier Pattern (DesignRulerCore files)
```swift
// Before (internal by default):
class OverlayCoordinator {
    var windows: [NSWindow] = []
    func run(hideHintBar: Bool) { ... }
}

// After (package access):
package class OverlayCoordinator {
    package var windows: [NSWindow] = []
    package func run(hideHintBar: Bool) { ... }
}
```

### Bridge Files After Restructure (add import)
```swift
// Sources/RaycastBridge/Measure.swift
import AppKit
import DesignRulerCore          // ADD THIS
import RaycastSwiftMacros

@raycast func inspect(hideHintBar: Bool, corrections: String) {
    Measure.shared.run(hideHintBar: hideHintBar, corrections: corrections)
}

final class Measure: OverlayCoordinator {  // OverlayCoordinator now from DesignRulerCore
    // ... unchanged
}
```

### Verify ray build Compatibility
```bash
# From repo root
cd porto
ray build --environment dist

# Or just check it compiles:
cd porto/swift/DesignRuler
swift package dump-package | python3 -c "
import json, sys
d = json.load(sys.stdin)
exes = [t for t in d.get('targets', []) if t.get('type') == 'executable']
print(f'Executable targets: {len(exes)} -> {[t[\"name\"] for t in exes]}')
print('Raycast: OK' if len(exes) == 1 else 'Raycast: WILL FAIL')
"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| `swift package generate-xcodeproj` | xcodegen | Deprecated ~Xcode 12 | generate-xcodeproj no longer maintained; xcodegen is the community standard |
| `public` for cross-package APIs | `package` modifier | Swift 5.9 (2023) | Safer than `public`; hides APIs from external consumers while sharing within package |
| Single flat executableTarget | library + executable in one package | Always supported | No tools-version change needed; SPM has always allowed multiple target types |

**Deprecated/outdated:**
- `swift package generate-xcodeproj`: Removed in modern Xcode; do not use.

---

## Open Questions

1. **Should `package` vs `public` be decided per-type or all-at-once?**
   - What we know: Phase 18 needs `package` for cross-target compilation; Phase 19+ needs `public` for the app's new coordinator subclasses.
   - What's unclear: Whether it's better to add `public` to everything now vs incrementally.
   - Recommendation: Use `package` everywhere in Phase 18. The incremental `public` additions in Phase 19+ are mechanical and localized to the types the app needs.

2. **Should the generated `.xcodeproj` be committed to git?**
   - What we know: xcodegen can regenerate it; project.yml is the canonical source.
   - What's unclear: Team preference.
   - Recommendation: Commit it for convenience — engineers can open the project immediately without installing xcodegen. Add a `.gitattributes` entry to treat `.xcodeproj` as binary-ish to reduce diff noise.

3. **Where exactly does the App/ directory live in the repo?**
   - What we know: Claude's discretion per CONTEXT.md.
   - Recommendation: `App/` at the repository root (alongside `swift/`, `src/`). Clean separation, matches the mental model of "Raycast extension" vs "standalone app".

---

## Sources

### Primary (HIGH confidence)
- Direct source inspection: `/Users/haythem/.nvm/versions/node/v22.13.1/lib/node_modules/@raycast/api/dist/utils/esbuild-plugins/swift-files.js` — verified Raycast's exact target-counting logic and xcodebuild command
- `swift package dump-package` on the live project — verified `type: "executable"` for current target
- `Package.swift` at `swift/DesignRuler/Package.swift` — verified current structure
- All 25 Swift source files — verified which files contain `@raycast`, which are bridge vs core

### Secondary (MEDIUM confidence)
- xcodegen 2.44.1 docs (`https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/Docs/ProjectSpec.md`) — verified local package and `product:` key syntax
- `brew info xcodegen` — confirmed version 2.44.1, Xcode 15.3+ requirement
- Raycast extensions-swift-tools README (fetched) — confirmed plugin structure, no constraint on library targets

### Tertiary (LOW confidence)
- WebSearch results on Swift `package` access modifier — LOW confidence; verified against Swift 5.9 docs conceptually but not tested against this specific Package.swift structure

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — verified Raycast source code directly; xcodegen docs fetched
- Architecture: HIGH — Raycast's constraint confirmed via source inspection; SPM patterns are well-established
- Pitfalls: HIGH — derived from direct code analysis (Raycast plugin logic, SPM behavior)

**Research date:** 2026-02-18
**Valid until:** 2026-09-18 (stable tooling; xcodegen API is stable)
