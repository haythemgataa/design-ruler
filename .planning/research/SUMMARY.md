# Project Research Summary

**Project:** Design Ruler UI Enhancement Milestone
**Domain:** macOS pixel inspector (Raycast extension) — polish and robustness enhancements
**Researched:** 2026-02-13
**Confidence:** HIGH

## Executive Summary

This milestone adds five polish and robustness enhancements to an existing Raycast extension (Swift + AppKit + Core Animation). The extension is a mature macOS pixel inspector with a complex cursor management system, GPU-composited crosshair overlay, and edge detection engine. Research shows that the enhancements integrate cleanly into the existing architecture with zero new dependencies — all APIs (CAKeyframeAnimation, NSCursor, DispatchSourceTimer, UserDefaults, CALayer) are already in use and well within macOS 13+ deployment target.

The recommended approach is a refactor-first strategy: centralize the scattered NSCursor state management (18 call sites across 3 files) before adding new features that interact with cursors. This prevents the primary risk identified in research — unbalanced NSCursor push/pop/hide/unhide calls that can leave the user's cursor permanently hidden after exit. The existing codebase already has defensive resets for this issue (RulerWindow.swift:225), confirming it's a real problem. A centralized CursorManager eliminates the root cause.

Key risks: NSCursor stack imbalance (critical), DispatchSourceTimer deallocation crash (critical), and CALayer position drift from additive animations (moderate). All have well-documented solutions. The codebase is already sophisticated (warm-up capture for CGWindowListCreateImage, GPU-composited CAShapeLayer rendering, skip stabilization algorithm) — the enhancements continue this pattern without architectural rewrites.

## Key Findings

### Recommended Stack

All five enhancements use frameworks already imported in the project. Zero new dependencies required.

**Core technologies:**
- **CAKeyframeAnimation (macOS 10.5+)** — shake animation with additive transform.translation.x and damped oscillation values matching macOS login rejection idiom
- **NSCursor push/pop/hide/unhide (macOS 10.0+)** — centralized state enum prevents stack imbalance; hide counter tracking required for safe exit
- **DispatchSourceTimer (macOS 10.12+)** — process watchdog for 5-minute inactivity timeout; must resume immediately after creation to avoid deallocation crash
- **CALayer frame clamping (macOS 10.5+)** — manual math clamping (not masksToBounds) to keep overlay elements within screen bounds without clipping shadows
- **UserDefaults.standard (macOS 10.0+)** — preference persistence with fully-qualified keys; current usage is empirically sound

All APIs are stable, available since macOS 10.0-10.12 (target is macOS 13+), and already used elsewhere in the codebase (e.g., CAKeyframeAnimation in HintBarView slide animation, UserDefaults for hint bar dismiss state).

### Expected Features

**Must have (table stakes):**
- **Shake-to-reject for invalid selections** — macOS convention for "no" feedback; current silent disappearance feels broken
- **Cursor restoration on all exit paths** — losing cursor is the worst UX bug in overlay tools; unbalanced hide/unhide is already a known issue (MEMORY.md zombie processes)
- **Process self-termination on inactivity** — zombie processes are documented (MEMORY.md: "Ruler processes don't auto-terminate if NSApp.terminate(nil) never fires")
- **Structured logging (replace fputs)** — debug output in production is unprofessional; unstructured logs waste time

**Should have (competitive):**
- **"?" key to toggle help overlay** — discoverable help without permanent screen real estate
- **Startup safety timeout (10s)** — prevents completely stuck states from bad captures
- **SIGTERM handler for clean Raycast shutdown** — seamless integration with Raycast's process management

**Defer (v2+):**
- **Transient auto-dismiss hint bar** — current persistent-until-backspace pattern already works; auto-dismiss adds edge cases for minimal benefit

### Architecture Approach

Enhancements integrate into the existing singleton-driven architecture (Ruler owns lifecycle, RulerWindow routes events, CrosshairView owns rendering layers, SelectionManager owns selection state). No structural changes required.

**Major components affected:**
1. **CursorManager (new, in Utilities/)** — centralized enum-based state machine for NSCursor push/pop/hide/unhide; owned by Ruler, passed to RulerWindows; replaces 18 scattered call sites
2. **SelectionOverlay (enhanced)** — adds `shakeAndRemove()` method using CAKeyframeAnimation with isAdditive=true; called from SelectionManager.endDrag() on snap failure
3. **Ruler (enhanced)** — adds DispatchSourceTimer watchdog (5-minute inactivity check) and SIGTERM handler; coordinates CursorManager.reset() on exit
4. **CrosshairView (minor)** — calls CursorManager.transition() instead of direct NSCursor calls; existing pill clamping logic extended with manual frame clamping function
5. **Debug logging** — wrap existing fputs calls with #if DEBUG guards (not os_log, to avoid import overhead for 6 call sites in a short-lived process)

**Critical invariant preserved:** CrosshairView still owns resetCursorRects() (NSView lifecycle method). CursorManager only handles imperative push/pop/hide/unhide stack, not cursor rects.

### Critical Pitfalls

