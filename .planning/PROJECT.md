# Design Ruler

## What This Is

A macOS pixel inspector available as both a Raycast extension and a standalone menu bar app with configurable global hotkeys and auto-updates. Two commands: (1) **Measure** — crosshair with edge detection, W×H dimensions, arrow-key skip, drag-to-snap selections. (2) **Alignment Guides** — place vertical/horizontal guide lines to verify element alignment, color cycling, hover-to-remove, position pills. Both use fullscreen frozen overlays with per-screen multi-monitor capture, GPU-composited CAShapeLayer rendering, and liquid glass hint bars. Distributed as a code-signed, notarized DMG via GitHub Releases.

## Core Value

Instant, accurate pixel inspection of anything on screen — zero friction from invoke to dimension readout, whether launched from Raycast or a global hotkey.

## Requirements

### Validated

- ✓ Fullscreen frozen overlay with per-screen capture before window creation — existing
- ✓ Crosshair with edge detection in 4 cardinal directions — existing
- ✓ Live W×H dimension pill with flip animation near screen edges — existing
- ✓ Arrow key edge skipping + Shift+Arrow to un-skip — existing
- ✓ Smart border correction (absorb 1px CSS borders) with 3 correction modes — existing
- ✓ Drag-to-select with snap-to-edges — existing
- ✓ Selection hover + click-to-remove — existing
- ✓ Hint bar with keyboard shortcut hints and auto-reposition (bottom ↔ top) — existing
- ✓ Multi-monitor support (one window per screen, cursor-follows activation) — existing
- ✓ GPU-composited rendering via CAShapeLayer (no draw() override, low CPU) — existing
- ✓ System crosshair cursor on launch, hidden after first mouse move — existing
- ✓ Clean production builds with zero stderr debug output — v1.0
- ✓ Snap failure shake animation (macOS login rejection idiom) — v1.0
- ✓ Selection pill clamped to screen bounds with shadow clearance — v1.0
- ✓ ~~Help toggle: backspace dismiss, "?" re-enable, session persistence~~ — v1.0 (replaced in v1.1)
- ✓ 10-minute inactivity watchdog preventing zombie processes — v1.0
- ✓ Centralized CursorManager with SIGTERM handler — v1.0
- ✓ Hint bar redesign with liquid glass background and launch-to-collapse animation — v1.1
- ✓ New keycap sizes and layout (arrows 26x11, shift 40x25, esc 32x25) — v1.1
- ✓ ESC keycap in main bar with reddish tint (dark/light mode aware) — v1.1
- ✓ Bar split animation: full text → two keycap-only bars (arrows+shift left, esc right) — v1.1
- ✓ Liquid glass on macOS 26+, vibrancy fallback on older versions — v1.1
- ✓ Remove backspace-dismiss / ? re-enable system (preference-only hide) — v1.1
- ✓ Alignment guides: preview line with Tab direction toggle — v1.2
- ✓ Click placement with position pills (X/Y coordinates) — v1.2
- ✓ Spacebar color cycling (dynamic, red, green, orange, blue) with arc indicator — v1.2
- ✓ Hover-to-remove with 5px hit testing, red+dashed feedback, shrink animation — v1.2
- ✓ Pointing hand cursor on hover, resize cursor matching direction — v1.2
- ✓ Multi-monitor alignment guides with global color sync — v1.2
- ✓ HintBarMode system supporting both inspect and alignment guides keycaps — v1.2

- ✓ Unified pill rendering (PillRenderer with 3 factory methods) across CrosshairView, GuideLine, SelectionOverlay — v1.3
- ✓ Centralized design tokens (DesignTokens.swift: colors, radii, durations, BlendMode) — v1.3
- ✓ CATransaction.instant{} and .animated{} helpers eliminating 37+ boilerplate blocks — v1.3
- ✓ OverlayCoordinator base class for shared lifecycle (warmup, permissions, signal handler, exit) — v1.3
- ✓ OverlayWindow base class for shared NSWindow config, tracking, throttle, firstMove — v1.3
- ✓ CursorManager expanded to 6 states with resize cursors, replacing parallel cursor system — v1.3
- ✓ ScreenCapture utility and CoordinateConverter rect methods — v1.3
- ✓ HintBarContent deduplication via shared HintBarTextStyle — v1.3

