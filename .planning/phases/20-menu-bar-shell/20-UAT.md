---
status: passed
phase: 20-menu-bar-shell
source: 20-01-SUMMARY.md
started: 2026-02-18T12:00:00Z
updated: 2026-02-18T12:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Menu bar icon on launch
expected: Build and run the app. A ruler icon (SF Symbol "ruler") appears in the macOS menu bar immediately on launch. No Dock icon appears. The app does not show in Cmd+Tab.
result: pass (on re-test)
note: Initially failed due to stale process from prior commit still running. After killing old process and relaunching, icon appeared correctly.

### 2. Dropdown menu contents
expected: Click the menu bar icon. A dropdown appears containing: "Measure", "Alignment Guides", a separator, "Settings..." (grayed out/disabled), a separator, and "Quit Design Ruler".
result: pass

### 3. Launch Measure overlay
expected: Click "Measure" in the dropdown. The fullscreen overlay launches with crosshair following cursor, edge detection, and W×H pill — same as when invoked from Raycast.
result: pass
note: "Minor cosmetic issue: hint bar starts at top on launch then jumps to bottom on first mouse move. Not a Phase 20 regression — existing behavior."

### 4. Icon changes during active overlay
expected: While the Measure overlay is active, look at the menu bar icon. It should be a filled ruler icon ("ruler.fill") instead of the outline version, visually indicating an active session.
result: pass
note: "Not directly observable since fullscreen overlay covers menu bar. User briefly saw filled->outline flash on exit, confirming the state change works."

### 5. ESC exits overlay, app stays alive
expected: Press ESC to exit the overlay. The overlay closes, but the menu bar icon remains visible — the app process stays alive and ready for another invocation.
result: pass

### 6. Icon reverts after session ends
expected: After pressing ESC to exit the overlay, the menu bar icon reverts from the filled ruler back to the outline ruler, indicating the session has ended.
result: pass
note: "Briefly visible as filled->outline on exit. Same observability limitation as test 4."

### 7. Launch Alignment Guides overlay
expected: Click the menu bar icon again and select "Alignment Guides". The fullscreen overlay launches with a preview guide line following the cursor. Tab toggles direction, spacebar cycles color, click places a line.
result: pass

### 8. Quit from menu bar
expected: Click the menu bar icon and select "Quit Design Ruler". The app terminates completely — menu bar icon disappears, process exits.
result: pass

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0

## Notes

- Initial test 1 failure was due to stale process from prior commit (no code bug). Resolved by killing old process.
- Icon state changes (tests 4, 6) are not easily observable since the fullscreen overlay covers the menu bar. Briefly visible on exit transition — confirmed working.
- Minor pre-existing cosmetic issue: hint bar starts at top on launch, jumps to bottom on first mouse move. Not a Phase 20 regression.
- Debugger found 24 EXC_BAD_ACCESS crash reports in overlay teardown (separate from Phase 20 work). See .planning/debug/menu-bar-icon-not-appearing.md for details.

## Gaps

[none — all tests passed]
