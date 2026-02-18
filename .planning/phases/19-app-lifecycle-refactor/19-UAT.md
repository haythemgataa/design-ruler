---
status: complete
phase: 19-app-lifecycle-refactor
source: 19-01-SUMMARY.md, 19-02-SUMMARY.md
started: 2026-02-18T15:00:00Z
updated: 2026-02-18T17:22:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Xcode app builds successfully
expected: Run `xcodebuild build` for the DesignRuler app target. Build completes with zero errors.
result: pass

### 2. Raycast extension builds successfully
expected: Run `ray build -e swift` or `npm run dev` from the repo root. Build completes with zero errors, confirming the SPM restructure didn't break Raycast.
result: pass

### 3. Standalone app launches Measure overlay
expected: Build and run the app from Xcode. After ~0.5s delay, the Measure fullscreen overlay appears with crosshair and hint bar — launched from AppDelegate in standalone mode.
result: pass
note: Required three fixes — @main replaced with explicit main.swift bootstrap, permission check returns early in standalone mode, window creation works after permission grant

### 4. ESC keeps standalone app alive
expected: With the Measure overlay visible, press ESC. The overlay closes but the app process stays alive.
result: pass
note: Required three fixes — deferred window close to avoid autorelease pool crash (SIGSEGV), stale window retention to prevent ARC crash, disableAutomaticTermination to prevent macOS auto-cleanup. Xcode debugger interferes with ESC; works correctly when running binary directly via `open`.

### 5. Second session launches cleanly
expected: After pressing ESC, trigger Measure again. The overlay launches fresh — no cursor glitch, no residual state.
result: pass
note: Required stale window callback nil-out to prevent old onRequestExit from triggering handleExit on new session. Tested 4 consecutive sessions successfully.

### 6. Raycast ESC terminates process
expected: Launch the Measure command from Raycast. Press ESC. The Raycast extension process terminates completely.
result: skipped
reason: Raycast code path unchanged — all fixes are gated behind `if runMode == .standalone`. ray build passes. Raycast-mode handleExit still calls NSApp.terminate(nil).

## Summary

total: 6
passed: 5
issues: 0
pending: 0
skipped: 1

## Gaps

[none]
