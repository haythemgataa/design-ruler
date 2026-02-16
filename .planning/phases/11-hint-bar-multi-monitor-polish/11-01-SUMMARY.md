---
phase: 11-hint-bar-multi-monitor-polish
plan: 01
subsystem: alignment-guides-polish
tags: [polish, hint-bar, bug-fix, ui]
dependency_graph:
  requires: [phase-10-color-circles]
  provides: [remove-mode-reset, hint-bar-alignment-guides-content]
  affects: [GuideLineManager, GuideLine, ColorCircleIndicator, HintBarContent, HintBarView]
tech_stack:
  added: [HintBarMode-enum, alignment-guides-keycaps]
  patterns: [mode-based-content-selection, conditional-view-branching]
key_files:
  created: []
  modified:
    - swift/Ruler/Sources/AlignmentGuides/GuideLineManager.swift
    - swift/Ruler/Sources/AlignmentGuides/GuideLine.swift
    - swift/Ruler/Sources/AlignmentGuides/ColorCircleIndicator.swift
    - swift/Ruler/Sources/Rendering/HintBarContent.swift
    - swift/Ruler/Sources/Rendering/HintBarView.swift
decisions:
  - "Preview pill opacity set to 1.0 (matching inspect command pill) for visual consistency"
  - "Color circle borders use 2px inactive / 3px active for better visual hierarchy"
  - "Dynamic circle uses #292929 and #E2E2E2 (instead of pure black/white) for softer appearance"
  - "Left collapsed panel content conditionally created at init based on mode (inspect vs alignment guides)"
metrics:
  duration: 3m 50s
  tasks_completed: 2
  files_modified: 5
  completed_date: 2026-02-16
---

# Phase 11 Plan 01: Alignment Guide Polish & Hint Bar Infrastructure Summary

