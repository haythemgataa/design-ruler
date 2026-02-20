# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-18)

**Core value:** Instant, accurate pixel inspection of anything on screen — zero friction from invoke to dimension readout, whether launched from Raycast or a global hotkey.
**Current focus:** v2.0 Standalone App — Phase 23: Distribution

## Current Position

Phase: 23 of 23 (Distribution)
Plan: 3 of 3 complete in current phase
Status: Phase 23 complete — all plans executed (signing config + CI pipeline + user credential setup)
Last activity: 2026-02-20 — Completed 23-03: User credential setup (real EdDSA key, GitHub Secrets, correct repo URL)

Progress: [######░░░░] 57% (v2.0 — 4/7 phases complete, Phase 23 done)

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
| 22-global-hotkeys | 03 | 1min 40s | 2 | 2 |
| 23-distribution | 01 | 3min 59s | 2 | 5 |
| 23-distribution | 02 | 2min 56s | 2 | 4 |
| 23-distribution | 03 | user-driven | 2 | 2 |

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
- [Phase 22-global-hotkeys 22-03]: Guard else-branch on newShortcut != nil to survive onChange double-fire from setShortcut(nil) rejection
- [Phase 22-global-hotkeys 22-03]: NSMenuDelegate with menuNeedsUpdate for defensive shortcut refresh on every menu open
- [Phase 22-global-hotkeys 22-03]: menuWillOpen/menuDidClose disable/enable hotkeys during NSMenu tracking mode
- [Phase 23-distribution 23-01]: Empty entitlements dict — CGWindowListCreateImage/CGEventTap governed by TCC, not entitlements
- [Phase 23-distribution 23-01]: DEVELOPMENT_TEAM uses $(DEVELOPMENT_TEAM) build setting variable — CI passes via xcodebuild override
- [Phase 23-distribution 23-01]: Re-enabled Sparkle updater (startingUpdater: true) — real EdDSA key expected before distribution
- [Phase 23-distribution 23-02]: Two-workflow CI architecture — build on tag-push, appcast on release-publish
- [Phase 23-distribution 23-02]: EdDSA key piped via stdin in CI (never written to disk)
- [Phase 23-distribution 23-02]: create-dmg || true for exit code 2 warnings, with post-check for DMG existence
- [Phase 23-distribution 23-02]: Single-item appcast sufficient for stable-channel-only v1 pipeline
- [Phase 23-distribution 23-03]: Real EdDSA public key set by user (not placeholder)
- [Phase 23-distribution 23-03]: SUFeedURL corrected to haythemgataa/design-ruler (matching actual GitHub remote)

### Research Flags (from SUMMARY.md)

- Phase 18: Verify exact set of files with @raycast entry points before moving files
- Phase 22: RESOLVED — KeyboardShortcuts uses Carbon Event Manager, not CGEventTap. Library manages its own registration lifecycle.
- Phase 24: Sparkle 2.8.1 XPC service config — verify binaryTarget SPM pattern and EdDSA key setup

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 23-03-PLAN.md (User credential setup: real EdDSA key, GitHub Secrets, correct repo URL)
Resume: Phase 23 fully complete (all 3 plans). Next: Phase verification
