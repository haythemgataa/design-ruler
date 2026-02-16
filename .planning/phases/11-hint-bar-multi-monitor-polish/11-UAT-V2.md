---
status: diagnosed
phase: 11-hint-bar-multi-monitor-polish
source: [11-03-SUMMARY.md, 11-04-SUMMARY.md]
started: 2026-02-16T19:20:00Z
updated: 2026-02-16T20:45:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Color circle border clipping
expected: Press space to cycle through colors. The color circle indicator appears. Look closely at the border edges — no color should bleed or peek outside the rounded border. The border should cleanly clip all fill content.
result: pass

### 2. Spacebar during exit animation
expected: Press space to show the color circle indicator, then press space again quickly while the indicator is fading out (exit animation). The indicator should reappear correctly with the selection dot visible — no disappearing dot.
result: pass

### 3. Tab keycap symbol
expected: Look at the hint bar — the tab keycap should show an arrow followed by a pipe character (->|) rendered natively. No missing/fallback glyph boxes.
result: issue
reported: "tab keycap width: 40px. →: 14px. |: 11px. →| position: bottom left of the keycap"
severity: cosmetic

### 4. Space keycap symbol and size
expected: The space keycap in the hint bar shows an open-box symbol (looks like a small U shape at the bottom) centered in a wider keycap (64px wide). The symbol should be clearly visible at 16px size.
result: issue
reported: "␣ looks different than in Figma. Revert to 'space' text at 12px"
severity: cosmetic

### 5. Second monitor screenshot (if multiple screens)
expected: With multiple screens connected, launch alignment guides. The second monitor should show a captured screenshot of the desktop — not a black screen.
result: issue
reported: "still black"
severity: blocker

### 6. Preview line on monitor switch (if multiple screens)
expected: With multiple screens, move cursor from one monitor to another. The preview line on the previous monitor should disappear. A new preview line appears on the new monitor at the cursor position. No frozen/phantom preview lines on inactive screens.
result: pass

### 7. Color circle position on secondary monitor (if multiple screens)
expected: Launch alignment guides while cursor is on the second monitor. Press space before moving the mouse. The color circle indicator should appear near the cursor — not at the top-left corner of the main monitor.
result: issue
reported: "still at bottom left corner of main monitor, until I move out of that monitor and back"
severity: major

## Summary

total: 7
passed: 3
issues: 4
pending: 0
skipped: 0

## Gaps

- truth: "Tab keycap renders →| composite symbol with correct sizing and position"
  status: failed
  reason: "User reported: tab keycap width: 40px. →: 14px. |: 11px. →| position: bottom left of the keycap"
  severity: cosmetic
  test: 3
  root_cause: |
    The tab keycap in HintBarContent.swift uses a single Unicode symbol "⇥" (U+21E5) at 13px centered,
    but user wants a composite symbol "→|" with specific sizing (→ at 14px, | at 11px) positioned
    at bottom-left with 40px keycap width.

    Current: Line 47-49 uses symbol: "⇥", width: 32, align: .center
    Expected: Composite HStack with "\u{2192}" at 14px + "|" at 11px, width: 40, align: .bottomLeading

    The composite rendering pattern already exists in KeyCap.capLabel (lines 433-442) but only
    triggers when `id == .tab`. However, the HintBarContent creates tab keycaps with wrong parameters
    that don't match user requirements.
  artifacts:
    - swift/Ruler/Sources/Rendering/HintBarContent.swift:47-49 (alignment guides mode)
    - swift/Ruler/Sources/Rendering/HintBarContent.swift:109-111 (collapsed mode)
    - swift/Ruler/Sources/Rendering/HintBarContent.swift:288-291 (glass mode)
  missing: []
  debug_session: ""

- truth: "Space keycap uses correct symbol and size"
  status: failed
  reason: "User reported: ␣ looks different than in Figma. Revert to 'space' text at 12px"
  severity: cosmetic
  test: 4
  root_cause: |
    The space keycap uses Unicode symbol "\u{2423}" (open box / space symbol) at 16px in a 64px wide
    keycap, but user reports it looks wrong in SF Pro Rounded and wants plain text "space" at 12px instead.

    Current: Line 51-53 uses symbol: "\u{2423}", width: 64, symbolFont: 16px
    Expected: symbol: "space", width: 64, symbolFont: 12px

    The problem is purely visual — SF Pro Rounded renders U+2423 differently than expected.
    Simple fix: change symbol string from "\u{2423}" to "space" and font size from 16px to 12px.
  artifacts:
    - swift/Ruler/Sources/Rendering/HintBarContent.swift:51-53 (alignment guides mode)
    - swift/Ruler/Sources/Rendering/HintBarContent.swift:112-114 (collapsed mode)
    - swift/Ruler/Sources/Rendering/HintBarContent.swift:294-297 (glass mode)
  missing: []
  debug_session: ""

- truth: "Second monitor shows captured screenshot (not black)"
  status: failed
  reason: "User reported: still black"
  severity: blocker
  test: 5
  root_cause: |
    The captureScreen() method in AlignmentGuides.swift (line 108-116) passes screen.frame directly
    to CGWindowListCreateImage without coordinate conversion. screen.frame uses AppKit coordinates
    (origin at bottom-left), but CGWindowListCreateImage expects CG coordinates (origin at top-left).

    This works accidentally for the main screen, but fails for secondary monitors where coordinate
    systems differ. The capture returns nil or captures the wrong screen region, resulting in a
    black window.

    Compare with EdgeDetector.swift:18-27 which correctly converts:
      cgRect.y = mainHeight - frame.origin.y - frame.height

    The fix in 11-03 (f701f01) removed duplicate background creation but did NOT fix the coordinate
    conversion bug, so secondary monitors still show black.
  artifacts:
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuides.swift:108-116 (captureScreen method)
    - swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift:18-27 (correct coordinate conversion)
  missing:
    - Coordinate conversion from AppKit to CG before CGWindowListCreateImage
  debug_session: ""

- truth: "Color circle indicator follows cursor on correct screen when launched from second monitor"
  status: failed
  reason: "User reported: still at bottom left corner of main monitor, until I move out of that monitor and back"
  severity: major
  test: 7
  root_cause: |
    The fix in 11-03 (f701f01) initialized lastCursorPosition in showInitialState() using
    NSEvent.mouseLocation, BUT showInitialState() is only called on the cursor window (line 98 in
    AlignmentGuides.swift), not on all windows.

    When launched from second monitor:
    1. Second monitor window: showInitialState() called → lastCursorPosition set correctly
    2. Main monitor window: showInitialState() NOT called → lastCursorPosition remains at .zero (line 21)
    3. User presses spacebar before moving mouse
    4. Main monitor window uses lastCursorPosition = (0, 0) → color circle at bottom-left

    The activate() method (line 153-162) updates preview position but does NOT update lastCursorPosition,
    so windows that weren't the initial cursor window still have .zero until first mouseMoved() event.

    User reports "until I move out of that monitor and back" confirms this: moving the mouse triggers
    mouseMoved() which sets lastCursorPosition (line 189), fixing the position.
  artifacts:
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift:21 (lastCursorPosition initialized to .zero)
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift:105-113 (showInitialState only updates cursor window)
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift:153-162 (activate does not update lastCursorPosition)
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuides.swift:98 (only cursor window gets showInitialState)
  missing:
    - lastCursorPosition update in activate() method
  debug_session: ""
