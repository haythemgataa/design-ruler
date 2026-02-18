---
phase: 20-menu-bar-shell
plan: 01
subsystem: App Shell / Overlay Lifecycle
tags: [menu-bar, NSStatusItem, onSessionEnd, cleanup, AppDelegate]
dependency_graph:
  requires:
    - 19-app-lifecycle-refactor/19-02 (MeasureCoordinator + AlignmentGuidesCoordinator in DesignRulerCore)
  provides:
    - NSStatusItem menu bar icon with overlay launch dropdown
    - onSessionEnd callback for icon state revert
    - Clean production AppDelegate with no test scaffolding
  affects:
    - OverlayCoordinator (all exit paths now fire onSessionEnd)
    - Both coordinator subclasses (onSessionEnd wired in AppDelegate)
tech_stack:
  added: []
  patterns:
    - NSStatusItem with stored property (ARC retention)
    - Callback-based decoupling (MenuBarController has no coordinator imports)
    - anySessionActive guard before setActive(true) prevents stuck icon
    - onSessionEnd fires last in handleExit() and on permission abort
key_files:
  created:
    - App/Sources/MenuBarController.swift
  modified:
    - swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift
    - App/Sources/AppDelegate.swift
    - App/Sources/main.swift
    - App/Design Ruler.xcodeproj/project.pbxproj
decisions:
  - "MenuBarController uses callbacks (onMeasure/onAlignmentGuides) wired by AppDelegate — keeps controller decoupled from coordinator types"
  - "setActive(_:) dispatches to main thread — coordinator onSessionEnd may fire from non-main context"
  - "onSessionEnd placed as LAST statement in handleExit() so icon reverts after all cleanup completes"
  - "anySessionActive guard in launchMeasure/launchAlignmentGuides checked BEFORE setActive(true) to prevent stuck filled icon on rejected double-launches"
metrics:
  duration: "2min 58s"
  completed: "2026-02-18"
  tasks_completed: 2
  files_changed: 5
---

# Phase 20 Plan 01: Menu Bar Shell Summary

NSStatusItem menu bar icon with Measure/Alignment Guides/Settings(disabled)/Quit dropdown, onSessionEnd callback hook in OverlayCoordinator, and removal of all Phase 19 test scaffolding and debug logging.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add onSessionEnd hook to OverlayCoordinator and remove debug logging | 12120b1 | OverlayCoordinator.swift |
| 2 | Create MenuBarController, rewrite AppDelegate, update Xcode project | 715b864 | MenuBarController.swift, AppDelegate.swift, main.swift, project.pbxproj |

## What Was Built

### MenuBarController.swift (new)
- `NSStatusItem` as a `let` stored property (ARC retention — local variables release immediately)
- `ruler` SF Symbol in template mode for adaptive dark/light mode rendering
- Dropdown menu: Measure, Alignment Guides, separator, Settings... (disabled), separator, Quit Design Ruler
- `setActive(_ active: Bool)` swaps icon to `ruler.fill` / `ruler`, dispatched to main thread
- `launchMeasure` / `launchAlignmentGuides` guard on `!OverlayCoordinator.anySessionActive` before `setActive(true)` — prevents icon getting stuck if coordinator rejects the call
- Decoupled from coordinators via `onMeasure` / `onAlignmentGuides` callbacks wired by AppDelegate

### OverlayCoordinator.swift (modified)
- Removed `drLog()` function and all 9 call sites (Phase 19 temporary debug logging)
- Added `public var onSessionEnd: (() -> Void)?` stored property
- `onSessionEnd?()` fires at the end of `handleExit()` — covers ESC, inactivity timer, SIGTERM
- `onSessionEnd?()` fires in standalone permission-abort early return in `run()` — prevents icon stuck in filled state when screen recording permission is denied

### AppDelegate.swift (rewritten)
- Removed: `logToFile` function, `asyncAfter` test launch, `applicationDidBecomeActive` re-invoke, `applicationShouldTerminate → .terminateCancel`, `applicationWillTerminate` log stub
- Added: `MenuBarController` strong property, `onMeasure`/`onAlignmentGuides` callback wiring, `onSessionEnd` wiring on both coordinators

### main.swift (cleaned)
- Removed: `logPath` declaration and `.write(toFile:)` Phase 19 debug entry write
- Result: 4-line clean entry point (import, shared, delegate, run)

### project.pbxproj (updated)
- Added MenuBarController.swift to PBXBuildFile, PBXFileReference, PBXGroup Sources, PBXSourcesBuildPhase

## Verification Results

- `xcodebuild` Debug build: **BUILD SUCCEEDED**
- `swift build` (SPM/Raycast path): **Build complete!**
- No `drLog`/`logToFile`/`fputs`/`logPath`/`write(toFile:)` in any source file
- No Phase 19 stubs (`asyncAfter`, `terminateCancel`, `applicationDidBecomeActive`) in AppDelegate
- `onSessionEnd` wired on both coordinators in AppDelegate (lines 27, 30)
- MenuBarController contains all 4 required menu items (8 matching lines)

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

All files found:
- FOUND: App/Sources/MenuBarController.swift
- FOUND: App/Sources/AppDelegate.swift
- FOUND: App/Sources/main.swift
- FOUND: swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift

All commits found:
- FOUND: 12120b1 (Task 1)
- FOUND: 715b864 (Task 2)
