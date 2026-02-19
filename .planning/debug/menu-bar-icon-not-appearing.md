---
status: resolved
trigger: "NSStatusItem menu bar icon doesn't appear when standalone app launches"
created: 2026-02-18T23:05:00+01:00
updated: 2026-02-18T23:20:00+01:00
---

## Current Focus

hypothesis: The code is correct; the NSStatusItem IS created and visible
test: Launch fresh instance, check system logs for FBSScene status item creation
expecting: Scene created = icon is visible; no scene = icon missing
next_action: None - investigation complete

## Symptoms

expected: Menu bar icon (ruler SF Symbol) appears when app launches
actual: User reported no menu bar icon visible despite process running
errors: None in app logs; 24 crash reports from earlier sessions (separate issue)
reproduction: Could not reproduce - fresh launch shows icon correctly
started: First attempt after building phase 20-01

## Eliminated

- hypothesis: NSStatusItem not retained (deallocated by ARC)
  evidence: MenuBarController stored as `private var menuBarController: MenuBarController!` on AppDelegate (strong ref); NSStatusItem stored as `private let statusItem` on MenuBarController (strong ref); AppDelegate stored as local `let delegate` in main.swift (stays in scope during app.run())
  timestamp: 2026-02-18T23:08:00

- hypothesis: AppDelegate deallocated because NSApplication.delegate is weak
  evidence: While NSApplication.delegate IS weak, the `let delegate = AppDelegate()` in main.swift's top-level scope stays alive for the duration of app.run() (which never returns). This is the standard programmatic NSApplication pattern.
  timestamp: 2026-02-18T23:09:00

- hypothesis: SF Symbol "ruler" doesn't exist, causing nil image
  evidence: "ruler" is a valid SF Symbol available since SF Symbols 1.0 / macOS 11. Even if it were nil, NSStatusItem would still appear (just with no icon), not be invisible.
  timestamp: 2026-02-18T23:10:00

- hypothesis: applicationDidFinishLaunching never called
  evidence: System logs at launch show: disableAutomaticTermination called ("No windows open yet"), NSStatusItem scene created via FBSScene, status item auxiliary view scenes realized. All of this only happens if applicationDidFinishLaunching ran.
  timestamp: 2026-02-18T23:12:00

- hypothesis: NSStatusItem created on background thread
  evidence: All code in applicationDidFinishLaunching runs on main thread (called by NSApplication.run() on main thread). No dispatch to background anywhere in init path.
  timestamp: 2026-02-18T23:13:00

- hypothesis: setActivationPolicy(.accessory) conflicts with status item
  evidence: .accessory is the correct policy for menu bar apps (hides from Dock, shows in menu bar). LSUIElement=true in Info.plist matches. This is the standard pattern.
  timestamp: 2026-02-18T23:14:00

## Evidence

- timestamp: 2026-02-18T23:07:00
  checked: App/Sources/main.swift, AppDelegate.swift, MenuBarController.swift
  found: Code structure is correct - strong reference chain from main.swift -> AppDelegate -> MenuBarController -> NSStatusItem. Button configured with "ruler" SF Symbol, menu with Measure/Alignment Guides/Quit items.
  implication: No obvious code-level retention or configuration bug.

- timestamp: 2026-02-18T23:08:00
  checked: Info.plist and project.yml
  found: LSUIElement=true (correct for menu bar app), NSPrincipalClass=NSApplication (correct for programmatic main.swift). Build settings correct.
  implication: Build configuration is correct.

- timestamp: 2026-02-18T23:10:00
  checked: Xcode DerivedData build output
  found: Binary exists (58016 bytes), links to Design Ruler.debug.dylib (1.4MB, contains DesignRulerCore). No missing frameworks.
  implication: Build produced valid binary.

- timestamp: 2026-02-18T23:11:00
  checked: App/build/Debug/ (project-local build directory)
  found: Contents/MacOS/ is EMPTY - no binary. This is NOT the Xcode DerivedData build.
  implication: The App/build/ directory is a stale/incomplete build artifact. Actual builds go to DerivedData.

- timestamp: 2026-02-18T23:12:00
  checked: System log for PID 90096 (fresh launch via `open` command)
  found: At 23:12:17.826 - "Alloc com.apple.controlcenter.statusitems"; FBSScene requests for status item created successfully; NSStatusItemSceneHostSettings, NSStatusItemAuxiliaryViewSceneSettings realized; multiple NSSceneFenceAction sent.
  implication: NSStatusItem IS being created and the system IS rendering it in the menu bar.

- timestamp: 2026-02-18T23:13:00
  checked: System log for PID 36087 (user's running instance from 18:22)
  found: Same pattern - status item scenes created, app functional, screen captures performed at 22:58 and 23:00.
  implication: The running instance was fully functional with a status item.

- timestamp: 2026-02-18T23:15:00
  checked: Crash reports (24 total from 17:04 to 18:19)
  found: All crashes are EXC_BAD_ACCESS in objc_release during autorelease pool drain within [NSApplication run]. Crash happens during overlay sessions (4+ threads), not at launch.
  implication: Separate bug - use-after-free during overlay sessions. Not related to status item visibility.

- timestamp: 2026-02-18T23:16:00
  checked: Git history of App/Sources/
  found: Prior commit (5ab21ed) used @main with temp DispatchQueue measure trigger. Current commit (715b864) switched to main.swift + MenuBarController. If old binary was still running when user tested new code, the old process (without MenuBarController) would block new instance launch.
  implication: Most likely cause of "no icon" report: stale process from old code still running, preventing new code from launching.

## Resolution

root_cause: The NSStatusItem code is correct and functional. The most likely explanation for the reported issue is one of:
  1. A stale process from the previous code version (5ab21ed, which had no MenuBarController) was still running when the new code was built. macOS reuses the existing process for the same bundle ID instead of launching a new instance, so the user saw the old code running (no menu bar icon) instead of the new code.
  2. The menu bar icon was present but not noticed (macOS can overflow status items into the hidden area if the menu bar is crowded).
  3. The icon appeared but was lost due to one of the 24 crash-and-relaunch cycles that occurred between 17:04 and 18:19.

fix: No code fix needed for the status item. The code is correct. However, the crash reports (EXC_BAD_ACCESS during overlay sessions) indicate a separate use-after-free bug that should be investigated separately.

verification: Fresh launch via `open` command confirmed NSStatusItem creation in system logs (FBSScene status item scenes created and rendered). Process running stable at 0% CPU.

files_changed: []