- ✓ DesignRulerCore SPM library shared by Raycast extension and standalone Xcode app — v2.0
- ✓ RunMode enum gating app.run()/NSApp.terminate() for standalone lifecycle — v2.0
- ✓ Session guards (isSessionActive + anySessionActive) preventing overlapping invocations — v2.0
- ✓ CursorManager.restore() at start of every session (singleton state leak prevention) — v2.0
- ✓ NSStatusItem menu bar icon with Measure/Guides/Settings/Quit dropdown — v2.0
- ✓ Menu bar icon active state (ruler.fill / ruler) with anySessionActive guard — v2.0
- ✓ onSessionEnd callback decoupling MenuBarController from coordinator types — v2.0
- ✓ SwiftUI Settings window (General, Measure, Shortcuts, About) with AppPreferences singleton — v2.0
- ✓ Launch at Login via SMAppService.mainApp with .onAppear re-sync — v2.0
- ✓ Sparkle 2 auto-update integration with EdDSA signature verification — v2.0
- ✓ Configurable global hotkeys via KeyboardShortcuts 2.4.0 (Carbon Event Manager) — v2.0
- ✓ Session-aware hotkey dispatch: toggle-off, cross-switch, normal launch — v2.0
- ✓ Shortcut recorder UI with inline conflict detection — v2.0
- ✓ Menu bar shortcut symbol display via NSMenuDelegate refresh — v2.0
- ✓ Developer ID code signing with Hardened Runtime — v2.0
- ✓ Notarization via notarytool for Gatekeeper approval — v2.0
- ✓ Branded DMG installer with /Applications alias — v2.0
- ✓ Dual GitHub Actions CI: build-release (tag-push) + update-appcast (release-publish) — v2.0

### Active

(No active requirements — planning next milestone)

### Out of Scope

- Copy dimensions to clipboard — inspection tool, not measurement export
- Accessibility (AX) based detection — complexity with minimal benefit over image-based
- Snap-to-edge cursor behavior — disorienting, arrow-key skipping is better
- Partial snap (snap 3 sides when 4th fails) — hand-drawn edge won't be pixel-accurate
- Edge detection sensitivity preference — tolerance=1 works well, UI complexity not justified
- App Store distribution — Sandbox blocks CGEventTap and CGWindowListCreateImage
- Multiple simultaneous overlay sessions — one session at a time matches Raycast behavior

## Context

- Shipped v2.0 Standalone App with ~5,562 LOC Swift + 73 LOC TypeScript across 23 phases (5 milestones)
- Dual distribution: Raycast extension (TypeScript thin wrapper → Swift via `@raycast` macro) + standalone menu bar app (DMG)
- DesignRulerCore SPM library contains all shared overlay/detection/rendering code
- macOS 14+ minimum, Swift 5.9+, AppKit + CoreGraphics + QuartzCore + SwiftUI + KeyboardShortcuts + Sparkle
- Two commands: `design-ruler` (inspect) and `alignment-guides` (guides)
- Standalone app: LSUIElement menu bar agent, global hotkeys via Carbon Event Manager, Sparkle auto-updates
- CI/CD: GitHub Actions dual-workflow (build-release on tag-push, update-appcast on release-publish)
- CGWindowListCreateImage has a cold-start penalty on macOS 26; mitigated by 1x1 warmup capture
- Coordinate system duality: AppKit (bottom-left origin) for UI, CG (top-left origin) for pixel scanning

## Constraints

