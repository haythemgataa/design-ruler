---
phase: 22-global-hotkeys
verified: 2026-02-19T12:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 22: Global Hotkeys Verification Report

**Phase Goal:** User can trigger both overlay commands via configurable global keyboard shortcuts from any application
**Verified:** 2026-02-19
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | App ships with no pre-assigned hotkeys — both bindings unassigned on first launch | VERIFIED | `HotkeyNames.swift`: `Self("measure")` and `Self("alignmentGuides")` — no `default:` parameter passed to either constructor. No default shortcut assigned. |
| 2 | User can record a custom keyboard shortcut for Measure in Settings | VERIFIED | `SettingsView.swift` line 60: `KeyboardShortcuts.Recorder("Shortcut:", name: .measure)` in the Measure section |
| 3 | User can record a custom keyboard shortcut for Alignment Guides in Settings | VERIFIED | `SettingsView.swift` line 78: `KeyboardShortcuts.Recorder("Shortcut:", name: .alignmentGuides)` in the Alignment Guides section |
| 4 | Pressing an assigned hotkey from any app launches the corresponding overlay | VERIFIED | `HotkeyController.swift`: `KeyboardShortcuts.onKeyUp(for: .measure)` and `onKeyUp(for: .alignmentGuides)` registered in `registerHandlers()`, called from `AppDelegate.applicationDidFinishLaunching`. Carbon-based global hotkeys fire from any application. |
| 5 | Pressing same-command hotkey while overlay is active toggles it off | VERIFIED | `HotkeyController.swift` line 38-45: `if command == activeCommand` branch calls `MeasureCoordinator.shared.handleExit()` / `AlignmentGuidesCoordinator.shared.handleExit()` |
| 6 | Pressing cross-command hotkey while overlay is active closes current and launches the other | VERIFIED | `HotkeyController.swift` line 46-62: `else if activeCommand != nil` branch exits active command then dispatches `launchCommand` via `DispatchQueue.main.async` |
| 7 | Menu bar dropdown shows assigned shortcut symbols next to command names | VERIFIED | `MenuBarController.swift` lines 62-63: `measureItem.setShortcut(for: .measure)` and `guidesItem.setShortcut(for: .alignmentGuides)` inside `MainActor.assumeIsolated { }` |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `App/Sources/HotkeyNames.swift` | KeyboardShortcuts.Name extensions for .measure and .alignmentGuides | VERIFIED | Exists, 6 lines, defines both names with no defaults |
| `App/Sources/HotkeyController.swift` | Session-aware hotkey dispatch (toggle-off, cross-switch, normal launch) | VERIFIED | Exists, 75 lines, all three dispatch paths implemented and substantive |
| `App/project.yml` | KeyboardShortcuts 2.4.0 SPM dependency | VERIFIED | Line 13-15: `KeyboardShortcuts: url: https://github.com/sindresorhus/KeyboardShortcuts from: "2.4.0"`, also in target dependencies line 28 |
| `App/Sources/AppDelegate.swift` | HotkeyController creation, handler registration, session tracking | VERIFIED | `hotkeyController` property, all wiring present, `registerHandlers()` called |
| `App/Sources/MenuBarController.swift` | setShortcut(for:) on both menu items | VERIFIED | `import KeyboardShortcuts`, both `setShortcut` calls present |
| `App/Sources/SettingsView.swift` | Two KeyboardShortcuts.Recorder controls with conflict detection | VERIFIED | Exactly 2 Recorder instances, bidirectional conflict detection with inline orange warnings |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `HotkeyController.swift` | `OverlayCoordinator.handleExit()` | toggle-off and cross-switch dispatch | WIRED | `MeasureCoordinator.shared.handleExit()` and `AlignmentGuidesCoordinator.shared.handleExit()` called directly; `handleExit()` confirmed public in `OverlayCoordinator.swift` line 213 |
| `AppDelegate.swift` | `HotkeyController.swift` | onKeyUp handler registration | WIRED | `hotkeyController.registerHandlers()` called at line 69; session callbacks at lines 39, 44, 58, 63, 74, 78 |
| `MenuBarController.swift` | `HotkeyNames.swift` | NSMenuItem.setShortcut(for:) | WIRED | `setShortcut(for: .measure)` and `setShortcut(for: .alignmentGuides)` reference the names defined in HotkeyNames.swift |
| `SettingsView.swift` | `HotkeyNames.swift` | Recorder name: .measure and .alignmentGuides | WIRED | Both Recorder controls reference `.measure` and `.alignmentGuides` shortcut names |
| `SettingsView.swift` | KeyboardShortcuts library | Recorder control and getShortcut/setShortcut API | WIRED | `import KeyboardShortcuts` at top, `KeyboardShortcuts.Recorder`, `KeyboardShortcuts.getShortcut`, `KeyboardShortcuts.setShortcut` all present |

