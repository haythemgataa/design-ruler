---
phase: 22-global-hotkeys
verified: 2026-02-19T12:30:00Z
status: human_needed
score: 4/4 success criteria verified (code)
re_verification: true
previous_status: passed
previous_score: 7/7
gaps_closed:
  - "Conflict detection warning persistence (nil-guard fix in SettingsView.swift)"
  - "Menu bar shortcut display (NSMenuDelegate + menuNeedsUpdate in MenuBarController.swift)"
gaps_remaining: []
regressions: []
human_verification:
  - test: "Hotkey fires from a non-Design-Ruler application (e.g. Figma, Finder)"
    expected: "Overlay launches immediately on correct screen"
    why_human: "Carbon global hotkey registration cannot be verified statically"
  - test: "Toggle-off behavior: press same hotkey while overlay active"
    expected: "Overlay closes (ESC behavior)"
    why_human: "Requires runtime session state machine interaction"
  - test: "Cross-command switch: press Guides hotkey while Measure is active"
    expected: "Measure closes, Alignment Guides launches after async delay"
    why_human: "Requires two live sessions and runtime event sequencing"
  - test: "Conflict detection warning: assign same shortcut to both commands"
    expected: "Orange warning appears and persists after rejection"
    why_human: "Nil-guard fix is code-verified but double-fire behavior needs UAT re-run to confirm"
  - test: "Menu bar shows shortcut symbols after shortcuts are assigned"
    expected: "Assigned shortcut appears right-aligned next to command names on menu open"
    why_human: "menuNeedsUpdate is code-verified but runtime rendering requires visual inspection"
  - test: "Settings recorder UI appearance and interaction"
    expected: "Recorder shows placeholder when unassigned, shortcut symbol when assigned, X to clear"
    why_human: "Third-party KeyboardShortcuts.Recorder visual behavior requires runtime inspection"
---

# Phase 22: Global Hotkeys Verification Report

**Phase Goal:** User can trigger both overlay commands via configurable global keyboard shortcuts from any application
**Verified:** 2026-02-19T12:30:00Z
**Status:** human_needed
**Re-verification:** Yes — post gap-closure (22-03); previous VERIFICATION.md predated UAT gap-closure execution

## Summary

All 4 success criteria are satisfied in code. Two UAT-reported bugs (conflict warning disappeared immediately; menu bar did not show shortcut symbols) were fixed in plan 22-03 via commits `c64af8b` and `fef8bec`. Both fixes are confirmed in the actual source files. No anti-patterns found. Human re-testing of the two fixed behaviors is recommended to confirm runtime correctness.

## Goal Achievement

### Observable Truths (Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Both bindings show as unassigned on first launch | VERIFIED | `HotkeyNames.swift` lines 4-5: `Self("measure")` and `Self("alignmentGuides")` — no `default:` argument |
| 2 | User can record a Measure shortcut in Settings Shortcuts tab | VERIFIED | `SettingsView.swift` line 60: `KeyboardShortcuts.Recorder("Shortcut:", name: .measure)` inside `Section("Measure")` |
| 3 | User can record an Alignment Guides shortcut in Settings Shortcuts tab | VERIFIED | `SettingsView.swift` line 78: `KeyboardShortcuts.Recorder("Shortcut:", name: .alignmentGuides)` inside `Section("Alignment Guides")` |
| 4 | Pressing assigned hotkey from any app launches corresponding overlay | VERIFIED | `HotkeyController.swift` lines 19-24: `KeyboardShortcuts.onKeyUp(for: .measure)` and `onKeyUp(for: .alignmentGuides)` registered via Carbon; `registerHandlers()` called at `AppDelegate.swift` line 69 |

**Score:** 4/4 success criteria verified

