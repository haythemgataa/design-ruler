# Roadmap: Design Ruler

## Milestones

- ✅ **v1.0 Enhancement** — Phases 1-5 (shipped 2026-02-13)
- ✅ **v1.1 Hint Bar Redesign** — Phases 6-8 (shipped 2026-02-14)
- ✅ **v1.2 Alignment Guides** — Phases 9-11 (shipped 2026-02-16)
- ✅ **v1.3 Code Unification** — Phases 12-17 (shipped 2026-02-17)
- 📋 **v2.0 Standalone App** — Phases 18-24 (planned)

## Phases

<details>
<summary>✅ v1.0 Enhancement (Phases 1-5) — SHIPPED 2026-02-13</summary>

- [x] Phase 1: Debug Cleanup and Process Safety (1/1 plans) — completed 2026-02-13
- [x] Phase 2: Cursor State Machine (1/1 plans) — completed 2026-02-13
- [x] Phase 3: Snap Failure Shake (1/1 plans) — completed 2026-02-13
- [x] Phase 4: Selection Pill Clamping (1/1 plans) — completed 2026-02-13
- [x] Phase 5: Help Toggle System (1/1 plans) — completed 2026-02-13

</details>

<details>
<summary>✅ v1.1 Hint Bar Redesign (Phases 6-8) — SHIPPED 2026-02-14</summary>

- [x] Phase 6: Remove Help Toggle System (1/1 plans) — completed 2026-02-14
- [x] Phase 7: Hint Bar Visual Redesign (2/2 plans) — completed 2026-02-14
- [x] Phase 8: Launch-to-Collapse Animation (1/1 plans) — completed 2026-02-14

</details>

<details>
<summary>✅ v1.2 Alignment Guides (Phases 9-11) — SHIPPED 2026-02-16</summary>

- [x] Phase 9: Scaffold + Preview Line + Placement (1/1 plans) — completed 2026-02-16
- [x] Phase 10: Remove Interaction + Color System (2/2 plans) — completed 2026-02-16
- [x] Phase 11: Hint Bar + Multi-Monitor + Polish (6/6 plans) — completed 2026-02-16

</details>

<details>
<summary>✅ v1.3 Code Unification (Phases 12-17) — SHIPPED 2026-02-17</summary>

- [x] Phase 12: Leaf Utilities (2/2 plans) — completed 2026-02-16
- [x] Phase 13: Rendering Unification (2/2 plans) — completed 2026-02-16
- [x] Phase 14: Coordinator Base (2/2 plans) — completed 2026-02-17
- [x] Phase 15: Window Base + Cursor (2/2 plans) — completed 2026-02-17
- [x] Phase 16: Final Cleanup (1/1 plan) — completed 2026-02-17
- [x] Phase 17: Unified cursor manager fixes (1/1 plan) — completed 2026-02-17

</details>

### 📋 v2.0 Standalone App (Planned)

**Milestone Goal:** Design Ruler available as a standalone macOS menu bar app with global hotkeys, settings, and DMG distribution — while keeping full Raycast extension support.

- [x] **Phase 18: Build System** - Extract DesignRulerCore library, create Xcode project, verify Raycast build still passes (completed 2026-02-18)
- [x] **Phase 19: App Lifecycle Refactor** - Add RunMode to OverlayCoordinator so overlay sessions end without killing the process (2 plans) (completed 2026-02-18)
- [x] **Phase 20: Menu Bar Shell** - NSStatusItem with dropdown launching both overlay commands from a persistent app (completed 2026-02-18)
- [x] **Phase 21: Settings and Preferences** - Settings window with General, Measure, Shortcuts, About sections wired to UserDefaults + Sparkle (3 plans) (completed 2026-02-19)
- [ ] **Phase 22: Global Hotkeys** - Configurable global keyboard shortcuts triggering overlays from any application
- [ ] **Phase 23: Coexistence** - One-time nudge when Raycast extension is also installed
- [ ] **Phase 24: Distribution** - Code-signed, notarized DMG with GitHub Actions CI pipeline

## Phase Details

