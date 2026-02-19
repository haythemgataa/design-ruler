---
status: diagnosed
phase: 22-global-hotkeys
source: 22-01-SUMMARY.md, 22-02-SUMMARY.md
started: 2026-02-19T11:00:00Z
updated: 2026-02-19T11:20:00Z
---

## Current Test

[testing complete]

## Tests

### 1. No Default Hotkeys
expected: Open Settings from the menu bar. The Measure and Alignment Guides sections each have a shortcut recorder control. Both show no shortcut assigned (empty/blank recorder).
result: pass

### 2. Settings Section Order
expected: Settings window shows sections in this order: General, Measure, Alignment Guides, About. There is no separate "Shortcuts" section — recorders are inline within each command's section.
result: pass

### 3. Record Measure Shortcut
expected: Click the shortcut recorder in the Measure section, press a key combination (e.g., Ctrl+Shift+1). The recorder captures and displays the shortcut. It persists after closing and reopening Settings.
result: pass

### 4. Record Alignment Guides Shortcut
expected: Click the shortcut recorder in the Alignment Guides section, press a different key combination (e.g., Ctrl+Shift+2). The recorder captures and displays the shortcut. It persists after closing and reopening Settings.
result: pass

### 5. Conflict Detection
expected: Try assigning the same shortcut to both commands (e.g., set Alignment Guides to the same combo as Measure). The duplicate is rejected — an orange warning message appears and the shortcut is cleared.
result: issue
reported: "no warning is shown, but the shortcut didn't register"
severity: minor

### 6. Global Hotkey Launches Overlay
expected: Focus a different app (e.g., Finder or Safari). Press the assigned Measure hotkey. The Measure overlay launches fullscreen with the crosshair.
result: pass

### 7. Toggle-Off Hotkey
expected: While the Measure overlay is active, press the Measure hotkey again. The overlay closes (ESC-like behavior) and you return to your previous app.
result: pass

### 8. Cross-Command Switch
expected: Launch Measure via its hotkey. While the Measure overlay is active, press the Alignment Guides hotkey. Measure closes and Alignment Guides launches.
result: pass

### 9. Menu Bar Shows Shortcut Symbols
expected: After assigning shortcuts, open the menu bar dropdown. The Measure and Alignment Guides menu items display the assigned shortcut key combinations next to their names.
result: issue
reported: "nope, not shown"
severity: major

## Summary

total: 9
passed: 7
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "Orange warning message appears when assigning duplicate shortcut to both commands"
  status: failed
  reason: "User reported: no warning is shown, but the shortcut didn't register"
  severity: minor
  test: 5
  root_cause: "onChange callback fires twice — once with conflicting shortcut (sets warning), then again with nil when setShortcut(nil) triggers notification chain through RecorderCocoa.controlTextDidChange -> saveShortcut(nil) -> onChange(nil). The else branch unconditionally clears measureConflict/guidesConflict to nil on the second call."
  artifacts:
    - path: "App/Sources/SettingsView.swift"
      issue: "else { measureConflict = nil } and else { guidesConflict = nil } unconditionally clear warning on nil callback"
  missing:
    - "Change else { measureConflict = nil } to else if newShortcut != nil { measureConflict = nil } (same for guidesConflict)"
  debug_session: ""

- truth: "Menu bar dropdown displays assigned shortcut key combinations next to Measure and Alignment Guides items"
  status: failed
  reason: "User reported: nope, not shown"
  severity: major
  test: 9
  root_cause: "NSMenuItem.setShortcut(for:) is called once at init() time in MenuBarController.setupMenu(). The library uses NotificationCenter observers on associated objects to auto-update when shortcuts change. Static analysis shows correct wiring but the observer chain may fail at runtime — likely the observer is not firing or keyToCharacter() returns nil. Requires runtime investigation."
  artifacts:
    - path: "App/Sources/MenuBarController.swift"
      issue: "setShortcut(for:) called in setupMenu() lines 58-64, observer may not be updating menu items"
  missing:
    - "Verify NSMenuItem.setShortcut(for:) observer registration and notification chain at runtime"
    - "Check if keyEquivalent and keyEquivalentModifierMask are actually being set on menu items after shortcut recording"
  debug_session: ""
