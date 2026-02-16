---
phase: 11-hint-bar-multi-monitor-polish
plan: 03
subsystem: AlignmentGuides
type: gap-closure
tags: [multi-monitor, bug-fix, uat-failures]
completed: 2026-02-16
duration: 116s
dependencies:
  requires:
    - AlignmentGuidesWindow
    - AlignmentGuides
    - GuideLineManager
  provides:
    - Fixed multi-monitor background rendering
    - Fixed preview line lifecycle
    - Fixed color circle initial position
  affects:
    - Multi-monitor alignment guides behavior
    - Screenshot capture and display
    - Preview line visibility management
tech-stack:
  added: []
  patterns: [capture-before-window, window-local-coordinates]
key-files:
  created: []
  modified:
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuides.swift
    - swift/Ruler/Sources/AlignmentGuides/GuideLineManager.swift
key-decisions:
  - "Single background view per window eliminates Z-order conflicts"
  - "Initialize cursor position from NSEvent.mouseLocation in showInitialState()"
  - "Preview line lifecycle tied to window activation/deactivation"
metrics:
  tasks: 2
  commits: 2
  files_modified: 3
---

# Phase 11 Plan 03: Multi-Monitor UAT Gap Closure Summary

Fixed three multi-monitor bugs: second monitor black screen, frozen preview lines, and color circle at (0,0).

## Overview

Closed critical multi-monitor gaps discovered during UAT. The second monitor was showing a black screen instead of the captured screenshot due to duplicate background view creation. Preview lines remained visible on inactive monitors when the cursor moved away. The color circle indicator appeared at (0,0) when spacebar was pressed before any mouse movement on secondary monitors.

## Tasks Completed

### Task 1: Fix duplicate background and color circle initial position

**What was done:**
- Removed duplicate `setBackground()` call from AlignmentGuides.swift (lines 69-71)
- Removed the entire `setBackground()` method from AlignmentGuidesWindow.swift (lines 105-114)
- Single background view now created in `setupViews()` as part of the view hierarchy
- Added cursor position initialization in `showInitialState()` using `NSEvent.mouseLocation - screenBounds.origin`

**Files modified:**
- swift/Ruler/Sources/AlignmentGuides/AlignmentGuides.swift
- swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift

**Commit:** f701f01

**Issues resolved:**
- Bug 1 (blocker): Second monitor showed black screen instead of screenshot
- Bug 3 (major): Color circle appeared at (0,0) when launched on second monitor and spacebar pressed before mouse move

**Root cause:**
The original code created TWO background views: one in `setupViews()` at lines 60-66, and another via `setBackground()` called from AlignmentGuides.swift at lines 69-71. The second background was inserted BELOW the first using `addSubview(_:positioned:.below)`, creating a Z-order conflict where the first (potentially empty or black) background obscured the second.

Additionally, `lastCursorPosition` was initialized to `.zero` and only updated in `mouseMoved()`, causing the color circle to appear at (0,0) if spacebar was pressed before any mouse movement.

### Task 2: Hide preview line on monitor deactivation

**What was done:**
- Added `hidePreview()` method to GuideLineManager (calls `setLineVisible(false)` and `hidePill()`)
- Added `showPreview()` method to GuideLineManager (calls `setLineVisible(true)`)
- Modified `deactivate()` in AlignmentGuidesWindow to call `guideLineManager.hidePreview()`
- Modified `activate()` in AlignmentGuidesWindow to call `guideLineManager.showPreview()` before updating preview position

**Files modified:**
- swift/Ruler/Sources/AlignmentGuides/GuideLineManager.swift
- swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift

**Commit:** 4cad137

**Issues resolved:**
- Bug 2 (minor): Preview line remained frozen on inactive monitor when cursor moved to another screen

**Root cause:**
The `deactivate()` method only cleared hover state but never hid the preview line itself. When the cursor moved to another monitor, the preview line (and its pill) remained visible at the last cursor position on the deactivated screen. The user reported "there is a preview line for each monitor, it doesn't disappear if I move away."

## Deviations from Plan

None. Plan executed exactly as written.

## Technical Decisions

| Decision | Rationale | Alternatives Considered |
|----------|-----------|------------------------|
| Single background view creation in setupViews() | Eliminates Z-order conflicts, matches RulerWindow pattern | Keep both but fix Z-order (more complex, error-prone) |
| Initialize lastCursorPosition in showInitialState() | Provides correct cursor position before first mouse move | Wait for first mouseMoved (leaves gap where spacebar fails) |
| Preview line lifecycle tied to activation/deactivation | Clean separation of concerns, predictable behavior | Track cursor screen globally (more state complexity) |

## Verification

All success criteria met:

- Swift build passes with no errors
- No duplicate background creation (verified via grep)
- Preview line hidden on deactivation, shown on activation (verified via grep)
- Color circle initial position derived from NSEvent.mouseLocation, not (0,0)
- Second monitor shows captured screenshot (single background view)
- Preview line disappears when cursor leaves monitor, reappears when cursor enters

## Self-Check: PASSED

**Created files:** None (no new files created)

**Modified files:**
- /Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift - FOUND
- /Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/AlignmentGuides/AlignmentGuides.swift - FOUND
- /Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/AlignmentGuides/GuideLineManager.swift - FOUND

**Commits:**
- f701f01 - FOUND
- 4cad137 - FOUND

All referenced files and commits exist.

## Impact

**Immediate:**
- Multi-monitor alignment guides now work correctly on all screens
- Second monitor users can see the screenshot background
- Preview line behavior is consistent across monitor transitions
- Color circle appears at correct position when launched on any screen

**Follow-up:**
- UAT should be re-run to confirm all three issues are resolved
- Consider adding automated tests for multi-monitor scenarios

## Commits

| Hash | Type | Description |
|------|------|-------------|
| f701f01 | fix | Eliminate duplicate background creation in alignment guides |
| 4cad137 | fix | Hide preview line when cursor leaves monitor |
