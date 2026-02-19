---
status: diagnosed
phase: 21-settings-and-preferences
source: 21-01-SUMMARY.md, 21-02-SUMMARY.md
started: 2026-02-19T12:00:00Z
updated: 2026-02-19T12:20:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Open Settings Window
expected: Click the menu bar icon to open the dropdown. A "Settings..." item with Cmd+, shortcut is visible. Clicking it (or pressing Cmd+,) opens a Settings window with 4 grouped sections: General, Measure, Shortcuts, and About.
result: pass

### 2. Settings Window Persistence
expected: Close the Settings window (Cmd+W or red close button). Reopen it from the menu bar. The window reappears without flicker — same window reused, not recreated from scratch.
result: pass

### 3. Hide Hint Bar Preference
expected: In Settings > General, toggle "Hide Hint Bar" ON. Launch Measure from the menu bar. The hint bar should NOT appear. Exit (ESC), toggle it back OFF, launch Measure again — hint bar appears normally.
result: pass

### 4. Corrections Mode Preference
expected: In Settings > Measure, radio buttons for corrections mode are visible (Smart, Include, None). Selecting a different mode persists — close and reopen Settings, the selection is still there.
result: pass

### 5. Launch at Login Toggle
expected: In Settings > General, "Launch at Login" toggle is present. Toggling it ON registers the app in System Settings > General > Login Items. Toggling it OFF removes it.
result: issue
reported: "it works for the most part, after toggling it off, it gets removed from Login Items, but if I close Settings and reopen, I find it set to on again, even though it's still removed from Login Items, toggeling it off and on again adds it back to Login Items"
severity: major

### 6. About Section
expected: In Settings > About, the app icon, app name ("Design Ruler"), version number, and copyright text are displayed. A GitHub link is present.
result: pass

### 7. Check for Updates Menu Item
expected: The menu bar dropdown shows "Check for Updates..." as a menu item (between Settings and Quit). Clicking it triggers a Sparkle update check dialog.
result: issue
reported: "nothing happened. as I first launch the app I get this: Unable to Check For Updates - The updater failed to start. Please verify you have the latest version of Design Ruler and contact the app developer if the issue still persists. Check the Console logs for more information."
severity: major

### 8. Check for Updates in Settings
expected: In Settings > About section, a "Check for Updates..." button is present. In Settings > General, an "Automatically Check for Updates" toggle is present.
result: pass

## Summary

total: 8
passed: 6
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "Launch at Login toggle reflects actual SMAppService registration status when Settings window is reopened"
  status: failed
  reason: "User reported: it works for the most part, after toggling it off, it gets removed from Login Items, but if I close Settings and reopen, I find it set to on again, even though it's still removed from Login Items, toggeling it off and on again adds it back to Login Items"
  severity: major
  test: 5
  root_cause: "The toggle uses a custom Binding whose get closure reads SMAppService.mainApp.status, but SMAppService.status is not observable by SwiftUI — no @State/@Published backs it — so SwiftUI never re-evaluates the binding when the settings window reappears (window is reused, not recreated)."
  artifacts:
    - path: "App/Sources/SettingsView.swift"
      issue: "Custom Binding(get:set:) reads SMAppService.mainApp.status which is opaque to SwiftUI dependency tracking"
    - path: "App/Sources/SettingsWindowController.swift"
      issue: "Window reuse path (isReleasedWhenClosed=false) does not trigger any SwiftUI state refresh"
  missing:
    - "Add @State private var launchAtLogin: Bool initialized from SMAppService status, refresh via .onAppear"
  debug_session: ".planning/debug/launch-at-login-toggle-desync.md"

- truth: "Sparkle updater starts without error and Check for Updates triggers update check dialog"
  status: failed
  reason: "User reported: nothing happened. as I first launch the app I get this: Unable to Check For Updates - The updater failed to start. Please verify you have the latest version of Design Ruler and contact the app developer if the issue still persists."
  severity: major
  test: 7
  root_cause: "Placeholder string 'PLACEHOLDER_EDDSA_PUBLIC_KEY' in SUPublicEDKey fails Sparkle 2's EdDSA key validation (not valid base64, not 32-byte Ed25519 key), causing SPUUpdater.startUpdater to fail immediately since startingUpdater:true triggers validation at init time."
  artifacts:
    - path: "App/Sources/AppDelegate.swift"
      issue: "SPUStandardUpdaterController initialized with startingUpdater: true triggers immediate key validation"
    - path: "App/Sources/Info.plist"
      issue: "SUPublicEDKey set to 'PLACEHOLDER_EDDSA_PUBLIC_KEY' which is not valid base64"
    - path: "App/project.yml"
      issue: "Same placeholder duplicated in xcodegen info properties"
  missing:
    - "Change startingUpdater: true to startingUpdater: false so Sparkle does not validate keys until real ones are configured in Phase 24"
  debug_session: ".planning/debug/sparkle-updater-fails-to-start.md"