### Additional Truths (from sub-plans)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 5 | Same-command hotkey while overlay active toggles it off | VERIFIED | `HotkeyController.swift` lines 38-45: `if command == activeCommand` branch exits via `handleExit()` |
| 6 | Cross-command hotkey closes current overlay and opens the other | VERIFIED | `HotkeyController.swift` lines 46-62: `else if activeCommand != nil` exits then async-dispatches `launchCommand` |
| 7 | Conflict warning persists when duplicate shortcut assigned | VERIFIED (code) | `SettingsView.swift` lines 64, 82: `else if newShortcut != nil { ... = nil }` guards — nil callback no longer clears warning. UAT re-run recommended. |
| 8 | Menu bar shows shortcut symbols on dropdown open | VERIFIED (code) | `MenuBarController.swift` lines 102-107: `menuNeedsUpdate` re-applies `setShortcut(for:)` via NSMenuDelegate. UAT re-run recommended. |

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `App/Sources/HotkeyNames.swift` | VERIFIED | 6 lines; `.measure` and `.alignmentGuides` defined; no `default:` parameter |
| `App/Sources/HotkeyController.swift` | VERIFIED | 75 lines; all three dispatch paths (toggle-off, cross-switch, normal launch) substantive |
| `App/Sources/SettingsView.swift` | VERIFIED | Two `Recorder` controls at lines 60, 78; nil-guard at lines 64, 82; orange conflict text rendered conditionally |
| `App/Sources/MenuBarController.swift` | VERIFIED | `NSMenuDelegate` conformance line 5; stored `measureItem`/`guidesItem` lines 10-11; `menuNeedsUpdate` lines 102-107; `menuWillOpen`/`menuDidClose` lines 109-117 |
| `App/Sources/AppDelegate.swift` | VERIFIED | `hotkeyController` property line 9; `registerHandlers()` line 69; session-end callbacks lines 72-79 |
| `App/project.yml` | VERIFIED | `KeyboardShortcuts` SPM dep lines 13-15: `from: "2.4.0"`; target dependency line 28 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `HotkeyController.swift` | `OverlayCoordinator.handleExit()` | `.handleExit()` on shared singletons | WIRED | Calls confirmed lines 42-44 and 50-53; `handleExit()` is `public` at `OverlayCoordinator.swift` line 213 |
| `AppDelegate.swift` | `HotkeyController.swift` | `registerHandlers()` + callback wiring | WIRED | `registerHandlers()` at line 69; all three callbacks wired lines 57-68 |
| `MenuBarController.swift` | `HotkeyNames.swift` | `NSMenuItem.setShortcut(for:)` | WIRED | `setShortcut(for: .measure)` and `setShortcut(for: .alignmentGuides)` at lines 68-69 (init) and 104-105 (menuNeedsUpdate) |
| `SettingsView.swift` | `HotkeyNames.swift` | `Recorder(name:)` references | WIRED | Both Recorder controls reference `.measure` and `.alignmentGuides` from HotkeyNames.swift |
| `AppDelegate.swift` | `OverlayCoordinator.onSessionEnd` | Session-end callbacks | WIRED | `MeasureCoordinator.shared.onSessionEnd` line 72; `AlignmentGuidesCoordinator.shared.onSessionEnd` line 76; both call `setActive(false)` and `sessionEnded()` |
| `MenuBarController.swift` | `KeyboardShortcuts` library | `menuWillOpen`/`menuDidClose` | WIRED | `KeyboardShortcuts.disable/enable` calls confirmed at lines 110-116 |

### Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|---------|
| No pre-assigned hotkeys on first launch | SATISFIED | No `default:` argument in `HotkeyNames.swift` constructors |
| Record Measure shortcut in Settings Shortcuts tab | SATISFIED | `Recorder("Shortcut:", name: .measure)` in Measure section |
| Record Alignment Guides shortcut in Settings Shortcuts tab | SATISFIED | `Recorder("Shortcut:", name: .alignmentGuides)` in Alignment Guides section |
| Pressing assigned hotkey from any app launches overlay | SATISFIED | `KeyboardShortcuts.onKeyUp` Carbon handlers registered; `launchCommand` calls coordinator `run()` |

### Anti-Patterns Found

None. Scanned all five phase-22 source files (`HotkeyNames.swift`, `HotkeyController.swift`, `SettingsView.swift`, `MenuBarController.swift`, `AppDelegate.swift`):