- **No Bundle.module**: Raycast deploys only the Swift binary — embed everything inline
- **No SVG via NSImage**: Filter effects cause 80%+ CPU — draw natively with NSBezierPath
- **No NSCursor push/pop or resetCursorRects**: Pushed cursors get overridden on borderless windows — use `NSCursor.set()` via CursorManager + `cursorUpdate(with:)` override
- **Capture before window**: Must capture screen before creating overlay to avoid self-interference
- **Performance**: CPU must stay <5% during mouse movement — CALayer-only updates, no draw() overrides
- **No App Sandbox**: CGEventTap + CGWindowListCreateImage incompatible with sandbox
- **No App Store**: Sandbox requirement blocks core functionality — DMG distribution only

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Image-based edge detection over AX | Simpler, works on any visual content, no accessibility API complexity | ✓ Good |
| Single EdgeDetector class (capture + scan + skip) | Avoids wrapper indirection, keeps state co-located | ✓ Good |
| CAShapeLayer with difference blend for crosshair | GPU composited, visible on any background | ✓ Good |
| Smart border correction as default | Automatically absorbs 1px CSS borders using 4px grid heuristic | ✓ Good |
| Per-screen window creation (not lazy) | Simpler coordination, all screens ready immediately | ✓ Good |
| Removed fputs entirely (not #if DEBUG gated) | Raycast always builds debug config, so the flag provides zero protection | ✓ Good |
| Singleton CursorManager.shared | NSCursor is inherently global state; matches existing Ruler.shared pattern | ✓ Good |
| State enum for cursor (4 cases) | Prevents impossible state combinations vs scattered boolean flags | ✓ Good |
| Additive CAKeyframeAnimation for shake | Same animation works on all layers regardless of position; no model layer changes | ✓ Good |
| Shadow-aware 4px clampMargin | Uniform margin simpler than per-edge computation; sufficient for shadowRadius=3 + offset=1 | ✓ Good |
| NSGlassEffectView on macOS 26+ with NSVisualEffectView fallback | Native glass material on Tahoe, graceful degradation on older systems | ✓ Good |
| Screenshot brightness sampling for adaptive glass tint | Adapts to frozen screenshot content, not system color scheme | ✓ Good |
| SwiftUI GlassEffectContainer morph (macOS 26+) | Native liquid glass split animation; two-layer rendering hack enables smooth keycap sliding + glass split | ✓ Good |
| 3-second minimum expanded display | Ensures users can read hint text before collapse on first mouse move | ✓ Good |
| NSAnimationContext crossfade fallback (pre-macOS 26) | Simple, reliable animation without SwiftUI glass APIs | ✓ Good |
| Separate AlignmentGuides classes (not extending inspect) | Inspect code too coupled to edge detection; clean separation avoids refactor | ✓ Good — v1.3 extracted shared OverlayCoordinator + OverlayWindow base while keeping command-specific logic separate |
| 5px hover threshold for guide line removal | Comfortable selection without false positives; perpendicular distance calculation | ✓ Good |
| Per-line color retention | New lines use current style; existing placed lines keep their original color | ✓ Good |
| Global color state in AlignmentGuides singleton | Synced to windows on activation via callbacks; consistent across monitors | ✓ Good |
| Arc-based color indicator (108-degree span) | Comfortable visual spread without overlap; screen edge clamping flips direction | ✓ Good |
| HintBarMode enum for dual-command support | Single HintBarView class serves both inspect and alignment guides with mode-specific content | ✓ Good |
| Composite tab keycap (arrow+pipe) | ⇥ glyph unsupported in SF Pro Rounded; composite renders correctly | ✓ Good |
| Class-based OverlayCoordinator (not protocol) | Shared stored state (windows, activeWindow, timers) needs class semantics; subclass overrides for hooks | ✓ Good |
| OverlayWindowProtocol for type-safe window access | Coordinator base calls showInitialState/collapseHintBar/deactivate without knowing concrete types | ✓ Good |
| PillRenderer factory pattern (returns structs) | Caller receives fully-configured layer hierarchy, only sets position/content; no duplicated setup | ✓ Good |
| Static configureOverlay() instead of init override | NSWindow init is complex; static method called after init is simpler and more explicit | ✓ Good |
| CursorManager 6-state machine (expanded from 4) | Replaces AlignmentGuidesWindow's parallel cursor system; single authority for all cursor transitions | ✓ Good |
| HintBarTextStyle returns Text (not some View) | Satisfies both direct Text and View usage sites in SwiftUI content structs | ✓ Good |
| DesignRulerCore as open-class SPM library | Cross-module subclassing from both Raycast bridge and standalone app targets | ✓ Good |
| RunMode enum (.raycast / .standalone) on OverlayCoordinator | ~15-line change gates app.run() and NSApp.terminate() without rewrite | ✓ Good |
| MenuBarController callbacks (no coordinator imports) | Decoupled architecture — AppDelegate wires onMeasure/onAlignmentGuides/onSessionEnd | ✓ Good |
| AppPreferences computed properties over UserDefaults | Cross-context access from AppKit and SwiftUI; no @AppStorage limitations | ✓ Good |
| SMAppService.mainApp for Launch at Login | No helper bundle needed; .onAppear re-sync prevents desync with System Settings | ✓ Good |
| KeyboardShortcuts 2.4.0 (Carbon Event Manager) | No Accessibility permission for registration; onKeyUp prevents key-repeat re-triggering | ✓ Good |
| Session-aware hotkey dispatch (toggle/cross-switch/launch) | DispatchQueue.main.async between cross-command exit and relaunch for autorelease pool drainage | ✓ Good |
| Sparkle 2 with EdDSA verification | Industry-standard macOS auto-update; deferred startup until real keys configured | ✓ Good |
| Dual CI workflows (build-release + update-appcast) | Separation of concerns: tag-push builds DMG, release-publish generates appcast | ✓ Good |
| Empty entitlements (Hardened Runtime only) | CGWindowListCreateImage/CGEventTap governed by TCC, not entitlements | ✓ Good |
| LSUIElement = YES | Menu bar agent — no Dock icon, no Cmd+Tab entry | ✓ Good |

---
*Last updated: 2026-02-20 after v2.0 milestone completion*
