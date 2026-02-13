# Design Ruler

## What This Is

A macOS pixel inspector launched from Raycast. The user invokes it, a fullscreen overlay appears (frozen screenshot), and a crosshair follows the cursor showing detected edges in 4 directions with live W×H dimensions. Arrow keys skip past edges. Users can drag to select and snap regions. Multi-monitor support with per-screen capture.

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

### Active

- [ ] Remove debug fputs statements from production code
- [ ] Selection snap failure shake animation (horizontal shake before fade-out)
- [ ] Selection overlay pill — clamp to screen bounds
- [ ] Hint bar toggle: backspace dismisses + brief "Press ? for help" + `?` re-enables
- [ ] Process timeout safety valve (~10 min max lifetime)
- [ ] Cursor state machine hardening (centralize push/pop/hide/unhide)

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
- macOS 13+ minimum, Swift 5.9+, AppKit + CoreGraphics + QuartzCore
- CGWindowListCreateImage has a cold-start penalty on macOS 26; mitigated by 1x1 warmup capture
- Coordinate system duality: AppKit (bottom-left origin) for UI, CG (top-left origin) for pixel scanning
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

---
*Last updated: 2026-02-13 after initialization*
