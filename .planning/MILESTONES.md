# Milestones

## v1.0 Enhancement (Shipped: 2026-02-13)

**Phases completed:** 5 phases, 5 plans, 9 tasks
**Timeline:** 3 days (Feb 10 - Feb 13, 2026)
**Codebase:** 2,428 LOC Swift
**Git range:** `e3ca327`..`08fa8cf`

**Key accomplishments:**
- Eliminated all debug stderr output from production builds (6 fputs calls removed)
- Added 10-minute inactivity watchdog timer preventing zombie processes
- Centralized cursor management into CursorManager state machine with SIGTERM handler
- Added macOS-native damped shake animation for selection snap failure feedback
- Selection pill now clamps to screen bounds with shadow-aware 4px margins
- Help toggle system: backspace dismiss, "?" re-enable, UserDefaults session persistence

---


## v1.1 Hint Bar Redesign (Shipped: 2026-02-14)

**Phases completed:** 3 phases (6-8), 4 plans, 8 tasks
**Timeline:** 4 days (Feb 10 - Feb 14, 2026)
**Codebase:** 8,267 LOC Swift
**Git range:** `4fcb57f`..`eb29cfd`

**Key accomplishments:**
- Removed help toggle system (backspace-dismiss/"?" re-enable), leaving hideHintBar preference as sole control
- Added glass panel hint bar with NSGlassEffectView (macOS 26+) / NSVisualEffectView fallback and adaptive brightness sampling
- Updated keycap layout with new dimensions (arrows 26x11, shift 40x25, ESC 32x25) and ESC red tint
- Built collapsed two-section layout (arrows+shift | ESC) with BarState enum, 4px gap, fixed 48px height
- Implemented liquid glass morph animation via SwiftUI GlassEffectContainer with two-layer rendering hack for smooth keycap sliding
- Added 3-second minimum expanded display before collapse triggers on first mouse move

---

