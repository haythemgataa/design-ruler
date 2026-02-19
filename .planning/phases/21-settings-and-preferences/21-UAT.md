---
status: complete
phase: 21-settings-and-preferences
source: 21-01-SUMMARY.md, 21-02-SUMMARY.md, 21-03-SUMMARY.md
started: 2026-02-19T14:00:00Z
updated: 2026-02-19T14:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. No Sparkle Error on Launch
expected: Build and launch the app. No error dialog appears — specifically no "Unable to Check For Updates" or "The updater failed to start" message. The app starts silently with the menu bar icon.
result: pass

### 2. Open Settings Window
expected: Click the menu bar icon to open the dropdown. A "Settings..." item with Cmd+, shortcut is visible. Clicking it (or pressing Cmd+,) opens a Settings window with grouped sections: General, Measure, Shortcuts, and About.
result: pass

### 3. Launch at Login Toggle Sync
expected: In Settings > General, toggle "Launch at Login" ON. Close the Settings window. Reopen Settings — the toggle should still show ON. Now toggle it OFF. Close Settings. Reopen Settings — the toggle should show OFF (not revert to ON). The toggle should always match the actual state in System Settings > Login Items.
result: pass

### 4. Hide Hint Bar Preference
expected: In Settings > General, toggle "Hide Hint Bar" ON. Launch Measure from the menu bar — the hint bar should NOT appear. Exit (ESC), toggle it back OFF in Settings, launch Measure again — hint bar appears.
result: pass

### 5. Corrections Mode Preference
expected: In Settings > Measure, radio buttons for corrections mode are visible (Smart, Include, None). Select a different mode, close and reopen Settings — the selection persists.
result: pass

### 6. About Section
expected: In Settings > About, the app icon, name ("Design Ruler"), version number, and copyright are displayed. A GitHub link is present.
result: pass

### 7. Check for Updates Menu Item
expected: The menu bar dropdown shows "Check for Updates..." between Settings and Quit. Clicking it does NOT produce an error dialog. (Since no real appcast URL is configured yet, Sparkle may show a "no updates available" or connection error — that's fine. The key is no startup failure.)
result: issue
reported: "nothing showed up"
severity: major

### 8. Auto-Check for Updates Toggle
expected: In Settings > General, an "Automatically Check for Updates" toggle is present. In Settings > About, a "Check for Updates..." button is present. Both are interactive (not grayed out).
result: pass

## Summary

total: 8
passed: 7
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "Check for Updates menu item triggers Sparkle update check dialog"
  status: deferred-to-phase-24
  reason: "User reported: nothing showed up"
  severity: major
  test: 7
  root_cause: "startingUpdater: false (set in 21-03 to avoid placeholder EdDSA key validation error) means SPUUpdater is never started. checkForUpdates() silently no-ops on an uninitialized updater. Phase 24 will set real keys and re-enable startingUpdater: true."
  artifacts:
    - path: "App/Sources/AppDelegate.swift"
      issue: "SPUStandardUpdaterController initialized with startingUpdater: false — updater never starts"
    - path: "App/Sources/Info.plist"
      issue: "SUPublicEDKey is placeholder 'PLACEHOLDER_EDDSA_PUBLIC_KEY' — cannot pass validation"
  missing:
    - "Phase 24: Replace placeholder EdDSA key with real key"
    - "Phase 24: Replace placeholder SUFeedURL with real appcast URL"
    - "Phase 24: Change startingUpdater back to true"
  debug_session: ""
