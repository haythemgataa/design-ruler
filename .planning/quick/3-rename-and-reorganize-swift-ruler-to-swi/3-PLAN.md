---
phase: quick-3
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - swift/DesignRuler/Package.swift
  - swift/DesignRuler/Sources/Measure.swift
  - swift/DesignRuler/Sources/MeasureWindow.swift
  - swift/DesignRuler/Sources/Cursor/CursorManager.swift
  - swift/DesignRuler/Sources/Utilities/OverlayCoordinator.swift
  - src/measure.ts
  - src/alignment-guides.ts
  - CLAUDE.md
autonomous: true
must_haves:
  truths:
    - "swift/Ruler/ no longer exists; swift/DesignRuler/ contains all Swift sources"
    - "Package.swift declares package name 'DesignRuler' and target name 'DesignRuler'"
    - "Class Ruler is now class Measure with Measure.shared singleton"
    - "Class RulerWindow is now class MeasureWindow"
    - "Both TypeScript entry points import from swift:../swift/DesignRuler"
    - "npm run build succeeds with zero errors"
    - "CLAUDE.md reflects all new paths and class names"
  artifacts:
    - path: "swift/DesignRuler/Package.swift"
      provides: "SPM package definition with name DesignRuler"
      contains: 'name: "DesignRuler"'
    - path: "swift/DesignRuler/Sources/Measure.swift"
      provides: "Measure command coordinator"
      contains: "class Measure"
    - path: "swift/DesignRuler/Sources/MeasureWindow.swift"
      provides: "Measure command overlay window"
      contains: "class MeasureWindow"
  key_links:
    - from: "src/measure.ts"
      to: "swift/DesignRuler"
      via: "swift bridge import"
      pattern: 'swift:../swift/DesignRuler'
    - from: "src/alignment-guides.ts"
      to: "swift/DesignRuler"
      via: "swift bridge import"
      pattern: 'swift:../swift/DesignRuler'
---

<objective>
Rename swift/Ruler/ to swift/DesignRuler/, rename Ruler class to Measure, rename RulerWindow class to MeasureWindow, and update all references across the codebase.

Purpose: Align Swift package/class naming with the renamed "Measure" command (quick task 2) and give the package a descriptive name matching the extension.
Output: Fully renamed and building codebase with preserved git history.
</objective>

<execution_context>
@/Users/haythem/.claude/get-shit-done/workflows/execute-plan.md
@/Users/haythem/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@swift/Ruler/Package.swift
@swift/Ruler/Sources/Ruler.swift
@swift/Ruler/Sources/RulerWindow.swift
@swift/Ruler/Sources/Cursor/CursorManager.swift
@swift/Ruler/Sources/Utilities/OverlayCoordinator.swift
@src/measure.ts
@src/alignment-guides.ts
</context>

<tasks>

