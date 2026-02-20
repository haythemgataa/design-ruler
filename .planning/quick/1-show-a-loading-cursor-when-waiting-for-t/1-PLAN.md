---
phase: quick
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - swift/Ruler/Sources/Ruler.swift
autonomous: true
must_haves:
  truths:
    - "User sees a spinning wait cursor immediately after invoking the command"
    - "Wait cursor disappears when the overlay windows appear"
    - "Normal cursor behavior (system crosshair on launch) is unaffected after overlay loads"
  artifacts:
    - path: "swift/Ruler/Sources/Ruler.swift"
      provides: "Wait cursor shown during warmup + capture, removed before window display"
      contains: "NSCursor.wait"
  key_links:
    - from: "swift/Ruler/Sources/Ruler.swift"
      to: "CursorManager"
      via: "Wait cursor cleanup before CursorManager takes over cursor state"
      pattern: "NSCursor\\.wait"
---

<objective>
Show a loading/wait cursor (spinning beachball) during the cold-start delay between the user invoking the Raycast command and the fullscreen overlay appearing.

Purpose: The CGWindowListCreateImage warmup capture + multi-screen capture can take anywhere from 50ms to several seconds on cold start. During this time the user has no feedback that anything is happening. A wait cursor provides immediate visual confirmation.

Output: Modified Ruler.swift with wait cursor shown at start of `inspect()`, removed just before windows are displayed.
</objective>

<execution_context>
@/Users/haythem/.claude/get-shit-done/workflows/execute-plan.md
@/Users/haythem/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@swift/Ruler/Sources/Ruler.swift
@swift/Ruler/Sources/Cursor/CursorManager.swift
@swift/Ruler/Sources/RulerWindow.swift
@CLAUDE.md (Section 3: "NO NSCursor.set() for Persistent Cursors" — only applies to crosshair phase, not pre-window loading)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add wait cursor during warmup and capture in Ruler.swift</name>
  <files>swift/Ruler/Sources/Ruler.swift</files>
  <action>
In the top-level `inspect()` function (before `Ruler.shared.run()`), push a wait cursor:

1. At the very start of `inspect()`, BEFORE the warmup capture, add:
   ```swift
   NSCursor.wait.push()
   ```
   This immediately shows the spinning wait cursor. Using `push()` is safe here because no window exists yet (no cursor rect management to fight with). The `push()` approach is stack-based and cleanly reversible with `pop()`.

2. At the start of `Ruler.run()`, AFTER all captures are complete but BEFORE creating windows (i.e., right before the `let app = NSApplication.shared` line), add:
   ```swift
   NSCursor.pop()  // Remove wait cursor before overlay appears
   ```

Why this placement:
- `push()` in `inspect()` covers both the warmup 1x1 capture AND the `Ruler.shared.run()` multi-screen capture loop
- `pop()` in `run()` removes it before windows appear, so CursorManager's initial `.systemCrosshair` state (managed via `resetCursorRects` / `addCursorRect`) takes over cleanly
- The wait cursor is visible for the entire slow path: warmup + permission check + screen detection + all screen captures

Do NOT use `NSCursor.wait.set()` — it would be overridden. Use the push/pop stack.
Do NOT modify CursorManager — the wait cursor is a pre-CursorManager concern (happens before any window or state machine exists).
  </action>
  <verify>
Build the Swift package to confirm compilation:
```
cd swift/Ruler && swift build 2>&1 | tail -5
```

Then do a full Raycast build:
```
cd /Users/haythem/Developer/design-ruler && ray build 2>&1 | tail -10
```

If the build cache causes issues, clear it first:
```
rm -rf swift/Ruler/.raycast-swift-build && ray build
```
  </verify>
  <done>
- `NSCursor.wait.push()` is called at the start of `inspect()` before any capture work
- `NSCursor.pop()` is called in `run()` after captures complete but before window creation
- Project builds successfully with `ray build`
- CursorManager is not modified (wait cursor is outside its lifecycle)
  </done>
</task>

</tasks>

<verification>
1. Build succeeds: `cd /Users/haythem/Developer/design-ruler && ray build`
2. Code review: `inspect()` starts with `NSCursor.wait.push()`, `run()` has `NSCursor.pop()` before window creation
3. The wait cursor push/pop is balanced (1 push, 1 pop) so no cursor state leaks
</verification>

<success_criteria>
- The extension builds without errors
- A wait cursor is shown immediately when the command is invoked
- The wait cursor is removed before the overlay windows appear
- Existing cursor behavior (system crosshair on launch, hidden after first move) is unchanged
</success_criteria>

<output>
After completion, create `.planning/quick/1-show-a-loading-cursor-when-waiting-for-t/1-SUMMARY.md`
</output>