### Phase 18: Build System
**Goal**: Shared Swift overlay code compiles as a library that both the Raycast extension and the Xcode app target can reference, with Raycast build verified unchanged
**Depends on**: Phase 17
**Requirements**: BUILD-01, BUILD-02, BUILD-03
**Success Criteria** (what must be TRUE):
  1. `DesignRulerCore` library target exists in Package.swift and contains all existing overlay/detection/rendering Swift files
  2. `ray build` completes without errors after the SPM source restructure (Raycast build path unchanged)
  3. Xcode project builds and produces a runnable `.app` binary referencing DesignRulerCore as a local package
**Plans**: 2 plans
  - [ ] 18-01-PLAN.md — Restructure SPM sources into DesignRulerCore library + RaycastBridge executable, verify Raycast build
  - [ ] 18-02-PLAN.md — Create Xcode app project with xcodegen, verify xcodebuild

### Phase 19: App Lifecycle Refactor
**Goal**: OverlayCoordinator can be invoked from a persistent app without starting or killing the event loop, and cursor state is clean at the start of every session
**Depends on**: Phase 18
**Requirements**: LIFE-01, LIFE-02, LIFE-03
**Success Criteria** (what must be TRUE):
  1. Invoke Measure from AppDelegate, press ESC — the app process remains alive (menu bar icon still visible)
  2. Invoke Measure a second time immediately after ESC — second session launches with no cursor glitch or residual state from the first
  3. Raycast extension behavior is unchanged: pressing ESC still terminates the Raycast process as before
**Plans**: 2 plans
  - [ ] 19-01-PLAN.md -- Add RunMode enum, session guard, and gated lifecycle to OverlayCoordinator
  - [ ] 19-02-PLAN.md -- Move coordinator subclasses to DesignRulerCore, wire AppDelegate for standalone mode

### Phase 20: Menu Bar Shell
**Goal**: User can reach both overlay commands via a menu bar icon in a persistent app that survives ESC
**Depends on**: Phase 19
**Requirements**: MENU-01, MENU-02, MENU-03, MENU-04
**Success Criteria** (what must be TRUE):
  1. App shows an NSStatusItem icon in the menu bar immediately on launch (no Dock icon, no Cmd+Tab entry)
  2. Clicking the menu bar icon reveals a dropdown containing Measure and Alignment Guides items
  3. Clicking Measure or Alignment Guides in the dropdown launches the corresponding fullscreen overlay
  4. Menu bar icon visually distinguishes the active-overlay state from the idle state
**Plans**: 1 plan
  - [ ] 20-01-PLAN.md -- MenuBarController + AppDelegate cleanup + onSessionEnd hook + Xcode project update

### Phase 21: Settings and Preferences
**Goal**: User can configure all overlay preferences, launch at login, and access About information through a persistent settings window
**Depends on**: Phase 20
**Requirements**: SETT-01, SETT-02, SETT-03, SETT-05, SETT-06, SETT-07
**Success Criteria** (what must be TRUE):
  1. User can open a Settings window from the menu bar dropdown and it persists across multiple openings
  2. Changing hideHintBar or corrections mode in Settings takes effect on the next overlay session (preferences survive app restart)
  3. Enabling Launch at Login registers the app in System Settings Login Items; disabling removes it
  4. User can view the About window (app name, version, copyright) from the menu bar
  5. User can trigger an update check via Sparkle from the menu bar (Check for Updates item present)
**Plans**: 3 plans
Plans:
- [ ] 21-01-PLAN.md -- Settings window (AppPreferences + SettingsView + SettingsWindowController) with preferences wiring and first-launch login
- [ ] 21-02-PLAN.md -- Sparkle 2 integration (SPM dependency, Info.plist keys, Check for Updates in menu + settings, auto-check toggle)
- [ ] 21-03-PLAN.md -- UAT gap closure: fix Launch at Login toggle desync and Sparkle updater startup failure

### Phase 22: Global Hotkeys
**Goal**: User can trigger both overlay commands via configurable global keyboard shortcuts from any application
**Depends on**: Phase 21
**Requirements**: HOTK-01, HOTK-02, HOTK-03, SETT-04
**Success Criteria** (what must be TRUE):
  1. App ships with no pre-assigned hotkeys — the Shortcuts tab in Settings shows both bindings as unassigned on first launch
  2. User can record a custom keyboard shortcut for Measure in the Settings Shortcuts tab using a recorder control
  3. User can record a custom keyboard shortcut for Alignment Guides in the Settings Shortcuts tab using a recorder control
  4. Pressing an assigned hotkey while focused on Figma (or any other app) launches the corresponding overlay
