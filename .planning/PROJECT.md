# Design Ruler

## What This Is

A macOS pixel inspector available as both a Raycast extension and a standalone menu bar app. Two commands: (1) **Measure** — crosshair with edge detection, W×H dimensions, arrow-key skip, drag-to-snap selections. (2) **Alignment Guides** — place vertical/horizontal guide lines to verify element alignment, color cycling, hover-to-remove, position pills. Both use fullscreen frozen overlays with per-screen multi-monitor capture, GPU-composited CAShapeLayer rendering, and liquid glass hint bars.

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

### Active

## Current Milestone: v2.0 Standalone App

**Goal:** Make Design Ruler available as a standalone macOS menu bar app with global hotkeys and settings, while keeping full Raycast extension support.

**Target features:**
- Standalone macOS menu bar app with dropdown for both commands
- Configurable global keyboard shortcuts for Measure and Alignment Guides
- Settings window (hideHintBar, corrections, hotkey bindings, launch at login)
- Coexistence detection with Raycast extension (recommend keeping one)
- DMG distribution via GitHub releases
- Identical overlay behavior to Raycast version

### Out of Scope

- Copy dimensions to clipboard — this is an inspection tool, not a measurement export tool
- Accessibility (AX) based detection — adds complexity with minimal benefit over image-based
- Snap-to-edge cursor behavior — disorienting, arrow-key skipping is better
- Partial snap (snap 3 sides when 4th fails) — hand-drawn edge won't be pixel-accurate
- Edge detection sensitivity preference — tolerance=1 works well for most designs, adding UI complexity not justified
- Tap-to-clear discoverability hint — users will discover it naturally

## Context

- Raycast extension: TypeScript thin wrapper calls Swift via `@raycast` macro bridge
- Standalone app: native macOS menu bar app sharing same Swift overlay/detection code
- Raycast only deploys the Swift binary — no `.bundle` directories, no `Bundle.module`
- macOS 13+ minimum, Swift 5.9+, AppKit + CoreGraphics + QuartzCore + SwiftUI
- CGWindowListCreateImage has a cold-start penalty on macOS 26; mitigated by 1x1 warmup capture
- Coordinate system duality: AppKit (bottom-left origin) for UI, CG (top-left origin) for pixel scanning
- Shipped v1.3 Code Unification with ~3,300 LOC Swift across 17 phases (4 milestones)
- Two commands: `design-ruler` (inspect) and `alignment-guides` (guides)
- Shared base classes: OverlayCoordinator (lifecycle), OverlayWindow (window setup)
- Shared utilities: PillRenderer, DesignTokens, ScreenCapture, CoordinateConverter, CursorManager, PermissionChecker, HintBarView
- Codebase map at `.planning/codebase/` (7 documents, mapped 2026-02-13)

## Constraints

- **No Bundle.module**: Raycast deploys only the Swift binary — embed everything inline
- **No SVG via NSImage**: Filter effects cause 80%+ CPU — draw natively with NSBezierPath
- **No NSCursor push/pop or resetCursorRects**: Pushed cursors get overridden on borderless windows — use `NSCursor.set()` via CursorManager + `cursorUpdate(with:)` override
- **Capture before window**: Must capture screen before creating overlay to avoid self-interference
- **Performance**: CPU must stay <5% during mouse movement — CALayer-only updates, no draw() overrides

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

---
*Last updated: 2026-02-17 after v2.0 milestone started*