<task type="auto">
  <name>Task 1: Git-rename folder and files, update Package.swift and all Swift class references</name>
  <files>
    swift/DesignRuler/Package.swift
    swift/DesignRuler/Sources/Measure.swift
    swift/DesignRuler/Sources/MeasureWindow.swift
    swift/DesignRuler/Sources/Cursor/CursorManager.swift
    swift/DesignRuler/Sources/Utilities/OverlayCoordinator.swift
  </files>
  <action>
    **Step 1 — Folder and file renames (git mv to preserve history):**

    1. `git mv swift/Ruler swift/DesignRuler`
    2. `git mv swift/DesignRuler/Sources/Ruler.swift swift/DesignRuler/Sources/Measure.swift`
    3. `git mv swift/DesignRuler/Sources/RulerWindow.swift swift/DesignRuler/Sources/MeasureWindow.swift`

    **Step 2 — Delete old build cache (will not work with new path):**

    `rm -rf swift/DesignRuler/.raycast-swift-build`

    **Step 3 — Update Package.swift:**

    Change both occurrences of `"Ruler"` to `"DesignRuler"`:
    - `name: "Ruler"` -> `name: "DesignRuler"`
    - `.executableTarget(name: "Ruler"` -> `.executableTarget(name: "DesignRuler"`

    **Step 4 — Update class names in Measure.swift (formerly Ruler.swift):**

    - `class Ruler: OverlayCoordinator` -> `class Measure: OverlayCoordinator`
    - `static let shared = Ruler()` -> `static let shared = Measure()`
    - `Ruler.shared.run(` -> `Measure.shared.run(`
    - `let rulerWindow = RulerWindow.create(` -> `let measureWindow = MeasureWindow.create(`
    - `rulerWindow.setBackground(` -> `measureWindow.setBackground(`
    - `return rulerWindow` -> `return measureWindow`
    - `guard let rulerWindow = window as? RulerWindow` -> `guard let measureWindow = window as? MeasureWindow` (2 occurrences: wireCallbacks and activateWindow)
    - Update all `rulerWindow.` references to `measureWindow.` in those methods

    **Step 5 — Update class names in MeasureWindow.swift (formerly RulerWindow.swift):**

    - `final class RulerWindow: OverlayWindow` -> `final class MeasureWindow: OverlayWindow`
    - `var onActivate: ((RulerWindow) -> Void)?` -> `var onActivate: ((MeasureWindow) -> Void)?`
    - `static func create(...) -> RulerWindow` -> `static func create(...) -> MeasureWindow`
    - `let window = RulerWindow(` -> `let window = MeasureWindow(`

    **Step 6 — Update comments referencing old names in other Swift files:**

    In `CursorManager.swift`:
    - Line 11 comment: `Ruler:  idle` -> `Measure:  idle` (this is an ASCII diagram)
    - Line 18 comment: `Ruler: cursor hidden` -> `Measure: cursor hidden`
    - Line 21 comment: `Ruler only` -> `Measure only`
    - Line 38 comment: `RulerWindow.showInitialState()` -> `MeasureWindow.showInitialState()`
    - Line 39 comment: `Ruler mode` -> `Measure mode`
    - Line 70 comment: `(Ruler)` -> `(Measure)`
    - Line 86 comment: `Ruler only` -> `Measure only`
    - Line 96 comment: `(Ruler)` -> `(Measure)`

    In `OverlayCoordinator.swift`:
    - Line 3 comment: `RulerWindow` -> `MeasureWindow`
    - Line 14 comment: `Both Ruler and AlignmentGuides` -> `Both Measure and AlignmentGuides`
    - Line 115 comment: `Ruler overrides` -> `Measure overrides`

    IMPORTANT: Only comments change in CursorManager.swift and OverlayCoordinator.swift. No functional code changes in those files.
    IMPORTANT: The `@raycast func inspect()` and `@raycast func alignmentGuides()` function names do NOT change.
  </action>
  <verify>
    1. `ls swift/DesignRuler/Sources/Measure.swift` exists
    2. `ls swift/DesignRuler/Sources/MeasureWindow.swift` exists
    3. `ls swift/Ruler 2>/dev/null` does NOT exist
    4. `grep -r "class Ruler" swift/DesignRuler/` returns nothing
    5. `grep -r "RulerWindow" swift/DesignRuler/` returns nothing
    6. `grep -r 'name: "Ruler"' swift/DesignRuler/Package.swift` returns nothing
    7. `grep "class Measure:" swift/DesignRuler/Sources/Measure.swift` succeeds
    8. `grep "class MeasureWindow:" swift/DesignRuler/Sources/MeasureWindow.swift` succeeds
  </verify>
  <done>
    swift/Ruler/ fully renamed to swift/DesignRuler/. Ruler class is now Measure. RulerWindow is now MeasureWindow. All internal Swift references (code and comments) updated. No stale "Ruler" class or "RulerWindow" references remain in any Swift file.
  </done>
</task>

