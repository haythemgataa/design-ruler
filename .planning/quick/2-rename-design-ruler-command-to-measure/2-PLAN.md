---
phase: quick-2
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - package.json
  - src/measure.ts
  - src/design-ruler.ts
  - swift/Ruler/Sources/RulerWindow.swift
  - swift/Ruler/Sources/Utilities/OverlayWindow.swift
  - swift/Ruler/Sources/Cursor/CursorManager.swift
  - CLAUDE.md
autonomous: true
must_haves:
  truths:
    - "Raycast shows the command as 'Measure' (not 'Design Ruler') in the command palette"
    - "The extension name remains 'Design Ruler' in Raycast"
    - "Both commands (Measure and Alignment Guides) still work after rename"
    - "CLAUDE.md accurately reflects the new command name"
  artifacts:
    - path: "package.json"
      provides: "Command renamed from design-ruler to measure"
      contains: '"name": "measure"'
    - path: "src/measure.ts"
      provides: "Renamed TypeScript entry point"
    - path: "CLAUDE.md"
      provides: "Updated documentation"
      contains: "**Measure**"
  key_links:
    - from: "package.json"
      to: "src/measure.ts"
      via: "Raycast command name must match TS filename"
      pattern: '"name": "measure"'
---

<objective>
Rename the "Design Ruler" command to "Measure" across the entire codebase.

Purpose: The command currently shares its name with the extension ("Design Ruler"), which is confusing. Renaming the command to "Measure" makes it distinct and descriptive of what it does.
Output: All user-visible references say "Measure", the TS entry file is renamed to match, and documentation is updated.
</objective>

<execution_context>
@/Users/haythem/.claude/get-shit-done/workflows/execute-plan.md
@/Users/haythem/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@package.json
@src/design-ruler.ts
@CLAUDE.md
@swift/Ruler/Sources/RulerWindow.swift
@swift/Ruler/Sources/Utilities/OverlayWindow.swift
@swift/Ruler/Sources/Cursor/CursorManager.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Rename command in package.json and TypeScript source</name>
  <files>package.json, src/design-ruler.ts, src/measure.ts</files>
  <action>
    1. In `package.json`, update the first command entry (index 0 in the `commands` array):
       - Change `"name": "design-ruler"` to `"name": "measure"`
       - Change `"title": "Design Ruler"` to `"title": "Measure"`
       - Change `"description": "Inspect pixel distances with edge detection"` to `"description": "Measure pixel distances with edge detection"`
       - Do NOT change the top-level extension `"name"` or `"title"` fields (those stay as "design-ruler" / "Design Ruler")
       - Do NOT change anything about the `alignment-guides` command

    2. Rename the TypeScript source file:
       - `git mv src/design-ruler.ts src/measure.ts`
       - The file contents remain identical (the Swift import path `swift:../swift/Ruler` and function name `inspect` do not change)

    Note: `raycast-env.d.ts` is auto-generated from package.json and will regenerate on next build. Do not manually edit it.
  </action>
  <verify>
    - `cat package.json | grep -A2 '"name": "measure"'` shows the renamed command
    - `ls src/measure.ts` confirms the file exists
    - `ls src/design-ruler.ts 2>&1` confirms the old file is gone
    - `cat package.json | grep '"title": "Design Ruler"'` still shows the extension title (line 4)
  </verify>
  <done>package.json command entry says name:"measure" title:"Measure", src/measure.ts exists, src/design-ruler.ts is gone</done>
</task>

