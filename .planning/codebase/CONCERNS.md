# Codebase Concerns

**Analysis Date:** 2026-02-13

## Debug Statements in Production Code

**Debug fputs() calls left in shipping code:**
- Issue: Multiple `fputs("[DEBUG]...")` calls to stderr are active in production builds
- Files:
  - `swift/Ruler/Sources/RulerWindow.swift` (lines 226, 252, 272, 281)
  - `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` (lines 36, 75)
- Impact: Pollutes stderr with internal diagnostic output, may confuse users or create noise in logs
- Fix approach: Remove or gate these behind a debug-only flag that's disabled in release builds. Consider using `#DEBUG` compiler flag or environment-based logging instead.

## Stale Drag State Recovery (Fragile)

**Drag state can get stuck if system steals mouseUp:**
- Issue: `RulerWindow.mouseDown()` includes recovery logic at line 225 that resets `isDragging` if it's unexpectedly true. This indicates the state machine is fragile and can get out of sync with OS events.
- Files: `swift/Ruler/Sources/RulerWindow.swift` (lines 223-230)
- Why fragile: If the system steals the mouseUp event (e.g., during Mission Control, Spotlight, or system gesture), `isDragging` stays true and subsequent clicks fail silently until reset. The recovery code masks the root cause rather than preventing it.
- Safe modification: Events should be routed through `sendEvent(_:)` override (line 167), which already intercepts all mouse events. Verify that mouseUp is never dropped or missed.
- Test coverage: Need tests for system gesture interruption and event cancellation scenarios.

## Coordinate System Conversion Dependency

**Multiple coordinate system conversions create subtle bugs:**
- Issue: AppKit ↔ CG coordinate conversions happen in multiple places with manual y-flip calculations
- Files:
  - `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` (lines 16-40 in `capture()`, lines 198-204 in `snapSelection()`)
  - `swift/Ruler/Sources/Utilities/CoordinateConverter.swift` (lines 6-14)
  - `swift/Ruler/Sources/RulerWindow.swift` (lines 188-192, 241-245, 291-294)
- Impact: Any screen rotation, multi-monitor setup change, or future display API upgrade could cause off-by-one errors in edge detection
- Improvement path: Create a centralized coordinate converter that handles all transformations. Reduce manual y-flip calculations. Add unit tests that verify AppKit→CG→AppKit round-trips preserve original coordinates.

## Per-Direction Edge Skipping Without Persistence

**Skip counts reset on every mouse move, no way to retry an edge:**
- Issue: `EdgeDetector.onMouseMoved()` at line 70 resets `skipCounts` to zero on every mouse event. This is correct for the crosshair mode, but means users cannot skip the same edge multiple times without mouse movement.
- Files: `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` (line 70)
- Impact: If an edge is detected at a boundary pixel and the user wants to skip it twice, they must move the mouse, then press arrow again. This is awkward but not a blocker.
- Workaround: Current behavior is actually consistent with the design (arrow keys skip from cursor position, not from last detection). Document this as expected behavior.

## Smart Edge Correction Algorithm Untested

**Smart mode's 4-combo grid-alignment logic has no unit test coverage:**
- Issue: `EdgeDetector.smartEdges()` (lines 101-132) tries all 4 combinations of absorbed/normal edges per axis and picks the first combo whose dimension lands on a 4px grid. This heuristic is clever but has no test coverage.
- Files: `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` (lines 101-167)
- Risk: If the grid-snapping logic fails, it silently falls back to the "both absorbed" option (line 166). Users may see unexpected measurements without knowing why.
- Recommendations:
  - Add unit tests with sample edge detection scenarios (1px borders, 2px borders, subpixel antialiasing)
  - Log which combo was selected for debugging
  - Add diagnostics to help users understand why a particular edge was chosen

## Memory Pressure from Retained CGImage Buffers

**Full-screen CGImage capture at bestResolution can be memory-heavy:**
- Issue: `EdgeDetector.capture()` (line 29) captures full screen at best resolution (2x on Retina = 4x pixels), then `applyCapture()` (line 46) allocates a [UInt8] pixel buffer of size `width * height * 4`
- Files: `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` (lines 16-65)
- Capacity: On a 5K display (5120×2880 pixels), this buffer is 5120 × 2880 × 4 = ~57 MB per screen. With multi-monitor, multiple captures exist simultaneously.
- Impact: No observed issue on current hardware, but extended sessions with many monitors could pressure memory. CGImage itself is also retained in `ColorMap`.
- Scaling path: For future 8K displays, consider:
  - Lazy tile-based scanning instead of full capture
  - Release capture after edge skipping is done (currently held for entire session)
  - Cache only the active screen's capture if multi-monitor becomes a bottleneck

