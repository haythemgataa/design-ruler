# Design Ruler

## What This Is

A macOS pixel inspector launched from Raycast. Two commands: (1) **Design Ruler** — crosshair with edge detection, W×H dimensions, arrow-key skip, drag-to-snap selections. (2) **Alignment Guides** — place vertical/horizontal guide lines to verify element alignment, color cycling, position pills. Both use fullscreen frozen overlays with per-screen capture, GPU-composited CAShapeLayer rendering, and liquid glass hint bars.

## Core Value

Instant, accurate pixel inspection of anything on screen — zero friction from Raycast invoke to dimension readout.

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

### Active (v1.2 Alignment Guides)

- REQ-AG-01 through REQ-AG-16 — see `.planning/REQUIREMENTS.md`

### Out of Scope

- Copy dimensions to clipboard — this is an inspection tool, not a measurement export tool
- Accessibility (AX) based detection — adds complexity with minimal benefit over image-based
- Snap-to-edge cursor behavior — disorienting, arrow-key skipping is better
- Partial snap (snap 3 sides when 4th fails) — hand-drawn edge won't be pixel-accurate
- Edge detection sensitivity preference — tolerance=1 works well for most designs, adding UI complexity not justified
- Tap-to-clear discoverability hint — users will discover it naturally

## Context

- Raycast extension: TypeScript thin wrapper calls Swift via `@raycast` macro bridge
- Raycast only deploys the Swift binary — no `.bundle` directories, no `Bundle.module`
- macOS 13+ minimum, Swift 5.9+, AppKit + CoreGraphics + QuartzCore + SwiftUI
- CGWindowListCreateImage has a cold-start penalty on macOS 26; mitigated by 1x1 warmup capture
- Coordinate system duality: AppKit (bottom-left origin) for UI, CG (top-left origin) for pixel scanning
- Shipped v1.1 Hint Bar Redesign with 8,267 LOC Swift across 8 phases
- v1.2 Alignment Guides: separate command, separate classes, reuses shared utilities
- Existing codebase map at `.planning/codebase/` (7 documents, mapped 2026-02-13)

## Constraints

- **No Bundle.module**: Raycast deploys only the Swift binary — embed everything inline
- **No SVG via NSImage**: Filter effects cause 80%+ CPU — draw natively with NSBezierPath
- **No NSCursor.set()**: Gets overridden by window cursor rect management — use resetCursorRects()
- **Capture before window**: Must capture screen before creating overlay to avoid self-interference
- **Performance**: CPU must stay <5% during mouse movement — CALayer-only updates, no draw() overrides

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Image-based edge detection over AX | Simpler, works on any visual content, no accessibility API complexity | ✓ Good |
| Single EdgeDetector class (capture + scan + skip) | Avoids wrapper indirection, keeps state co-located | ✓ Good |
| CAShapeLayer with difference blend for crosshair | GPU composited, visible on any background | ✓ Good |
| Smart border correction as default | Automatically absorbs 1px CSS borders using 4px grid heuristic | ✓ Good |
| Per-screen window creation (not lazy) | Simpler coordination, all screens ready immediately | — Pending |
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

| Separate AlignmentGuides classes (not extending inspect) | Inspect code too coupled to edge detection; clean separation avoids refactor | — Pending |

---
*Last updated: 2026-02-16 — v1.2 Alignment Guides milestone started*
