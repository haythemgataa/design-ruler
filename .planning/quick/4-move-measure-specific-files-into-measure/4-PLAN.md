---
phase: quick-4
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - swift/DesignRuler/Sources/Measure/Measure.swift
  - swift/DesignRuler/Sources/Measure/MeasureWindow.swift
  - swift/DesignRuler/Sources/Measure/EdgeDetector.swift
  - swift/DesignRuler/Sources/Measure/ColorMap.swift
  - swift/DesignRuler/Sources/Measure/DirectionalEdges.swift
  - swift/DesignRuler/Sources/Measure/CrosshairView.swift
  - swift/DesignRuler/Sources/Measure/SelectionManager.swift
  - swift/DesignRuler/Sources/Measure/SelectionOverlay.swift
  - CLAUDE.md
autonomous: true
must_haves:
  truths:
    - "All Measure-specific files live under Sources/Measure/"
    - "EdgeDetection/ folder no longer exists"
    - "Rendering/ only contains shared files (PillRenderer, HintBarView, HintBarContent)"
    - "Project builds successfully with swift build"
    - "CLAUDE.md architecture tree reflects new structure"
  artifacts:
    - path: "swift/DesignRuler/Sources/Measure/Measure.swift"
      provides: "Measure entry point"
    - path: "swift/DesignRuler/Sources/Measure/MeasureWindow.swift"
      provides: "Measure window"
    - path: "swift/DesignRuler/Sources/Measure/EdgeDetector.swift"
      provides: "Edge detection logic"
    - path: "swift/DesignRuler/Sources/Measure/ColorMap.swift"
      provides: "Pixel buffer and color scanning"
    - path: "swift/DesignRuler/Sources/Measure/DirectionalEdges.swift"
      provides: "EdgeHit and DirectionalEdges models"
    - path: "swift/DesignRuler/Sources/Measure/CrosshairView.swift"
      provides: "Crosshair rendering"
    - path: "swift/DesignRuler/Sources/Measure/SelectionManager.swift"
      provides: "Drag selection logic"
    - path: "swift/DesignRuler/Sources/Measure/SelectionOverlay.swift"
      provides: "Selection rendering"
  key_links:
    - from: "swift/DesignRuler/Package.swift"
      to: "swift/DesignRuler/Sources/**/*.swift"
      via: "automatic source discovery (no path: specified)"
      pattern: "executableTarget"
---

<objective>
Move all Measure-specific Swift files into a dedicated `Measure/` subfolder under `Sources/`, mirroring the existing `AlignmentGuides/` folder pattern. Remove the now-empty `EdgeDetection/` folder. Update CLAUDE.md to reflect the new structure.

Purpose: Organize Measure command files into their own subfolder for symmetry with AlignmentGuides, making the codebase structure clearer.
Output: Reorganized file tree with passing build.
</objective>

