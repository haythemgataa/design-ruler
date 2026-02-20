---
phase: 20-menu-bar-shell
verified: 2026-02-18T00:00:00Z
status: passed
score: 4/4 success criteria verified
re_verification:
  previous_status: passed
  previous_score: 8/8
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 20: Menu Bar Shell Verification Report

**Phase Goal:** User can reach both overlay commands via a menu bar icon in a persistent app that survives ESC
**Verified:** 2026-02-18
**Status:** passed
**Re-verification:** Yes — regression check after initial passed verification

## Goal Achievement

### Observable Truths (Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | App shows an NSStatusItem icon in the menu bar immediately on launch (no Dock icon, no Cmd+Tab entry) | VERIFIED | `MenuBarController.init()` calls `NSStatusBar.system.statusItem(withLength: .squareLength)` and sets a "ruler" SF Symbol image. `AppDelegate.applicationDidFinishLaunching` instantiates it synchronously and calls `NSApp.setActivationPolicy(.accessory)`. `Info.plist` has `LSUIElement = true`. No Dock entry or Cmd+Tab entry will appear. |
| 2 | Clicking the menu bar icon reveals a dropdown containing Measure and Alignment Guides items | VERIFIED | `setupMenu()` adds "Measure" (`action: launchMeasure`, `target: self`) and "Alignment Guides" (`action: launchAlignmentGuides`, `target: self`) as the first two items. Also includes Settings... (disabled) and Quit Design Ruler. Menu is assigned to `statusItem.menu`. |
| 3 | Clicking Measure or Alignment Guides in the dropdown launches the corresponding fullscreen overlay | VERIFIED | `launchMeasure()` fires `onMeasure?()` which `AppDelegate` wires to `MeasureCoordinator.shared.run(hideHintBar: false, corrections: "smart")`. `launchAlignmentGuides()` fires `onAlignmentGuides?()` wired to `AlignmentGuidesCoordinator.shared.run(hideHintBar: false)`. Both coordinators have `runMode = .standalone` set in `applicationDidFinishLaunching`, so ESC exits the session without terminating the process. |
| 4 | Menu bar icon visually distinguishes the active-overlay state from the idle state | VERIFIED | `setActive(true)` (called before `onMeasure?()` / `onAlignmentGuides?()`) swaps symbol to "ruler.fill". `onSessionEnd` fires at `OverlayCoordinator.handleExit()` line 235 and at the permission-abort early return (line 77), both calling `menuBarController.setActive(false)` which reverts to "ruler". Dispatch to main thread is handled via `DispatchQueue.main.async`. |