**Plans**: 2 plans
Plans:
- [ ] 22-01-PLAN.md -- Add KeyboardShortcuts dependency, HotkeyNames, HotkeyController, wire AppDelegate + menu item shortcut display
- [ ] 22-02-PLAN.md -- Replace Shortcuts placeholder with recorder controls in Measure/Alignment Guides sections, internal conflict detection

### Phase 23: Coexistence
**Goal**: User who has both the standalone app and the Raycast extension installed sees a one-time recommendation to keep only one
**Depends on**: Phase 20
**Requirements**: COEX-01, COEX-02
**Success Criteria** (what must be TRUE):
  1. App detects when the Design Ruler Raycast extension is also installed and alerts the user on first detection
  2. The alert appears only once — subsequent launches with the extension still installed do not repeat the nudge
**Plans**: TBD

### Phase 24: Distribution
**Goal**: Anyone can download a notarized DMG from GitHub releases and run Design Ruler without a Gatekeeper warning
**Depends on**: Phase 23
**Requirements**: DIST-01, DIST-02, DIST-03, DIST-04
**Success Criteria** (what must be TRUE):
  1. `codesign --verify --deep --strict` passes on the built `.app` bundle
  2. `spctl --assess --type execute` passes on a clean machine that never ran the app before (Gatekeeper approves)
  3. DMG opens to reveal the app with a shortcut to /Applications for drag-install
  4. Pushing a version tag triggers the GitHub Actions workflow which produces a signed, notarized DMG as a release asset without manual intervention
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Debug Cleanup and Process Safety | v1.0 | 1/1 | Complete | 2026-02-13 |
| 2. Cursor State Machine | v1.0 | 1/1 | Complete | 2026-02-13 |
| 3. Snap Failure Shake | v1.0 | 1/1 | Complete | 2026-02-13 |
| 4. Selection Pill Clamping | v1.0 | 1/1 | Complete | 2026-02-13 |
| 5. Help Toggle System | v1.0 | 1/1 | Complete | 2026-02-13 |
| 6. Remove Help Toggle System | v1.1 | 1/1 | Complete | 2026-02-14 |
| 7. Hint Bar Visual Redesign | v1.1 | 2/2 | Complete | 2026-02-14 |
| 8. Launch-to-Collapse Animation | v1.1 | 1/1 | Complete | 2026-02-14 |
| 9. Scaffold + Preview Line + Placement | v1.2 | 1/1 | Complete | 2026-02-16 |
| 10. Remove Interaction + Color System | v1.2 | 2/2 | Complete | 2026-02-16 |
| 11. Hint Bar + Multi-Monitor + Polish | v1.2 | 6/6 | Complete | 2026-02-16 |
| 12. Leaf Utilities | v1.3 | 2/2 | Complete | 2026-02-16 |
| 13. Rendering Unification | v1.3 | 2/2 | Complete | 2026-02-16 |
| 14. Coordinator Base | v1.3 | 2/2 | Complete | 2026-02-17 |
| 15. Window Base + Cursor | v1.3 | 2/2 | Complete | 2026-02-17 |
| 16. Final Cleanup | v1.3 | 1/1 | Complete | 2026-02-17 |
| 17. Unified cursor manager fixes | v1.3 | 1/1 | Complete | 2026-02-17 |
| 18. Build System | v2.0 | Complete    | 2026-02-18 | - |
| 19. App Lifecycle Refactor | v2.0 | Complete    | 2026-02-18 | - |
| 20. Menu Bar Shell | v2.0 | Complete    | 2026-02-18 | - |
| 21. Settings and Preferences | v2.0 | Complete    | 2026-02-19 | - |
| 22. Global Hotkeys | v2.0 | 0/TBD | Not started | - |
| 23. Coexistence | v2.0 | 0/TBD | Not started | - |
| 24. Distribution | v2.0 | 0/TBD | Not started | - |