## Missing Nil Checks in Optional Chains

**Several edge detection calls assume edges are always returned:**
- Issue: `RulerWindow.keyDown()` (lines 314, 318, 322, 326) calls `edgeDetector.incrementSkip()` / `decrementSkip()` which can return nil if `lastCursorPosition` is nil, but the optional is not checked before updating the crosshair.
- Files: `swift/Ruler/Sources/RulerWindow.swift` (lines 314-326)
- Pattern: `if let edges { crosshairView.update(...) }` — safely guards the nil case, so this is actually OK.
- Verification: Code is correct as-is. The guard pattern works properly.

## Selection Overlay Snap Failure Silent on All Sides

**If snap fails on one or more sides, entire selection is discarded:**
- Issue: `SelectionManager.endDrag()` (lines 37-60) calls `edgeDetector.snapSelection()` which returns nil if edges aren't found on ALL 4 sides (see `ColorMap.scanInward()` line 235-236). If snap fails, the selection is removed without user feedback.
- Files:
  - `swift/Ruler/Sources/Rendering/SelectionManager.swift` (lines 50-58)
  - `swift/Ruler/Sources/EdgeDetection/ColorMap.swift` (lines 234-236)
- Impact: Users see a selection get drawn, then disappear silently when they release the mouse. No indication of why it failed (e.g., insufficient samples, no edges detected).
- Recommendations:
  - Show a visual feedback when snap fails (flash, bounce, or different animation)
  - Log which sides failed to snap for debugging
  - Consider partial snapping (e.g., snap 3 sides if 4th is not found)

## Color Comparison Tolerance Hardcoded at 1

**Edge detection tolerance is not user-configurable and only supports tolerance = 1:**
- Issue: All `ColorMap.scan()` calls use `tolerance: 1` hardcoded (see `EdgeDetector` lines 85, 90, 102, 106). The `tolerance` parameter exists but is never varied.
- Files:
  - `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` (lines 85-106)
  - `swift/Ruler/Sources/EdgeDetection/ColorMap.swift` (lines 19-50)
- Impact: Cannot adjust sensitivity for high-contrast vs. low-contrast screenshots. Tolerance of 1 works well for most designs but fails on noisy backgrounds, gradients, or antialiased text.
- Fix approach: Add user preference for "Edge Detection Sensitivity" (low=3, medium=1, high=0) and pass it through to ColorMap.scan(). Test on various UI types before shipping.

## Stabilization Tolerance Hardcoded at 3

**Edge stabilization logic uses hardcoded tolerance values with no explanation:**
- Issue: `ColorMap.scanDirection()` (line 60) uses `stabilizationTolerance = 3` as a magic number. The stabilization algorithm is correct per the blueprint (3 consecutive stable pixels) but the tolerance is never documented or justified.
- Files: `swift/Ruler/Sources/EdgeDetection/ColorMap.swift` (lines 54-174)
- Impact: If the tolerance is too loose, antialiased edges trigger false positives. If too tight, color noise prevents stabilization. Current value works but is unexplained.
- Recommendations: Add inline comment explaining why 3 pixels at tolerance 3 represents a "stable color region". Consider making this a user-adjustable parameter if sensitivity becomes a frequent issue.

## System Crosshair Cursor Not Always Hidden After First Move

**Cursor hiding logic is split across multiple calls with potential race conditions:**
- Issue: `CrosshairView.hideSystemCrosshair()` (line 114) calls `NSCursor.hide()`, but the cursor stack is also manipulated in `RulerWindow` for selection hover (lines 201-202, 209-210, 237-238, 258-259, 265-266, 301-302). If events race, cursor state can be misaligned.
- Files: `swift/Ruler/Sources/Rendering/CrosshairView.swift` (lines 113-118), `swift/Ruler/Sources/RulerWindow.swift` (lines 176-303)
- Why fragile: NSCursor maintains a stack internally. Mismatched push/pop or hide/unhide calls can leave the cursor stuck.
- Safe modification: Document the cursor state machine:
  - Launch: system crosshair shown (via `resetCursorRects()`)
  - First mouse move: `NSCursor.hide()`, custom CAShapeLayer takes over
  - Selection hover: push hand cursor, `NSCursor.unhide()`
  - Release from hover: pop hand cursor, `NSCursor.hide()`
  - Exit: `NSCursor.unhide()` once only (in `Ruler.handleExit()` line 121)
- Add guards to prevent duplicate hide/unhide or mismatched stack operations.

## Multi-Monitor Window Lifecycle Not Fully Tested