- No TODO/FIXME/XXX/HACK/PLACEHOLDER comments
- No stub return patterns (`return null`, `return {}`, `return []`)
- No placeholder text
- No empty handler implementations

### Commits Verified

| Commit | Description | Verified |
|--------|-------------|---------|
| `a9f7442` | feat(22-02): add shortcut recorder controls | Present in git log |
| `c64af8b` | fix(22-03): guard conflict warning clear on nil callback | Present in git log |
| `fef8bec` | fix(22-03): add NSMenuDelegate to refresh shortcut display | Present in git log |

### Gap Closure Verification (vs. UAT Issues)

**UAT Issue 5 — Conflict warning disappeared immediately**

- Root cause: `onChange` fires twice when a shortcut is rejected via `setShortcut(nil)`; the second call with `nil` unconditionally cleared the warning in the `else` branch
- Fix: `else if newShortcut != nil { measureConflict = nil }` and `else if newShortcut != nil { guidesConflict = nil }` at `SettingsView.swift` lines 64 and 82
- Code-verified: YES — both guards confirmed present in actual source
- Runtime re-test: recommended

**UAT Issue 9 — Menu bar did not show shortcut symbols**

- Root cause: `setShortcut(for:)` called once at init; library observer chain failed at runtime
- Fix: `NSMenuDelegate` with `menuNeedsUpdate` re-applies shortcuts on every menu open
- Code-verified: YES — `NSMenuDelegate` conformance, stored item references, and `menuNeedsUpdate` all confirmed in actual source
- Runtime re-test: recommended

### Human Verification Required

#### 1. Global Hotkey Fires from External Application

**Test:** Assign a shortcut (e.g., Ctrl+Shift+1) to Measure in Settings. Switch focus to Figma, Finder, or Safari. Press the assigned shortcut.
**Expected:** The Measure overlay launches immediately, fullscreen, on the screen where the cursor is.
**Why human:** Carbon hotkey registration cannot be exercised by static code analysis.

#### 2. Toggle-Off Behavior

**Test:** Assign a shortcut to Measure. Launch Measure via the shortcut. While the overlay is visible, press the same shortcut again.
**Expected:** The overlay closes instantly (same behavior as ESC).
**Why human:** Requires runtime interaction with the active session state machine.

#### 3. Cross-Command Switch

**Test:** Assign shortcuts to both commands. Launch Measure via its shortcut. While Measure is active, press the Alignment Guides shortcut.
**Expected:** Measure closes, then Alignment Guides launches after a brief async delay.
**Why human:** Requires two live sessions and runtime event sequencing.

#### 4. Conflict Detection Warning Persistence (re-test after fix)

**Test:** Assign Ctrl+Shift+1 to Measure. Then attempt to assign Ctrl+Shift+1 to Alignment Guides.
**Expected:** An orange warning appears reading "Already assigned to Measure" and stays visible. It does not disappear after a fraction of a second.
**Why human:** Nil-guard fix is code-verified but the double-fire behavior requires runtime validation.

#### 5. Menu Bar Shortcut Symbol Display (re-test after fix)

**Test:** Assign shortcuts to Measure and Alignment Guides. Open the Design Ruler menu bar dropdown.
**Expected:** The assigned shortcut appears right-aligned next to each command name (e.g., "Measure  ^⇧1"). Commands without shortcuts show no key equivalent.
**Why human:** NSMenuDelegate `menuNeedsUpdate` is code-verified but runtime rendering requires visual inspection.

#### 6. Recorder UI Appearance and Interaction

**Test:** Open Settings. Verify both sections each contain a "Shortcut:" recorder. Click the recorder and press a key combination.
**Expected:** Recorder shows "Record Shortcut" placeholder when unassigned; shows shortcut symbol when assigned; shows an X button to clear it. Shortcut persists after closing and reopening Settings.
**Why human:** Third-party KeyboardShortcuts.Recorder visual behavior requires runtime inspection.

---

_Verified: 2026-02-19T12:30:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification: Yes — post gap-closure (22-03) state_