<task type="auto">
  <name>Task 2: Update Swift comments and CLAUDE.md documentation</name>
  <files>swift/Ruler/Sources/RulerWindow.swift, swift/Ruler/Sources/Utilities/OverlayWindow.swift, swift/Ruler/Sources/Cursor/CursorManager.swift, CLAUDE.md</files>
  <action>
    1. Update Swift doc comments that reference the command name (NOT the extension name):
       - `swift/Ruler/Sources/RulerWindow.swift` line 4: Change "Design Ruler command" to "Measure command"
         `/// Fullscreen overlay window for the Measure command.`
       - `swift/Ruler/Sources/Utilities/OverlayWindow.swift` line 4: Change "Design Ruler and Alignment Guides" to "Measure and Alignment Guides"
         `/// Base class for fullscreen overlay windows shared by both Measure and Alignment Guides.`
       - `swift/Ruler/Sources/Cursor/CursorManager.swift` line 3: Change "Design Ruler and Alignment Guides" to "Measure and Alignment Guides"
         `/// Centralized cursor state machine for both Measure and Alignment Guides.`

    2. Update CLAUDE.md — change command references from "Design Ruler" to "Measure". Carefully distinguish between the EXTENSION name (stays "Design Ruler") and the COMMAND name (becomes "Measure"):
       - Section 1 intro: Keep "Design Ruler" as the extension title in the header. Change the command description line:
         `**Measure** -- Fullscreen overlay (frozen screenshot), crosshair follows`
       - Section 2 Architecture: Change file description:
         `├─ src/measure.ts  -> import { inspect } from "swift:../swift/Ruler"`
         and `├─ Ruler.swift              -- OverlayCoordinator subclass, Measure entry`
       - Section 9 Hint Bar Modes: "Measure mode: arrow key hints" (was "Design Ruler mode")
       - Section 10 Preferences table: Change "design-ruler only" to "measure only" in corrections row
       - Section 11 Key Behaviors: Change `### Design Ruler` heading to `### Measure`
       - Section 12 Animations Cursor on Launch: Change "**Design Ruler**:" to "**Measure**:"
       - Section 14 CursorManager states: Change "Ruler:" comment line to "Measure:" for the state diagram
       - Section 15 Swift Bridge: Change comment from `// design-ruler.ts` to `// measure.ts`
       - Section 17 Testing Checklist: Change `### Design Ruler` heading to `### Measure`
       - Do NOT change the main title "# Design Ruler -- Build Blueprint" (that is the extension name)
       - Do NOT change "Design Ruler" where it refers to the extension/product name in general prose
  </action>
  <verify>
    - `grep "Measure command" swift/Ruler/Sources/RulerWindow.swift` finds the updated comment
    - `grep "Measure and Alignment" swift/Ruler/Sources/Utilities/OverlayWindow.swift` finds the updated comment
    - `grep "Measure and Alignment" swift/Ruler/Sources/Cursor/CursorManager.swift` finds the updated comment
    - `grep "src/measure.ts" CLAUDE.md` finds the updated file reference
    - `grep "### Measure" CLAUDE.md` finds the updated section headings
    - `grep "Design Ruler" CLAUDE.md | head -5` still shows the extension name references are preserved
  </verify>
  <done>All Swift comments reference "Measure" (not "Design Ruler") as the command name. CLAUDE.md consistently uses "Measure" for the command name while preserving "Design Ruler" as the extension name.</done>
</task>

<task type="auto">
  <name>Task 3: Verify build succeeds</name>
  <files></files>
  <action>
    1. Run `cd /Users/haythem/Developer/design-ruler && npm run build` to verify:
       - Raycast resolves `"name": "measure"` to `src/measure.ts` correctly
       - The Swift bridge import still works
       - No TypeScript errors from the rename
    2. If build fails due to stale cache: `rm -rf swift/Ruler/.raycast-swift-build` and retry
  </action>
  <verify>`npm run build` exits with code 0 (no errors)</verify>
  <done>Extension builds cleanly with the renamed command</done>
</task>

</tasks>

<verification>
1. `npm run build` succeeds with no errors
2. `grep '"name": "measure"' package.json` confirms command name
3. `grep '"title": "Measure"' package.json` confirms command title
4. `grep '"title": "Design Ruler"' package.json` confirms extension title preserved
5. `test -f src/measure.ts && ! test -f src/design-ruler.ts` confirms file rename
6. No Swift source references "Design Ruler" as a command name
</verification>

<success_criteria>
- The command is named "Measure" in package.json (both name and title fields)
- The TypeScript entry point is src/measure.ts
- The extension name remains "Design Ruler"
- All Swift doc comments reference "Measure" instead of "Design Ruler" for the command
- CLAUDE.md consistently distinguishes "Design Ruler" (extension) from "Measure" (command)
- The extension builds successfully
</success_criteria>

<output>
After completion, create `.planning/quick/2-rename-design-ruler-command-to-measure/2-SUMMARY.md`
</output>
