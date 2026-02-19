---
status: resolved
trigger: "Launch at Login toggle shows ON after closing/reopening Settings even though unregistered via SMAppService"
created: 2026-02-19T00:00:00Z
updated: 2026-02-19T00:00:00Z
---

## Current Focus

hypothesis: confirmed - root cause identified (see Resolution)
test: n/a
expecting: n/a
next_action: return diagnosis

## Symptoms

expected: Toggle reflects actual SMAppService.mainApp.status (OFF after unregister)
actual: Toggle shows ON after closing and reopening the Settings window
errors: none
reproduction: Open Settings, toggle Launch at Login OFF, close window, reopen Settings - toggle shows ON
started: since implementation

## Eliminated

(none needed - root cause found on first hypothesis)

## Evidence

- timestamp: 2026-02-19T00:00:00Z
  checked: SettingsView.swift toggle binding
  found: Toggle uses custom Binding with get closure reading SMAppService.mainApp.status
  implication: This is a computed binding, not backed by @State - SwiftUI has no way to know when this value changes

- timestamp: 2026-02-19T00:00:00Z
  checked: SettingsWindowController.swift showSettings() method
  found: Three code paths - (1) window visible -> just makeKey, (2) window exists but hidden -> center + makeKey, (3) first time -> create NSWindow with NSHostingView(rootView: SettingsView(...))
  implication: On reopen (path 2), the NSHostingView and SettingsView are REUSED, not recreated. SwiftUI @State is preserved from previous session.

- timestamp: 2026-02-19T00:00:00Z
  checked: SMAppService.mainApp.status documentation
  found: SMAppService.mainApp.status is a synchronous property read, not an observable/published property. It has no KVO/Combine publisher. SwiftUI cannot observe changes to it.
  implication: The custom Binding's get closure IS called, but SwiftUI doesn't know WHEN to re-evaluate it because there's no state mutation triggering a view update.

- timestamp: 2026-02-19T00:00:00Z
  checked: The full reopen flow
  found: When Settings window is reopened (path 2 in showSettings), no SwiftUI state changes occur. The SettingsView body is NOT re-evaluated. The Binding get closure is not called because SwiftUI sees no reason to redraw.
  implication: The toggle displays stale state from the last time the body was evaluated.

## Resolution

root_cause: The "Launch at Login" toggle uses a custom Binding whose get closure reads SMAppService.mainApp.status, but since SMAppService.status is not observable by SwiftUI (no @State, @Published, or ObservableObject backing it), SwiftUI never knows to re-evaluate the binding when the window reappears -- the view body is not re-rendered, so the get closure is never re-called, and the toggle displays whatever state it had when the body was last evaluated.

fix: (not applied - diagnosis only)
verification: (not applied - diagnosis only)
files_changed: []