<execution_context>
@/Users/haythem/.claude/get-shit-done/workflows/execute-plan.md
@/Users/haythem/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md (Section 2 — Architecture Overview, needs update)
@swift/DesignRuler/Package.swift (auto-discovers Sources/, no file lists to update)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Move Measure-specific files into Measure/ subfolder</name>
  <files>
    swift/DesignRuler/Sources/Measure/Measure.swift
    swift/DesignRuler/Sources/Measure/MeasureWindow.swift
    swift/DesignRuler/Sources/Measure/EdgeDetector.swift
    swift/DesignRuler/Sources/Measure/ColorMap.swift
    swift/DesignRuler/Sources/Measure/DirectionalEdges.swift
    swift/DesignRuler/Sources/Measure/CrosshairView.swift
    swift/DesignRuler/Sources/Measure/SelectionManager.swift
    swift/DesignRuler/Sources/Measure/SelectionOverlay.swift
  </files>
  <action>
    1. Create the `Measure/` directory:
       ```
       mkdir -p swift/DesignRuler/Sources/Measure
       ```

    2. Use `git mv` for ALL moves (preserves history):
       ```
       git mv swift/DesignRuler/Sources/Measure.swift swift/DesignRuler/Sources/Measure/
       git mv swift/DesignRuler/Sources/MeasureWindow.swift swift/DesignRuler/Sources/Measure/
       git mv swift/DesignRuler/Sources/EdgeDetection/EdgeDetector.swift swift/DesignRuler/Sources/Measure/
       git mv swift/DesignRuler/Sources/EdgeDetection/ColorMap.swift swift/DesignRuler/Sources/Measure/
       git mv swift/DesignRuler/Sources/EdgeDetection/DirectionalEdges.swift swift/DesignRuler/Sources/Measure/
       git mv swift/DesignRuler/Sources/Rendering/CrosshairView.swift swift/DesignRuler/Sources/Measure/
       git mv swift/DesignRuler/Sources/Rendering/SelectionManager.swift swift/DesignRuler/Sources/Measure/
       git mv swift/DesignRuler/Sources/Rendering/SelectionOverlay.swift swift/DesignRuler/Sources/Measure/
       ```

    3. The `EdgeDetection/` directory should now be empty. Git removes empty directories automatically on commit, but verify with `ls swift/DesignRuler/Sources/EdgeDetection/` — it should error or be empty. Remove it explicitly with `rmdir` if needed.

    4. Verify `Rendering/` only contains shared files:
       ```
       ls swift/DesignRuler/Sources/Rendering/
       ```
       Expected: PillRenderer.swift, HintBarView.swift, HintBarContent.swift (3 files only).

    5. Verify `Measure/` contains all 8 files:
       ```
       ls swift/DesignRuler/Sources/Measure/
       ```
       Expected: Measure.swift, MeasureWindow.swift, EdgeDetector.swift, ColorMap.swift, DirectionalEdges.swift, CrosshairView.swift, SelectionManager.swift, SelectionOverlay.swift.

    6. Build to confirm no breakage:
       ```
       cd swift/DesignRuler && swift build 2>&1
       ```
       Must compile successfully. SPM auto-discovers all .swift files under Sources/ recursively, so no Package.swift changes needed.

    No Swift source code changes are needed — only file moves. All types remain in the same Swift module, so imports and references are unaffected.
  </action>
  <verify>
    - `ls swift/DesignRuler/Sources/Measure/` shows exactly 8 .swift files
    - `ls swift/DesignRuler/Sources/EdgeDetection/ 2>&1` errors (directory gone)
    - `ls swift/DesignRuler/Sources/Rendering/` shows exactly 3 shared files
    - `cd swift/DesignRuler && swift build` compiles without errors
  </verify>
  <done>All 8 Measure-specific files live under Sources/Measure/, EdgeDetection/ is gone, Rendering/ has only shared files, and the project builds successfully.</done>
</task>

