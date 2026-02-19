---
phase: 21-settings-and-preferences
verified: 2026-02-19T06:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification:
  previous_status: passed
  previous_score: 5/5
  gaps_closed:
    - "Launch at Login toggle reflects actual SMAppService status on Settings reopen (UAT gap 5)"
    - "Sparkle updater does not show error dialog on launch with placeholder keys (UAT gap 7)"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Toggle Launch at Login ON in Settings, open System Settings > General > Login Items, verify Design Ruler appears"
    expected: "App appears in Login Items. Toggle OFF removes it. Reopening Settings shows correct toggle state (OnAppear refreshes from SMAppService)."
    why_human: "SMAppService.mainApp.register() outcome and System Settings sync require live system check"
  - test: "Click Check for Updates... in the menu bar dropdown"
    expected: "With startingUpdater: false and placeholder keys, Sparkle should not crash or show an error dialog on launch. The menu item is present and wired. Actual update check behavior deferred to Phase 24 when real keys are configured."
    why_human: "Sparkle network behavior and UI presentation require runtime observation"
  - test: "Change corrections mode to None in Settings, launch Measure overlay, observe edge detection"
    expected: "No smart border corrections applied. Raw edge positions reported."
    why_human: "Requires visual inspection of overlay behavior"
---

# Phase 21: Settings and Preferences Verification Report

**Phase Goal:** User can configure all overlay preferences, launch at login, and access About information through a persistent settings window
**Verified:** 2026-02-19T06:00:00Z
**Status:** passed
**Re-verification:** Yes — after gap closure (21-03 plan fixed two UAT-blocking bugs)

## Re-Verification Summary

Previous VERIFICATION.md (status: passed) preceded UAT testing. UAT found two major issues:
- Launch at Login toggle desync on Settings window reopen (UAT test 5, severity: major)
- Sparkle updater error dialog on app launch with placeholder EdDSA key (UAT test 7, severity: major)

Plan 21-03 closed both gaps. This re-verification confirms fixes are present in the actual code.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can open a Settings window from the menu bar dropdown and it persists across multiple openings | VERIFIED | `MenuBarController.swift:59-64` Settings item with `keyEquivalent: ","` and `target: self`; `SettingsWindowController.swift:9-20` three-branch reuse logic (`isVisible` fast path, hidden-window re-center path, new-window creation); `isReleasedWhenClosed = false` ensures persistence |
| 2 | Changing hideHintBar or corrections in Settings takes effect on the next overlay session (preferences survive app restart) | VERIFIED | `SettingsView.swift:35-37,53-55` writes to `UserDefaults.standard` on `onChange`; `AppPreferences.swift:7-15` reads `UserDefaults.standard` at access time; `AppDelegate.swift:37-41` reads `AppPreferences.shared` inside closures at invocation time (not captured at launch) |
| 3 | Enabling Launch at Login registers the app in System Settings Login Items; disabling removes it | VERIFIED | `SettingsView.swift:8,15,25-31` uses `@State private var launchAtLogin` initialized from `SMAppService.mainApp.status == .enabled`; `onChange` calls `SMAppService.mainApp.register()` / `.unregister()`; `.onAppear` at line 94-96 re-syncs state every time the window appears (fixes UAT gap 5) |
| 4 | User can view the About window (app name, version, copyright) from the menu bar | VERIFIED | `SettingsView.swift:66-91` About section renders "Design Ruler" title, `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`, copyright 2025, GitHub link — reachable from Settings item in menu bar |
| 5 | User can trigger an update check via Sparkle from the menu bar (Check for Updates item present) | VERIFIED | `MenuBarController.swift:66-71` "Check for Updates..." item with `target: self`; `AppDelegate.swift:43-45` wires `onCheckForUpdates` to `updaterController.checkForUpdates(nil)`; `startingUpdater: false` prevents launch error (fixes UAT gap 7) |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `App/Sources/AppPreferences.swift` | UserDefaults-backed preferences singleton | VERIFIED | 16 lines; `@Observable` singleton; `hideHintBar` and `corrections` computed properties over `UserDefaults.standard` |
| `App/Sources/SettingsView.swift` | SwiftUI Form with General, Measure, Shortcuts, About sections | VERIFIED | 100 lines; four `Section` blocks; `@State`-backed all toggle/picker state; `formStyle(.grouped)`; `.onAppear` refreshes Launch at Login state |
| `App/Sources/SettingsWindowController.swift` | NSWindow lifecycle (create, show, center, reuse) | VERIFIED | 42 lines; three-branch `showSettings()` — visible/hidden/new; `isReleasedWhenClosed = false`; `updateConstraintsIfNeeded()` before `center()` |
| `App/Sources/MenuBarController.swift` | Settings + Check for Updates items in menu | VERIFIED | Settings item `keyEquivalent: ","` at line 59-64; Check for Updates item at line 66-71; both wired via ObjC selectors to `onOpenSettings?()` and `onCheckForUpdates?()` callbacks |
| `App/Sources/AppDelegate.swift` | Sparkle init deferred, preferences read at invocation time | VERIFIED | `SPUStandardUpdaterController(startingUpdater: false, ...)` at lines 9-13; `AppPreferences.shared` read inside closures at lines 37-41; all four callbacks wired |
| `App/project.yml` | Sparkle SPM package dependency | VERIFIED | `url: https://github.com/sparkle-project/Sparkle`, `from: "2.6.0"` at lines 10-12 |
| `App/Sources/Info.plist` | SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks keys | VERIFIED | All three keys present; `SUPublicEDKey` is intentional placeholder — Phase 24 will set real keys; `startingUpdater: false` prevents validation error until then |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `AppDelegate.swift` | `AppPreferences.swift` | Reads `AppPreferences.shared` inside overlay closures at invocation time | WIRED | Line 37: `let prefs = AppPreferences.shared` inside `onMeasure` closure; line 41: `AppPreferences.shared.hideHintBar` inside `onAlignmentGuides` closure — not captured at launch |
| `MenuBarController.swift` | `SettingsWindowController` | `onOpenSettings` callback chain | WIRED | Line 11 declares `onOpenSettings`; line 98 calls `onOpenSettings?()`; `AppDelegate.swift:46-49` wires `settingsWindowController.showSettings(updater: ...)` |
| `SettingsView.swift` | `UserDefaults` | `onChange` handlers on toggle/picker | WIRED | Line 36: `UserDefaults.standard.set(newValue, forKey: "hideHintBar")`; line 54: `UserDefaults.standard.set(newValue, forKey: "corrections")` |
| `AppDelegate.swift` | Sparkle framework | `SPUStandardUpdaterController` with `startingUpdater: false` | WIRED | Lines 9-13: init with deferred start; line 44: `updaterController.checkForUpdates(nil)` |
| `MenuBarController.swift` | `AppDelegate.swift` | `onCheckForUpdates` callback | WIRED | Line 12 declares `onCheckForUpdates`; line 102 calls `onCheckForUpdates?()`; `AppDelegate.swift:43-45` wires it |
| `SettingsView.swift` | `SPUUpdater` | `updater.automaticallyChecksForUpdates` and `updater.checkForUpdates()` | WIRED | Line 41: `updater.automaticallyChecksForUpdates = newValue`; line 89: `updater.checkForUpdates()` |
| `SettingsView.swift` | `SMAppService` | `@State + .onAppear` refresh | WIRED | Lines 94-96: `.onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }`; `onChange` calls `register()`/`unregister()` |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| Settings window persists across multiple openings | SATISFIED | — |
| Preferences survive app restart (stored in UserDefaults) | SATISFIED | — |
| Launch at Login registers/removes via SMAppService | SATISFIED | — |
| Launch at Login toggle syncs with actual system state on reopen | SATISFIED | Fixed in 21-03: @State + .onAppear |
| First-launch auto-enables launch at login | SATISFIED | `AppDelegate.swift:26-29` |
| About section shows app name, version, copyright | SATISFIED | — |
| Check for Updates present in menu bar | SATISFIED | — |
| Sparkle does not error on launch with placeholder keys | SATISFIED | Fixed in 21-03: startingUpdater: false |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `App/Sources/SettingsView.swift` | 58-63 | `// --- Shortcuts (placeholder for Phase 22) ---` | Info | Intentional deferral; section renders informational text "Shortcuts will be available in a future update." — does not break any Phase 21 goal |
| `App/Sources/Info.plist` | 34 | `SUPublicEDKey: PLACEHOLDER_EDDSA_PUBLIC_KEY` | Info | Intentional placeholder; guarded by `startingUpdater: false` which prevents Sparkle validating keys at launch. Phase 24 will set real keys. |