1. **NSCursor push/pop stack imbalance** — every push() must have exactly one matching pop(); system alerts or deactivate events can interrupt drag/hover flows, leaving stale cursors on stack. Prevention: enum-based state machine with transition() method that handles push/pop pairs atomically. Force-reset on exit.

2. **NSCursor hide/unhide counter mismatch** — hide() increments internal counter, unhide() decrements; calling hide() twice requires two unhide() calls. If counts don't match at exit, user's cursor stays hidden system-wide. Prevention: track hideCount explicitly in CursorManager, call balancedUnhide() until count reaches zero in reset().

3. **DispatchSourceTimer deallocation crash** — deallocating a suspended timer crashes with "BUG IN CLIENT OF LIBDISPATCH: Release of an inactive object". Prevention: always call resume() immediately after makeTimerSource(), or use DispatchQueue.main.asyncAfter for one-shot delays (simpler lifecycle).

4. **CALayer position drift with non-additive animations** — CAKeyframeAnimation affects presentation layer only; model layer retains original position, causing snap-back unless fillMode=.forwards (which causes model/presentation divergence). Prevention: use isAdditive=true with zero-centered values for shake animations.

5. **CATransaction completion block timing with nested transactions** — setCompletionBlock fires when ALL animations in the transaction complete, including nested. Prevention: use separate CATransaction blocks for independent animations (existing pattern: lines instant, pill animated).

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Debug Cleanup + Process Safety
**Rationale:** Zero dependencies, trivial changes, reduces noise before refactor. Debug cleanup (#if DEBUG guards) prevents accidental removal of diagnostic context during subsequent work. Process timeout addresses known issue (MEMORY.md zombie processes) with minimal complexity.

**Delivers:**
- All fputs calls wrapped with #if DEBUG (keep HIGH-value diagnostics in EdgeDetector.swift, remove LOW-value traces)
- 5-minute inactivity timeout with DispatchQueue.main.asyncAfter (simpler than DispatchSourceTimer for one-shot delay)
- SIGTERM handler for clean Raycast shutdown
- Process watchdog starts in Ruler.run(), cancelled in Ruler.handleExit()

**Addresses:** Table stakes (process self-termination), differentiator (SIGTERM handler)

**Avoids:** Pitfall 8 (losing diagnostic context), Pitfall 3 (timer deallocation crash — use asyncAfter instead)

**Research flag:** SKIP research (standard patterns, well-documented)

---

### Phase 2: Centralized Cursor Management
**Rationale:** Prevents the most user-hostile bug (stuck hidden cursor). Invasive refactor that touches 18 call sites across 3 files — do this before adding new cursor-dependent features so they write against clean API from the start.

**Delivers:**
- CursorManager class with enum CursorState: .system, .hidden, .crosshair, .pointingHand
- transition(to:) method handles all push/pop/hide/unhide atomically
- reset() method force-unwinds stack on exit (balancedUnhide() loop, balancedPop() loop)
- Owned by Ruler singleton, passed to each RulerWindow at creation

**Addresses:** Table stakes (cursor restoration on all exit paths)

**Avoids:** Pitfall 1 (push/pop imbalance), Pitfall 2 (hide/unhide counter mismatch)

**Research flag:** SKIP research (documented NSCursor behavior, existing codebase patterns)

---

### Phase 3: Shake Animation
**Rationale:** Pure polish, independent of CursorManager. Small, satisfying enhancement that uses existing CAKeyframeAnimation patterns (HintBarView already uses CAKeyframeAnimation for slide).

**Delivers:**
- SelectionOverlay.shakeAndRemove() method
- CAKeyframeAnimation with isAdditive=true, transform.translation.x keyPath
- Damped oscillation values: [0, -6, 6, -4, 4, -2, 2, 0], duration 0.35s
- Chained with existing remove(animated:) fade-out
- Called from SelectionManager.endDrag() on snap failure

**Addresses:** Table stakes (shake-to-reject animation)

**Avoids:** Pitfall 4 (position drift — use isAdditive=true), Pitfall 5 (completion block timing — separate CATransaction), Pitfall 9 (key collision — use unique key "shakeEffect")

**Research flag:** SKIP research (well-documented CAKeyframeAnimation, existing animation patterns in codebase)

---

### Phase 4: Bounds Clamping (Polish)
**Rationale:** Low priority polish, independent of other phases. Current pill flip logic already handles left/right and above/below, this adds hard clamping at extreme corners.

**Delivers:**
- clampedFrame(_:within:padding:) pure function
- Applied after existing pill flip logic in CrosshairView.layoutPill()
- Manual frame clamping (not masksToBounds — preserves shadows, avoids offscreen rendering)

**Addresses:** Differentiator (polished edge handling)

**Avoids:** Pitfall (using masksToBounds which clips shadows)

**Research flag:** SKIP research (straightforward math)

---

### Phase 5: Help Toggle (Optional)
**Rationale:** Nice to have, lowest priority. Current hint bar already works. Adding transient "Press ? for help" with toggle creates new UI layer but minimal complexity.

**Delivers:**
- Two CALayers on CrosshairView (transientHintBg, transientHintText)
- showTransientHint() / hideTransientHint(animated:) methods
- "?" key handler in RulerWindow.keyDown shows full HintBarView
- Auto-fade after 3s using DispatchQueue.main.asyncAfter

**Addresses:** Differentiator ("?" key toggle help)

**Avoids:** Pitfall 3 (use asyncAfter not DispatchSourceTimer for one-shot delay)

**Research flag:** SKIP research (CALayer patterns already used, simple lifecycle)

---

### Phase Ordering Rationale

- **Phase 1 first:** Reduces noise and addresses known issue (zombie processes) with zero risk
- **Phase 2 second:** Most invasive refactor; doing it early means Phases 3-5 write against clean cursor API
- **Phases 3-4 in parallel:** Independent of each other; both are self-contained enhancements to existing components
- **Phase 5 last:** Depends on clean RulerWindow.keyDown handler (touched by Phase 2); lowest priority feature

**Critical path:** Phase 1 → Phase 2 → (Phase 3 || Phase 4) → Phase 5

**Phases 1 and 2 can be combined** if desired (both are robustness improvements), but keeping separate allows incremental testing of cursor refactor.

### Research Flags

**All phases: SKIP research-phase.** Rationale:
- All APIs already in use elsewhere in codebase (CAKeyframeAnimation in HintBarView, UserDefaults for hint bar dismiss, NSCursor calls throughout)
- All patterns well-documented in Apple Developer Documentation
- All pitfalls have known solutions with high confidence
- Research files already provide implementation guidance

Standard patterns dominate: enum-based state machines, additive Core Animation, balanced stack management, pure function frame clamping. No niche domains, no sparse documentation, no complex integrations requiring deeper research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs available since macOS 10.0-10.12, well within macOS 13+ target; already imported in project |
| Features | HIGH | Table stakes informed by macOS HIG and community conventions (shake-to-reject, cursor restoration, process timeout); differentiators are polish |
| Architecture | HIGH | Direct analysis of existing codebase; enhancements fit naturally into singleton-driven architecture with zero structural changes |
| Pitfalls | HIGH | All critical pitfalls (NSCursor balance, timer deallocation, CALayer position drift) have documented solutions with multiple independent sources |

**Overall confidence:** HIGH

Research is comprehensive and actionable. All five enhancements have clear implementation paths with known risks and documented mitigations. No external dependencies, no API availability concerns, no architectural rewrites.

### Gaps to Address

**UserDefaults domain in Raycast Swift binary (Pitfall 7):** The current usage (UserDefaults.standard with fully-qualified keys) works empirically but the domain behavior for Raycast Swift binaries is not officially documented. This is a LOW-priority gap — current approach is sound, but if preferences start disappearing across extension reinstalls, switch to file-based persistence (~/.config/design-ruler/state.json).

**CAKeyframeAnimation keyTimes/values count mismatch (Pitfall 11):** Research suggests asserting `values.count == keyTimes.count` in debug builds. This is a code-quality concern, not a research gap — implement during Phase 3.

**Shake animation during pill flip transition (Pitfall 10):** Theoretical concern (shaking while pill is mid-flip creates compound motion). Research suggests checking `isFlipping` boolean before triggering shake. Test visually during Phase 3; if not an issue in practice, skip the guard.

No gaps block implementation. All can be handled during execution with the guidance provided in research files.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: CAKeyframeAnimation, NSCursor (push/pop/hide/unhide), DispatchSourceTimer, UserDefaults
- Design Ruler codebase: direct analysis of Ruler.swift, RulerWindow.swift, CrosshairView.swift, SelectionOverlay.swift, HintBarView.swift, EdgeDetector.swift
- MEMORY.md: documents known issue with zombie processes requiring manual pkill

### Secondary (MEDIUM confidence)
- [Cocoa Is My Girlfriend: Window Shake Effect](https://www.cimgf.com/2008/02/27/core-animation-tutorial-window-shake-effect/) — canonical macOS shake parameters (3 oscillations, 0.3s duration, 4% amplitude)
- [Sam Soffes: Aggressively Hiding the Cursor](https://soff.es/blog/aggressively-hiding-the-cursor) — NSCursor.hide() balance behavior and fullscreen control patterns
- [objc.io: Animations Explained](https://www.objc.io/issues/12-animations/animations-explained/) — CALayer model/presentation layer divergence
- [Ole Begemann: Prevent CAAnimation Snap Back](https://oleb.net/blog/2012/11/prevent-caanimation-snap-back/) — isAdditive=true pattern for position animations
- [libdispatch issue #604](https://github.com/apple/swift-corelibs-libdispatch/issues/604) — DispatchSourceTimer deallocation crash behavior
- [Apple Developer Forums](https://developer.apple.com/forums/thread/15902) — DispatchSource suspend/resume reference counting

### Tertiary (LOW confidence)
- [Swift Discovery: Shake NSView](https://onmyway133.com/posts/how-to-shake-nsview-in-macos/) — community implementation patterns (validated against codebase patterns)
- [CALayer.com: CATransaction in Depth](https://www.calayer.com/core-animation/2016/05/17/catransaction-in-depth.html) — nested transaction behavior

---
*Research completed: 2026-02-13*
*Ready for roadmap: yes*