<task type="auto">
  <name>Task 2: Update CLAUDE.md architecture tree</name>
  <files>CLAUDE.md</files>
  <action>
    Update the architecture tree in Section 2 of CLAUDE.md to reflect the new folder structure. Replace the current tree with:

    ```
    TypeScript (thin wrappers, ~13 lines each)
      |- src/measure.ts       -> import { inspect } from "swift:../swift/DesignRuler"
      \- src/alignment-guides.ts -> import { alignmentGuides } from "swift:../swift/DesignRuler"
           \- Swift (all logic)
                |- Measure/
                |   |- Measure.swift            -- OverlayCoordinator subclass, Measure entry
                |   |- MeasureWindow.swift      -- OverlayWindow subclass, edge detection + drag
                |   |- EdgeDetector.swift       -- capture + scan + skip state + smart corrections
                |   |- ColorMap.swift           -- pixel buffer, color scanning, stabilization
                |   |- DirectionalEdges.swift   -- EdgeHit + DirectionalEdges models
                |   |- CrosshairView.swift      -- 4 lines, cross-feet, W*H pill (via PillRenderer)
                |   |- SelectionManager.swift   -- drag lifecycle, edge snapping, hover tracking
                |   \- SelectionOverlay.swift   -- selection rendering, snap animation, shake
                |- Rendering/
                |   |- PillRenderer.swift       -- shared pill factories, font, paths, text, shadows
                |   |- HintBarView.swift        -- glass hint bar, slide animation, expand/collapse
                |   \- HintBarContent.swift     -- SwiftUI keycap layouts, HintBarTextStyle
                |- AlignmentGuides/
                |   |- AlignmentGuides.swift    -- OverlayCoordinator subclass, alignment-guides entry
                |   |- AlignmentGuidesWindow.swift -- OverlayWindow subclass, guide line management
                |   |- GuideLineManager.swift   -- preview line, placed lines, hover detection
                |   |- GuideLine.swift          -- line rendering, position pills (via PillRenderer)
                |   |- GuideLineStyle.swift     -- 5 color presets (dynamic, red, green, orange, blue)
                |   \- ColorCircleIndicator.swift -- arc-based color indicator, debounced auto-hide
                |- Cursor/
                |   \- CursorManager.swift      -- state machine, 5 states, cursorUpdate pattern
                |- Utilities/
                |   |- OverlayCoordinator.swift -- shared lifecycle base (warmup, permissions, exit)
                |   |- OverlayWindow.swift      -- shared window base (config, tracking, throttle)
                |   |- ScreenCapture.swift      -- shared CGWindowListCreateImage wrapper
                |   |- DesignTokens.swift       -- centralized colors, radii, durations, BlendMode
                |   |- TransactionHelpers.swift  -- CATransaction.instant{} and .animated{}
                |   \- CoordinateConverter.swift -- AppKit <-> CG point + rect conversion
                \- Permissions/
                    \- PermissionChecker.swift  -- screen recording check/request
    ```

    Key changes from old tree:
    - `Measure.swift` and `MeasureWindow.swift` move from top-level into `Measure/`
    - `EdgeDetection/` folder removed entirely; its 3 files are now inside `Measure/`
    - `Rendering/` loses CrosshairView, SelectionManager, SelectionOverlay (moved to `Measure/`)
    - `Measure/` is listed first (before `Rendering/`) to mirror the command-first ordering

    Use the proper Unicode box-drawing characters (the action above uses ASCII for clarity, but the actual CLAUDE.md uses Unicode tree chars). Match the existing formatting style exactly.
  </action>
  <verify>
    - Read CLAUDE.md Section 2 and confirm the tree shows `Measure/` with 8 files
    - Confirm `EdgeDetection/` does not appear in the tree
    - Confirm `Rendering/` shows only 3 shared files
  </verify>
  <done>CLAUDE.md architecture tree in Section 2 accurately reflects the new Measure/ subfolder structure, with EdgeDetection/ removed and Rendering/ showing only shared files.</done>
</task>

</tasks>

<verification>
1. `ls swift/DesignRuler/Sources/` shows: AlignmentGuides, Cursor, Measure, Permissions, Rendering, Utilities (6 items, no EdgeDetection, no loose .swift files)
2. `ls swift/DesignRuler/Sources/Measure/` shows 8 .swift files
3. `ls swift/DesignRuler/Sources/Rendering/` shows 3 .swift files
4. `cd swift/DesignRuler && swift build` succeeds
5. CLAUDE.md Section 2 tree matches actual file structure
</verification>

<success_criteria>
- All 8 Measure-specific files moved to Sources/Measure/ via git mv
- EdgeDetection/ directory removed
- Rendering/ contains only PillRenderer.swift, HintBarView.swift, HintBarContent.swift
- swift build passes with no errors
- CLAUDE.md architecture tree updated to match new structure
</success_criteria>

<output>
After completion, create `.planning/quick/4-move-measure-specific-files-into-measure/4-SUMMARY.md`
</output>