### Requirements Coverage

All four success criteria from ROADMAP.md are satisfied:

| Requirement | Status | Evidence |
|-------------|--------|---------|
| No pre-assigned hotkeys — Settings shows both bindings as unassigned on first launch | SATISFIED | `Self("measure")` / `Self("alignmentGuides")` constructors have no `default:` argument |
| User can record Measure shortcut in Settings Shortcuts tab | SATISFIED | `KeyboardShortcuts.Recorder("Shortcut:", name: .measure)` in Measure section |
| User can record Alignment Guides shortcut in Settings Shortcuts tab | SATISFIED | `KeyboardShortcuts.Recorder("Shortcut:", name: .alignmentGuides)` in Alignment Guides section |
| Pressing assigned hotkey from any app (e.g. Figma) launches the overlay | SATISFIED | `KeyboardShortcuts.onKeyUp` handlers registered globally via Carbon; `launchCommand` calls coordinator `run()` |

### Anti-Patterns Found

No anti-patterns found in the modified files.

- No TODO/FIXME/PLACEHOLDER comments in any phase 22 source files
- No stub implementations (empty return, console.log only, return null)
- No shortcuts placeholder section remaining in SettingsView (`"Shortcuts will be available"` not found)
- No default shortcuts assigned in HotkeyNames.swift

### Build Verification

| Build Target | Status | Evidence |
|-------------|--------|---------|
| Xcode (App) — `xcodebuild Debug` | BUILD SUCCEEDED | Confirmed via build output |
| SPM (Raycast) — `swift build` | Build complete | Confirmed from `swift/DesignRuler/` — KeyboardShortcuts is in project.yml only, not Package.swift |

### Human Verification Required

The following items require human testing and cannot be verified programmatically:

#### 1. Hotkey fires from a non-Design-Ruler application

**Test:** Assign a shortcut (e.g., Cmd+Shift+M) to Measure in Settings. Switch focus to Figma, Sketch, or any other app. Press the assigned shortcut.
**Expected:** The Measure overlay launches immediately, fullscreen, on the screen where the cursor is.
**Why human:** Carbon hotkey registration cannot be exercised by static code analysis. The test requires a running app with an assigned shortcut.

#### 2. Toggle-off behavior

**Test:** Assign a shortcut to Measure. Launch Measure via the shortcut (from any app). Press the same shortcut again while the overlay is visible.
**Expected:** The overlay closes instantly (same behavior as pressing ESC).
**Why human:** Requires runtime interaction with the active session state machine.

#### 3. Cross-command switch

**Test:** Assign shortcuts to both Measure and Alignment Guides. Launch Measure via its shortcut. While Measure is active, press the Alignment Guides shortcut.
**Expected:** Measure closes, then Alignment Guides launches (with a brief async delay for autorelease pool drainage).
**Why human:** Requires two active sessions and runtime event sequencing.

#### 4. Shortcut Recorder UI appearance and interaction

**Test:** Open Settings > Measure section. Verify the "Shortcut:" recorder control is visible. Click it to record a shortcut. Press a key combination (e.g., Cmd+Shift+M). Verify the shortcut is displayed and accepted.
**Expected:** Recorder shows "Record Shortcut" placeholder when unassigned, shows shortcut symbol when assigned, and displays an X button to clear it.
**Why human:** Visual and interaction behavior of the Recorder control from the third-party KeyboardShortcuts library cannot be verified statically.

#### 5. Conflict detection UI

**Test:** Assign Cmd+Shift+M to Measure. Open Settings and attempt to assign the same shortcut (Cmd+Shift+M) to Alignment Guides.
**Expected:** An inline orange warning appears: "Already assigned to Measure", and the shortcut is not saved to Alignment Guides.
**Why human:** Requires runtime state comparison between two recorder controls.

#### 6. Menu bar shortcut symbol display

**Test:** Assign a shortcut to one or both commands. Open the Design Ruler menu bar dropdown.
**Expected:** The assigned shortcut appears right-aligned next to the command name (e.g., "Measure  ⌘⇧M"). Unassigned commands show no shortcut.
**Why human:** NSMenuItem.setShortcut(for:) rendering and dynamic update behavior requires visual inspection at runtime.

### Gaps Summary

No gaps found. All must-haves from both 22-01-PLAN.md and 22-02-PLAN.md are verified against the actual codebase. The implementation matches the plan specification exactly, with one documented deviation (MainActor.assumeIsolated for setShortcut calls) that was auto-fixed and confirmed by successful xcodebuild.

---

_Verified: 2026-02-19_
_Verifier: Claude (gsd-verifier)_
