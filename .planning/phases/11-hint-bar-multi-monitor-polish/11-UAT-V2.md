---
status: complete
phase: 11-hint-bar-multi-monitor-polish
source: [11-03-SUMMARY.md, 11-04-SUMMARY.md]
started: 2026-02-16T19:20:00Z
updated: 2026-02-16T19:35:00Z
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
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Space keycap uses correct symbol and size"
  status: failed
  reason: "User reported: ␣ looks different than in Figma. Revert to 'space' text at 12px"
  severity: cosmetic
  test: 4
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Second monitor shows captured screenshot (not black)"
  status: failed
  reason: "User reported: still black"
  severity: blocker
  test: 5
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Color circle indicator follows cursor on correct screen when launched from second monitor"
  status: failed
  reason: "User reported: still at bottom left corner of main monitor, until I move out of that monitor and back"
  severity: major
  test: 7
  artifacts: []
  missing: []
  debug_session: ""