No blockers. No warnings. Both anti-patterns are documented intentional deferrals.

### Build Verification

App builds successfully with `xcodebuild -project "Design Ruler.xcodeproj" -scheme "Design Ruler" -configuration Debug build` — confirmed `** BUILD SUCCEEDED **`.

### Confirmed Fix Commits

Both UAT gap closure commits verified in git log:
- `b032624` — fix(21-03): fix Launch at Login toggle desync on Settings reopen
- `24de60f` — fix(21-03): defer Sparkle updater startup to prevent launch error dialog

### Human Verification Required

#### 1. Launch at Login System Sync

**Test:** Toggle "Launch at Login" ON in Settings. Open System Settings > General > Login Items. Verify Design Ruler appears. Toggle OFF. Verify it disappears. Close Settings. Reopen Settings. Verify toggle reflects current state.
**Expected:** Toggle and Login Items stay in sync. Reopening Settings shows correct state (`.onAppear` refreshes from `SMAppService.mainApp.status`).
**Why human:** `SMAppService.mainApp.register()` outcome and macOS Login Items UI require live system verification.

#### 2. Sparkle Menu Item Behavior

**Test:** Click "Check for Updates..." in the menu bar dropdown.
**Expected:** No crash, no error dialog. With `startingUpdater: false` and placeholder keys, Sparkle either shows a "no updates available" message or a graceful failure — not the launch-time error dialog that was previously reported.
**Why human:** Sparkle UI behavior requires runtime observation; network interaction cannot be verified statically.

#### 3. Preferences Applied on Next Session

**Test:** Change "Border Corrections" to "None" in Settings. Close Settings. Launch Measure overlay. Move cursor to a 1px border element.
**Expected:** Edge detection uses no corrections. Raw edge position returned.
**Why human:** Requires visual inspection of overlay behavior.

## Gaps Summary

No gaps. All five success criteria from the Phase 21 roadmap are verified in the actual codebase.

The two UAT-blocking issues (Launch at Login desync, Sparkle error dialog) were fixed by Plan 21-03 and are confirmed present in the current code at commits `b032624` and `24de60f`.

Three human verification items remain — these are expected for phases integrating system APIs (SMAppService, Sparkle) and cannot be verified by static analysis alone. They do not indicate code gaps.

---

_Verified: 2026-02-19T06:00:00Z_
_Verifier: Claude (gsd-verifier)_