**Windows are created for ALL screens, not just the cursor screen:**
- Issue: `Ruler.run()` (lines 45-50) creates one `RulerWindow` per screen and captures all screens simultaneously. This is memory-intensive and untested on setups with >2 monitors or mixed Retina/non-Retina.
- Files: `swift/Ruler/Sources/Ruler.swift` (lines 42-95)
- Impact: On a 3-monitor setup, 3 windows are captured and displayed. Switching between them is smooth, but the initial capture takes longer and uses more memory.
- Scaling path: Consider lazy creation — only create windows on-demand when cursor enters a new screen. This requires refactoring the callback system but reduces startup time and memory.

## Pill Position Snap Without Bounds Checking

**Pill layout can place text outside view bounds if dimensions are very small:**
- Issue: `CrosshairView.layoutPill()` (lines 277-344) positions the pill near the cursor with fallback logic for screen edges, but does not verify the pill width/height fit within screen bounds. If cursor is in a corner with a tiny dimension, the pill might render partially off-screen.
- Files: `swift/Ruler/Sources/Rendering/CrosshairView.swift` (lines 293-298)
- Impact: Low severity — pill is always visible at cursor position, just possibly clipped. Users will still see dimensions.
- Fix approach: Add clamping logic to ensure pill never extends beyond `[12px, screenWidth-12px]` and `[12px, screenHeight-12px]`. Test in corner cases (1px dimensions, ultra-wide monitors).

## DirectionalEdges Fully Optional (No Nil Return Case Documented)

**`EdgeDetector.onMouseMoved()` returns nil but documentation doesn't say when:**
- Issue: `EdgeDetector.onMouseMoved()` (lines 69-78) returns `DirectionalEdges?`. It can return nil if `colorMap` is nil, but the only `DirectionalEdges?` return in `currentEdges()` (line 82) guards colorMap. So nil only happens if colorMap was never set, which should not occur in normal flow.
- Files: `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` (lines 69-78)
- Impact: `RulerWindow.mouseMoved()` (line 194) has a guard that returns early if nil, which is correct. But the nil case is not preventable in normal operation.
- Fix approach: Either make `EdgeDetector.onMouseMoved()` throw an error if colorMap is nil (forcing explicit error handling), or assert that colorMap is set. This clarifies the contract.

## HintBar Dismiss via Backspace Not Reversible

**Once user presses backspace to dismiss hint bar, it stays dismissed even when preference is off:**
- Issue: `RulerWindow.keyDown()` (lines 327-340) sets `UserDefaults` key "hintBarDismissed" to true when backspace is pressed. This persists across sessions. The hint bar only reappears if `hideHintBar` preference is toggled ON, which clears the flag (see `Ruler.run()` lines 30-32).
- Files:
  - `swift/Ruler/Sources/RulerWindow.swift` (lines 327-340)
  - `swift/Ruler/Sources/Ruler.swift` (lines 30-32)
- Impact: Users who accidentally press backspace once will not see the hint bar again unless they explicitly toggle the preference. This is unintuitive.
- Fix approach: Add a "Settings" menu or keyboard shortcut (e.g., `?`) to toggle hint bar visibility dynamically, without persisting to UserDefaults. Or display a persistent "Hint bar dismissed" indicator that users can click to restore it.

## NSApplication.run() Blocks Forever Without Exit

**`Ruler.run()` (line 104) calls `app.run()` which blocks the Raycast command indefinitely:**
- Issue: `NSApplication.run()` is a modal event loop that runs forever until `NSApplication.terminate()` is called. If `handleExit()` never fires (e.g., ESC is eaten by another process), the command hangs.
- Files: `swift/Ruler/Sources/Ruler.swift` (lines 103-104), `swift/Ruler/Sources/Ruler.swift` (lines 119-127)
- Impact: If a window is orphaned or event routing fails, Raycast command may appear to hang. Users would need to force-kill the process.
- Recommendations:
  - Add a max-lifetime timeout (e.g., 10 minutes) via `DispatchSourceTimer`
  - Ensure ESC key is handled at OS level, not just in the window's keyDown event
  - Log all exit paths to verify which code path is taken on exit

## Tap-to-Clear on Selection Not Discoverable

**Users can click a hovered selection to remove it, but this is not documented anywhere:**
- Issue: `RulerWindow.mouseDown()` (lines 233-249) has logic to remove a selection if the hovered state is active, but this interaction is not explained in the hint bar or help system.
- Files: `swift/Ruler/Sources/RulerWindow.swift` (lines 232-250)
- Impact: Users may not know they can delete selections by clicking them. Selections persist until ESC or app exit.
- Fix approach: Update hint bar to show "Click a selection to remove it" when hovering a selection, or add a persistent "Clear" button overlay on selections.

---

*Concerns audit: 2026-02-13*