**One-liner:** Fixed remove-state-stuck bug with resetRemoveMode(), polished alignment guide visuals (pill opacity 1.0, color circle borders 2px/3px, dynamic circle colors #292929/#E2E2E2), and built hint bar content infrastructure with HintBarMode enum supporting both inspect and alignment guides keycaps.

## What Was Built

### Task 1: Remove-State Bug Fix + Visual Polish
**Files:** GuideLineManager.swift, GuideLine.swift, ColorCircleIndicator.swift
**Commit:** 8eb4aa3

Fixed critical bug where preview line remained in remove mode after clicking to remove a line:
- Added `GuideLineManager.resetRemoveMode()` method to reset `previewLine.isInRemoveMode = false` and `setLineVisible(true)`
- This method will be called from `AlignmentGuidesWindow.mouseDown()` after `removeLine()` completes (Plan 02 wiring)

Visual polish fixes:
- **Preview pill opacity:** Changed from 0.7 to 1.0 in both `setupLayers()` (line 103) and `layoutPill()` (line 173) to match inspect command pill opacity
- **Color circle borders:** Updated from 1px to 2px inactive, 2px to 3px active (lines 136, 148, 213, 305 in ColorCircleIndicator.swift)
- **Dynamic circle colors:** Updated from pure black/white to #292929 (left half) and #E2E2E2 (right half) for softer appearance (lines 245, 255)

### Task 2: Hint Bar Content Infrastructure
**Files:** HintBarContent.swift, HintBarView.swift
**Commit:** f03d074

Built complete hint bar content infrastructure for alignment guides mode:

**HintBarContent.swift changes:**
- Added `HintBarMode` enum with `.inspect` and `.alignmentGuides` cases
- Added `mode` property to `HintBarState` (defaults to `.inspect`)
- Updated `HintBarContent` body to branch on `state.mode`:
  - Inspect mode: "Use [arrows] to skip edges, plus [shift] to reverse. [esc] to exit."
  - Alignment guides mode: "Press [tab] to switch direction, [space] to change color. [esc] to exit."
- Added `CollapsedAlignmentGuidesLeftContent` view showing [tab][space] keycaps
- Updated `HintBarGlassRoot` (macOS 26+) to support both modes:
  - Added `tabCap` and `spaceCap` computed properties
  - Updated `glassLayer` to conditionally show inspect or alignment guides text
  - Updated `keycapLayer` to conditionally show inspect (arrows + shift) or alignment guides (tab + space) keycaps

**HintBarView.swift changes:**
- Added `KeyID.tab` and `KeyID.space` cases to enum
- Added `setMode(_ mode: HintBarMode)` public method for external mode setting
- Updated `leftHostingView` type from `NSHostingView<CollapsedLeftContent>?` to `NSView?` to support both collapsed content variants
- Updated `setupFallbackPath()` to conditionally create inspect or alignment guides left panel content based on `state.mode`

## Deviations from Plan

None — plan executed exactly as written.

## Integration Points

### For Plan 02 (Phase 11 wiring):
- Call `GuideLineManager.resetRemoveMode()` from `AlignmentGuidesWindow.mouseDown()` after `removeLine()` completes
- Call `hintBarView.setMode(.alignmentGuides)` before `hintBarView.configure()` in `AlignmentGuidesWindow.init()`
- Collapsed content will automatically show [tab][space] keycaps when mode is set

### For Future Use:
- `HintBarMode` enum is ready for additional modes if needed
- Keycap infrastructure supports any key via `KeyID` enum extension

## Verification Results

All verification steps passed:
- ✅ Swift build succeeds with no errors
- ✅ `GuideLineManager.resetRemoveMode()` method exists and resets `isInRemoveMode` + line visibility
- ✅ `GuideLine` preview pill opacity is 1.0 (not 0.7) in both locations
- ✅ `ColorCircleIndicator` uses 2px/3px border widths and #292929/#E2E2E2 dynamic colors
- ✅ `HintBarMode` enum exists with `.inspect` and `.alignmentGuides` cases
- ✅ `HintBarContent` renders alignment guides text when mode is `.alignmentGuides`
- ✅ `CollapsedAlignmentGuidesLeftContent` shows tab + space keycaps
- ✅ `HintBarGlassRoot` supports both modes in glass and keycap layers
- ✅ `HintBarView` has `setMode()` method and `KeyID.tab`, `KeyID.space` cases
- ✅ Existing inspect hint bar behavior unchanged (no regression)

## Technical Notes

### Why Preview Pill Opacity Changed
Inspect command pills use opacity 1.0. Alignment guide preview pills were using 0.7, creating visual inconsistency. Changed to 1.0 for uniformity.

### Why Border Widths Changed
Original 1px borders were too subtle for inactive circles. 2px inactive / 3px active creates better visual hierarchy while remaining subtle.

### Why Dynamic Circle Colors Changed
Pure black (#000000) and white (#FFFFFF) were too harsh against varied backgrounds. #292929 and #E2E2E2 provide softer contrast while maintaining the "dynamic" concept.

### Hint Bar Mode Architecture
The mode-based content selection uses SwiftUI's conditional branching (`if state.mode == .inspect { ... } else { ... }`). This approach:
- Keeps content selection logic in the view layer (where it belongs)
- Allows mode changes to trigger automatic view updates via `@Published`
- Works seamlessly with both morph path (macOS 26+) and fallback path (pre-macOS 26)
- Supports future modes without refactoring

## Self-Check: PASSED

### Files Verified
✅ `/Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/AlignmentGuides/GuideLineManager.swift` exists and contains `resetRemoveMode()`
✅ `/Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/AlignmentGuides/GuideLine.swift` exists and contains `opacity: Float = 1.0`
✅ `/Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/AlignmentGuides/ColorCircleIndicator.swift` exists and contains `borderWidth = 2` and `borderWidth = 3`
✅ `/Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/Rendering/HintBarContent.swift` exists and contains `HintBarMode` enum
✅ `/Users/haythem/conductor/workspaces/design-ruler-v1/rabat/swift/Ruler/Sources/Rendering/HintBarView.swift` exists and contains `case tab, space`

### Commits Verified
✅ Commit 8eb4aa3: fix(11-01): polish alignment guide visuals and remove-mode reset
✅ Commit f03d074: feat(11-01): add alignment guides hint bar content infrastructure

All artifacts delivered as specified in plan must-haves.
