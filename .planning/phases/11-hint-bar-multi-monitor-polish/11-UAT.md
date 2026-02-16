---
status: complete
phase: 11-hint-bar-multi-monitor-polish
source: [11-01-SUMMARY.md, 11-02-SUMMARY.md]
started: 2026-02-16T12:00:00Z
updated: 2026-02-16T12:25:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Remove-state fix after line removal
expected: Place a guide line, hover it until "Remove" appears, click to remove. Preview line should immediately return to coordinate display (not stuck in remove mode). Cursor reverts to system crosshair.
result: pass

### 2. Preview pill opacity
expected: Move cursor around in alignment guides mode. The preview pill (showing the dimension number) should appear fully opaque — not semi-transparent or see-through.
result: pass

### 3. Color circle border thickness
expected: Press space to cycle through colors. The color circle indicator appears. The active (selected) circle has a visibly thicker border than inactive circles. Active = 3px, Inactive = 2px.
result: issue
reported: "the color peeks just a tiny bit out of the border, ideally the border would hide the color and it won't be visible outside of the border. if I press space bar when the exit animation is playing, the selection dot disappears"
severity: cosmetic, major

### 4. Dynamic circle colors
expected: The dynamic preset circle (first one, split in half) shows a dark gray left half and light gray right half — softer than pure black/white.
result: pass

### 5. Hint bar shows alignment guides content
expected: When alignment guides launches, the hint bar shows: "Press [tab] to switch direction, [space] to change color. [esc] to exit." with tab, space, and esc keycaps. After collapse, only [tab] [space] keycaps on left and [esc] on right.
result: issue
reported: "for the tab icon, since ⇥ isn't supported by SF Pro Rounded, use →| as two separate text layers with | at 11px. for the space bar, use ␣ symbol at 16px centered, make keycap 64px wide"
severity: cosmetic

### 6. Hint bar collapse timing
expected: After launching alignment guides, the hint bar stays expanded (full text visible) for approximately 3 seconds. After that, on first mouse move, it collapses to show only the keycaps.
result: pass

### 7. Hint bar bottom-to-top repositioning
expected: Move cursor near the bottom edge of the screen. The hint bar should slide (animate) from bottom to top. Move cursor away from bottom — it slides back down.
result: pass

### 8. Keycap press feedback
expected: Press tab, space, or esc key. The corresponding keycap in the hint bar shows a visual press effect (color change or depression) while held, and releases when key is released.
result: pass

### 9. Multi-monitor overlays (if multiple screens)
expected: With multiple screens connected, launch alignment guides. Each screen gets its own fullscreen overlay with a frozen screenshot. No screen shows any overlay window in its screenshot (capture-before-window). Hint bar appears only on the screen where the cursor was at launch.
result: issue
reported: "second monitor is black. if I move the cursor to another monitor, the preview line remains frozen in the previous monitor and a second preview line appears in the new monitor, until I move back. so there is a preview line for each monitor, it doesn't disappear if I move away. if I launch the tool in the second monitor, the color switcher appears at x=0 y=0 of the main monitor, until I move to the main monitor and back for it to start following my cursor"
severity: blocker, minor, major

### 10. Global color cycling across screens (if multiple screens)
expected: With multiple screens, press space to change color on one screen. Move cursor to another screen. New guide lines use the same color that was selected. ESC closes all overlay windows on all screens.
result: pass

## Summary

total: 10
passed: 7
issues: 3
pending: 0
skipped: 0

## Gaps

- truth: "Color circle borders are 2px inactive, 3px active with no color bleeding outside"
  status: failed
  reason: "User reported: the color peeks just a tiny bit out of the border, ideally the border would hide the color and it won't be visible outside of the border"
  severity: cosmetic
  test: 3
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Color circle indicator handles space press during exit animation gracefully"
  status: failed
  reason: "User reported: if I press space bar when the exit animation is playing, the selection dot disappears"
  severity: major
  test: 3
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Tab keycap uses →| symbol (two separate text layers, | at 11px) for SF Pro Rounded consistency"
  status: failed
  reason: "User reported: ⇥ isn't supported by SF Pro Rounded, use →| as two separate text layers with | at 11px"
  severity: cosmetic
  test: 5
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Space keycap uses ␣ symbol at 16px centered, keycap width 64px"
  status: failed
  reason: "User reported: use ␣ symbol at 16px centered, make the keycap 64px wide"
  severity: cosmetic
  test: 5
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Second monitor shows captured screenshot (not black)"
  status: failed
  reason: "User reported: second monitor is black"
  severity: blocker
  test: 9
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Preview line disappears from previous monitor when cursor moves to another"
  status: failed
  reason: "User reported: preview line remains frozen in previous monitor, a second preview line appears in the new monitor. There is a preview line for each monitor, it doesn't disappear if I move away"
  severity: minor
  test: 9
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Color circle indicator follows cursor on correct screen when launched from second monitor"
  status: failed
  reason: "User reported: if I launch the tool in the second monitor, the color switcher appears at x=0 y=0 of the main monitor, until I move to the main monitor and back for it to start following my cursor"
  severity: major
  test: 9
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