<task type="auto">
  <name>Task 2: Update TypeScript imports, CLAUDE.md, and verify build</name>
  <files>
    src/measure.ts
    src/alignment-guides.ts
    CLAUDE.md
  </files>
  <action>
    **Step 1 — Update TypeScript imports:**

    In `src/measure.ts` line 2:
    - `import { inspect } from "swift:../swift/Ruler"` -> `import { inspect } from "swift:../swift/DesignRuler"`

    In `src/alignment-guides.ts` line 2:
    - `import { alignmentGuides } from "swift:../swift/Ruler"` -> `import { alignmentGuides } from "swift:../swift/DesignRuler"`

    **Step 2 — Update CLAUDE.md:**

    All path references containing `swift/Ruler/` must become `swift/DesignRuler/`. All class name references:
    - `Ruler.swift` -> `Measure.swift` (in architecture tree and all prose)
    - `RulerWindow.swift` -> `MeasureWindow.swift` (in architecture tree and all prose)
    - `class Ruler` / `Ruler.shared` -> `class Measure` / `Measure.shared`
    - `class RulerWindow` -> `class MeasureWindow`
    - In the Swift bridge pattern section: `Ruler.shared.run(` -> `Measure.shared.run(`
    - In architecture tree descriptions: update the comment text for Measure.swift and MeasureWindow.swift

    Specific sections to update:
    - Section 2 "Architecture Overview": the file tree shows `Ruler.swift` and `RulerWindow.swift` with descriptions referencing "Ruler" class names. Update file names AND descriptions.
    - Section 2 tree: `swift/Ruler/` at top level
    - Section 5 "Capture-Before-Window": references `OverlayCoordinator.run()` — "Ruler overrides" comment references
    - Section 12 "Animations": references to RulerWindow
    - Section 13 "Multi-Monitor": no direct Ruler class refs but check
    - Section 14 "CursorManager": `Ruler:  idle` diagram, `Ruler mode`, `RulerWindow.showInitialState()`
    - Section 15 "Swift Bridge Pattern": the code block shows `Ruler.shared.run()` and import path `swift:../swift/Ruler`
    - Section 16 "Learned Anti-Patterns": check for any Ruler refs

    Do a thorough search-and-replace in CLAUDE.md but be careful:
    - "Design Ruler" (the extension name) stays as "Design Ruler" — do NOT change it
    - Only change `Ruler` when it refers to the Swift class, file, or folder — not the product name
    - The phrase "Design Ruler" in section 1, section headers, etc. is the product name and stays

    **Step 3 — Build verification:**

    Run `npm run build` from the project root. Must complete with zero errors.

    If build fails due to stale cache, run `rm -rf swift/DesignRuler/.raycast-swift-build` and retry.
  </action>
  <verify>
    1. `grep "swift:../swift/DesignRuler" src/measure.ts` succeeds
    2. `grep "swift:../swift/DesignRuler" src/alignment-guides.ts` succeeds
    3. `grep -c "swift/Ruler" src/measure.ts src/alignment-guides.ts` returns 0 for both
    4. `grep "Measure.swift" CLAUDE.md` finds entries
    5. `grep "MeasureWindow.swift" CLAUDE.md` finds entries
    6. `grep "Ruler\.swift" CLAUDE.md` returns nothing (no stale file refs)
    7. `grep "RulerWindow\.swift" CLAUDE.md` returns nothing
    8. `grep "swift/Ruler/" CLAUDE.md` returns nothing
    9. `npm run build` exits 0
  </verify>
  <done>
    Both TypeScript files import from swift:../swift/DesignRuler. CLAUDE.md fully updated with new paths and class names while preserving "Design Ruler" product name references. Build passes cleanly.
  </done>
</task>

</tasks>

<verification>
1. `test ! -d swift/Ruler` — old directory gone
2. `test -d swift/DesignRuler` — new directory exists
3. `grep -r "class Ruler[^a-zA-Z]" swift/DesignRuler/` — returns nothing (no stale class refs)
4. `grep -r "RulerWindow" swift/DesignRuler/` — returns nothing
5. `grep -r "swift:../swift/Ruler" src/` — returns nothing
6. `grep "swift/Ruler/" CLAUDE.md` — returns nothing
7. `npm run build` — exits 0
8. `git log --oneline --follow swift/DesignRuler/Sources/Measure.swift | head -5` — shows history preserved
</verification>

<success_criteria>
- swift/Ruler/ no longer exists anywhere in the repo
- swift/DesignRuler/ contains all Swift sources with correct Package.swift
- Ruler class is Measure, RulerWindow class is MeasureWindow
- All Swift comments referencing old names are updated
- TypeScript imports point to swift:../swift/DesignRuler
- CLAUDE.md has no stale Ruler file/class references (product name "Design Ruler" preserved)
- `npm run build` passes
- Git history preserved via git mv
</success_criteria>

<output>
After completion, create `.planning/quick/3-rename-and-reorganize-swift-ruler-to-swi/3-SUMMARY.md`
</output>
