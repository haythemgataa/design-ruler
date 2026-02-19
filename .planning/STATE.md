# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-18)

**Core value:** Instant, accurate pixel inspection of anything on screen — zero friction from invoke to dimension readout, whether launched from Raycast or a global hotkey.
**Current focus:** v2.0 Standalone App — Phase 22: Global Hotkeys

## Current Position

Phase: 22 of 24 (Global Hotkeys)
Plan: 2 of 2 complete in current phase
Status: Phase 22 complete — all plans executed (hotkey infrastructure + Settings recorder UI)
Last activity: 2026-02-19 — Completed 22-02: Settings shortcut recorder UI (KeyboardShortcuts.Recorder in Measure and Alignment Guides sections, conflict detection)

Progress: [####░░░░░░] 43% (v2.0 — 3/7 phases complete, Phase 22 done)

## Performance Metrics

**Velocity (v1.0):**
- Total plans completed: 5 | Average: 2min | Total: 0.2 hours

**Velocity (v1.1):**
- Total plans completed: 4 | Average: 13min | Total: ~53min

**Velocity (v1.2):**
- Total plans completed: 9 | Average: 2min 38s | Total: ~24min 57s

**Velocity (v1.3):**
- Total plans completed: 10 | Average: 2min 53s | Total: ~28min 49s

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 12    | 01   | 1min 23s | 2     | 2     |
| 12    | 02   | 7min 4s  | 2     | 5     |
| 13    | 01   | 2min 18s | 2     | 1     |
| 13    | 02   | 4min 1s  | 2     | 4     |
| 14    | 01   | 2min 27s | 2     | 3     |
| 14    | 02   | 2min 28s | 2     | 5     |
| 15    | 01   | 2min 6s  | 2     | 2     |
| 15    | 02   | 3min 27s | 2     | 3     |
| 16    | 01   | 2min 4s  | 1     | 1     |
| 17    | 01   | 1min 31s | 2     | 2     |
| quick-2 | 01 | 2min 23s | 3   | 6     |
| quick-3 | 01 | 5min 21s | 2   | 8     |
| quick-4 | 01 | 3min 36s | 2   | 9     |
| 18-build-system | 01 | 19min | 2 | 26 |
| 18-build-system | 02 | 2min  | 1 | 6  |
| 19-app-lifecycle-refactor | 01 | 1min 46s | 1 | 1 |
| 19-app-lifecycle-refactor | 02 | 6min 42s | 2 | 5 |
| 20-menu-bar-shell | 01 | 2min 58s | 2 | 5 |
| 21-settings-and-preferences | 01 | 2min 54s | 2 | 6 |
| 21-settings-and-preferences | 02 | 4min 8s  | 2 | 7 |
| 21-settings-and-preferences | 03 | 1min 22s | 2 | 2 |
| 22-global-hotkeys | 01 | 4min 15s | 2 | 6 |
| 22-global-hotkeys | 02 | 1min 4s  | 1 | 1 |

## Accumulated Context

### Decisions

All decisions logged in PROJECT.md Key Decisions table.

Key decisions for v2.0:
- Use KeyboardShortcuts 2.4.0 (Carbon-based, no Accessibility permission needed for registration)
- Use SMAppService.mainApp for launch at login (no helper bundle)
- App Sandbox must be disabled (CGEventTap + CGWindowListCreateImage incompatible)
- LSUIElement = YES in Info.plist (no Dock icon, no Cmd+Tab entry)
- RunMode enum added to OverlayCoordinator (~15-line change, not a rewrite)
- CursorManager.shared.restore() called at START of every run() (singleton state leak prevention)
- setActivationPolicy(.accessory) kept in OverlayCoordinator.run() (Raycast has no AppDelegate; also added to AppDelegate for standalone — idempotent)
- [Phase 18-build-system]: open class OverlayCoordinator (not package) required for cross-module subclassing by DesignRuler bridge target
- [Phase 18-build-system]: Package.swift updated to macOS 14 minimum and products array declaring DesignRulerCore library
- [Phase 18-build-system 18-02]: xcodegen info.properties injects LSUIElement into generated plist (not standalone pre-written plist)
- [Phase 18-build-system 18-02]: CODE_SIGN_IDENTITY="-" for Debug (ad-hoc, no Apple Developer account required for local builds)
- [Phase 19-app-lifecycle-refactor]: open class (not final) for coordinator subclasses in DesignRulerCore — required for cross-module subclassing from library target
- [Phase 19-app-lifecycle-refactor]: GuideLineStyle is package type — currentStyle on AlignmentGuidesCoordinator must be package private(set) not public private(set)
- [Phase 19-app-lifecycle-refactor]: Foundation import required in @raycast files — macro expands to NSObject/JSONDecoder references, import AppKit alone is insufficient for thin wrappers
- [Phase 20-menu-bar-shell 20-01]: MenuBarController uses callbacks (onMeasure/onAlignmentGuides) wired by AppDelegate — decoupled from coordinator types
- [Phase 20-menu-bar-shell 20-01]: anySessionActive guard in launch actions checked BEFORE setActive(true) to prevent stuck filled icon on rejected double-launches
- [Phase 20-menu-bar-shell 20-01]: onSessionEnd fires last in handleExit() and on permission abort in standalone run() early return
- [Phase 21-settings-and-preferences 21-01]: AppPreferences uses computed properties over UserDefaults (not @AppStorage) for cross-context access from AppKit and SwiftUI
- [Phase 21-settings-and-preferences 21-01]: Launch at Login toggle reads SMAppService.mainApp.status directly (not UserDefaults) to stay in sync with System Settings
- [Phase 21-settings-and-preferences 21-01]: First-launch auto-registers login item since app distributes outside App Store
- [Phase 21-settings-and-preferences 21-02]: SPUStandardUpdaterController initialized as inline let (starts updater at launch — see 21-03 for deferred fix)
- [Phase 21-settings-and-preferences 21-02]: SPUUpdater passed through SettingsWindowController to SettingsView (dependency injection, not global access)
- [Phase 21-settings-and-preferences 21-02]: Placeholder SUFeedURL and SUPublicEDKey in Info.plist (real values in Phase 24)
- [Phase 21-settings-and-preferences 21-03]: @State + .onAppear over Binding(get:set:) for SMAppService status — SwiftUI cannot observe SMAppService directly
- [Phase 21-settings-and-preferences 21-03]: startingUpdater: false defers EdDSA key validation — Phase 24 will set real keys and re-enable
- [Phase 22-global-hotkeys 22-01]: onKeyUp (not onKeyDown) for hotkey handlers — prevents key-repeat re-triggering
- [Phase 22-global-hotkeys 22-01]: DispatchQueue.main.async between cross-command exit and relaunch for autorelease pool drainage
- [Phase 22-global-hotkeys 22-01]: MainActor.assumeIsolated for setShortcut(for:) in MenuBarController — Swift 6 toolchain strict isolation
- [Phase 22-global-hotkeys 22-02]: Recorders placed inline in each command's section (not a separate Shortcuts tab)
- [Phase 22-global-hotkeys 22-02]: Conflict detection via onChange closure comparing against other command's shortcut, rejecting with setShortcut(nil)
- [Phase 22-global-hotkeys 22-02]: No keycap-style rendering for shortcuts (deferred per user decisions)

### Research Flags (from SUMMARY.md)

- Phase 18: Verify exact set of files with @raycast entry points before moving files
- Phase 22: RESOLVED — KeyboardShortcuts uses Carbon Event Manager, not CGEventTap. Library manages its own registration lifecycle.
- Phase 24: Sparkle 2.8.1 XPC service config — verify binaryTarget SPM pattern and EdDSA key setup

### Pending Todos

None.

### Blockers/Concerns

- Raycast extension detection path (LOW confidence): `~/Library/Application Support/com.raycast.macos/extensions/` is inferred, not documented. Implement as best-effort heuristic in Phase 23.

## Session Continuity

Last session: 2026-02-19
Stopped at: Completed 22-02-PLAN.md (Settings shortcut recorder UI with inline recorders and internal conflict detection)
Resume: Phase 22 complete. Next: Phase 23 (Raycast Detection) or Phase 24 (Distribution)