**Score:** 4/4 success criteria verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `App/Sources/MenuBarController.swift` | NSStatusItem + NSMenu lifecycle, icon state management | VERIFIED | 91 lines. `statusItem` as stored `let` (ARC retention). `setupButton()`, `setupMenu()`, `setActive(_:)` with main-thread dispatch. `launchMeasure`/`launchAlignmentGuides` with `anySessionActive` guard. `quitApp()` calls `NSApp.terminate(nil)`. |
| `App/Sources/AppDelegate.swift` | MenuBarController creation, coordinator callback wiring, runMode setup | VERIFIED | 38 lines. `menuBarController` as strong property. `runMode = .standalone` set on both coordinators. `onMeasure`/`onAlignmentGuides` and `onSessionEnd` callbacks all wired. No debug stubs. |
| `App/Sources/main.swift` | Clean 4-line app entry point | VERIFIED | Exactly 4 lines: `import AppKit`, `let app = NSApplication.shared`, `let delegate = AppDelegate()`, `app.delegate = delegate`, `app.run()`. No debug logging. |
| `App/Sources/Info.plist` | LSUIElement = true for agent-app behavior | VERIFIED | `<key>LSUIElement</key><true/>` present at line 23-24. |
| `swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift` | `onSessionEnd` callback, `runMode`, `anySessionActive` | VERIFIED | `public var onSessionEnd: (() -> Void)?` at line 46. Fires at line 235 (end of `handleExit()`). Fires at line 77 (permission-abort). `runMode` enum with `.standalone` and `.raycast` cases. `anySessionActive` static guard at line 30. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MenuBarController.launchMeasure` | `MeasureCoordinator.shared.run()` | `onMeasure` callback | WIRED | `launchMeasure()` calls `onMeasure?()`. `AppDelegate` assigns `onMeasure = { MeasureCoordinator.shared.run(...) }`. |
| `MenuBarController.launchAlignmentGuides` | `AlignmentGuidesCoordinator.shared.run()` | `onAlignmentGuides` callback | WIRED | `launchAlignmentGuides()` calls `onAlignmentGuides?()`. `AppDelegate` assigns `onAlignmentGuides = { AlignmentGuidesCoordinator.shared.run(...) }`. |
| `OverlayCoordinator.handleExit()` | `MenuBarController.setActive(false)` | `onSessionEnd` callback | WIRED | `AppDelegate` wires both coordinators' `onSessionEnd` to call `menuBarController.setActive(false)`. `handleExit()` calls `onSessionEnd?()` at line 235. |
| `OverlayCoordinator` permission-abort | `MenuBarController.setActive(false)` | `onSessionEnd` callback | WIRED | Permission-abort path (line 77) resets `isSessionActive`/`anySessionActive` then calls `onSessionEnd?()` before returning. |
| `MenuBarController.launchMeasure/launchAlignmentGuides` | `OverlayCoordinator.anySessionActive` | guard before `setActive(true)` | WIRED | Lines 77 and 83: `guard !OverlayCoordinator.anySessionActive else { return }` prevents double-launch. |

### Requirements Coverage

No REQUIREMENTS.md entries mapped to this phase.

### Anti-Patterns Found

None. Scanned all files in `App/Sources/`. Zero matches for: `TODO`, `FIXME`, `XXX`, `HACK`, `placeholder`, `drLog`, `logToFile`, `fputs`, `asyncAfter`, `terminateCancel`, `applicationDidBecomeActive`. No empty implementations or stub returns.

### Human Verification Required

#### 1. Menu Bar Icon Appears on App Launch

**Test:** Build and launch the Design Ruler app. Check the macOS menu bar.
**Expected:** A ruler SF Symbol icon appears in the menu bar immediately. No Dock icon, no Cmd+Tab entry.
**Why human:** Icon visibility and accessory policy behavior cannot be verified without running the app.

#### 2. Dropdown Reveals on Click

**Test:** Click the menu bar ruler icon.
**Expected:** Dropdown menu appears with: Measure, Alignment Guides, separator, Settings... (grayed out), separator, Quit Design Ruler.
**Why human:** NSMenu display and item enabling/disabling requires runtime verification.

#### 3. Overlay Launches and App Survives ESC

**Test:** Click Measure in the dropdown. Use the overlay. Press ESC.
**Expected:** Measure overlay launches fullscreen. After ESC, the app remains running (menu bar icon still present, no Dock icon).
**Why human:** Process survival after ESC with `runMode = .standalone` requires runtime observation.

#### 4. Icon State Change During Active Session

**Test:** Click Measure or Alignment Guides to launch an overlay. Observe the menu bar icon while the overlay is active. Press ESC. Observe the icon again.
**Expected:** Icon shows filled "ruler.fill" variant during the active session; reverts to hollow "ruler" after ESC.
**Why human:** Icon visual state change requires runtime observation.

### Gaps Summary

No gaps. Re-verification confirms all four success criteria are satisfied against the current codebase. All key links remain wired end-to-end. No regressions detected from the initial verification.

Four human verification items remain — they require a running build to confirm visual/behavioral properties that cannot be checked statically.

---

_Verified: 2026-02-18_
_Verifier: Claude (gsd-verifier)_
