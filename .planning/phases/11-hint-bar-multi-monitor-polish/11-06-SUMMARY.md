---
phase: 11-hint-bar-multi-monitor-polish
plan: 06
subsystem: alignment-guides-keycaps
tags: [gap-closure, multi-monitor, hint-bar, keycap-rendering]
dependency_graph:
  requires: [11-03-SUMMARY, 11-04-SUMMARY, 11-UAT-V2]
  provides: [complete-multi-monitor-cursor-tracking, corrected-keycap-rendering]
  affects: [AlignmentGuidesWindow, HintBarContent]
tech_stack:
  added: []
  patterns: [cursor-position-initialization, composite-symbol-alignment]
key_files:
  created: []
  modified:
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift
    - swift/Ruler/Sources/Rendering/HintBarContent.swift
decisions:
  - Initialize cursor position in activate() for non-cursor windows (not just showInitialState)
  - Tab keycap composite uses .bottomLeading alignment with frame for proper positioning
  - Space keycap uses "space" text instead of ␣ symbol for better SF Pro Rounded rendering
metrics:
  duration: 87s
  completed: 2026-02-16T18:50:33Z
---

# Phase 11 Plan 06: UAT Gap Closure - Multi-Monitor Color Circle & Keycap Rendering

**One-liner:** Fixed color circle cursor tracking on all screens when launched from second monitor and corrected tab/space keycap rendering per user feedback.

## What Was Done

### Task 1: Fix Color Circle Position on All Windows

**Problem:** When launched from second monitor, color circle appeared at (0,0) on the main monitor until mouse moved into that monitor.

**Root Cause:** The `showInitialState()` method initialized `lastCursorPosition` but was only called on the cursor window. Non-cursor windows retained the default `.zero` value until the first `mouseMoved()` event.

**Fix:** Added `lastCursorPosition` initialization at the start of `activate()` method using `NSEvent.mouseLocation - screenBounds.origin`. The `activate()` method is called when a window becomes active (cursor enters its screen), ensuring every window has the correct cursor position when it becomes active.

**Files Modified:**
- `swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift` - Updated `activate()` method (lines 153-162)

**Commit:** `1aa88be` - fix(11-06): initialize cursor position in activate() for all windows

### Task 2: Fix Tab Alignment and Space Keycap Text

**Problem 1:** Tab keycap composite (arrow + pipe) was centered instead of bottom-left aligned, and dimensions were slightly off from user's Figma design.

**Problem 2:** Space keycap used ␣ symbol at 16px which rendered differently than expected in SF Pro Rounded. User requested "space" text at 12px instead.

**Fix 1 - Tab Keycap:**
- Increased width from 32px to 40px (all 3 rendering paths)
- Increased arrow size from 13px to 14px
- Added `.bottomLeading` alignment with padding to the composite HStack in `capLabel`

**Fix 2 - Space Keycap:**
- Changed symbol from `"\u{2423}"` to `"space"` (all 3 rendering paths)
- Reduced font size from 16px to 12px
- Kept width at 64px as requested in UAT round 1

**Files Modified:**
- `swift/Ruler/Sources/Rendering/HintBarContent.swift` - Updated `capLabel` computed property and all 6 keycap call sites (3 tab, 3 space)

**Updated Call Sites:**
1. `HintBarContent.body` (alignment guides branch)
2. `CollapsedAlignmentGuidesLeftContent.body`
3. `HintBarGlassRoot.tabCap` and `HintBarGlassRoot.spaceCap` computed properties

**Commit:** `66ed5bc` - fix(11-06): update tab and space keycap rendering per user feedback

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

1. Swift build: ✅ Passed (Build complete! 1.56s)
2. `lastCursorPosition = NSPoint` appears in both `showInitialState()` and `activate()`: ✅ Verified
3. Tab keycap `width: 40` in all 3 rendering paths: ✅ Verified (3 occurrences)
4. Tab arrow `size: 14` in composite: ✅ Verified
5. Tab composite `.bottomLeading` alignment: ✅ Verified
6. Space keycap `symbol: "space"` in all 3 paths: ✅ Verified (3 occurrences)
7. Space keycap `size: 12` in all 3 paths: ✅ Verified (3 occurrences)
8. No `"\u{2423}"` in HintBarContent.swift: ✅ Verified (all replaced)

## Impact

**Multi-Monitor Color Circle Fix:**
- Color circle indicator now follows cursor correctly on all screens when launched from any monitor
- Spacebar can be pressed immediately on launch without waiting for mouse movement
- Non-cursor windows initialize cursor position when they become active

**Keycap Rendering Improvements:**
- Tab keycap matches user's Figma design (40px wide, arrow-pipe at bottom-left, 14px arrow)
- Space keycap uses plain text rendering for better visual consistency with SF Pro Rounded
- All 3 rendering paths (SwiftUI, collapsed, glass morph) updated consistently

## Testing Notes

**Multi-Monitor Cursor Tracking:**
- Launch from second monitor
- Press spacebar before moving mouse
- Color circle should appear at cursor position on all screens (not at 0,0)

**Keycap Rendering:**
- Launch alignment guides mode
- Tab keycap should be 40px wide with arrow-pipe composite at bottom-left
- Space keycap should show "space" text (not ␣ symbol) at 12px in 64px wide cap
- Both should render consistently in expanded, collapsed, and glass morph layouts

## Self-Check: PASSED

**Created files:** None (modifications only)

**Modified files:**
- ✅ `/Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift` exists
- ✅ `/Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/Rendering/HintBarContent.swift` exists

**Commits:**
- ✅ `1aa88be` found: fix(11-06): initialize cursor position in activate() for all windows
- ✅ `66ed5bc` found: fix(11-06): update tab and space keycap rendering per user feedback
