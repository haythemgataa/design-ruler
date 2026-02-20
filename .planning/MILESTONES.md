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


## v1.2 Alignment Guides (Shipped: 2026-02-16)

**Phases completed:** 3 phases (9-11), 9 plans, 23 tasks
**Timeline:** 6 days (Feb 10 - Feb 16, 2026)
**Codebase:** 4,741 LOC Swift (1,630 new for alignment guides)
**Git range:** `1d2a8f8`..`144075c`

**Key accomplishments:**
- End-to-end alignment guides feature: preview line with difference blend, Tab direction toggle, click placement with position pills, resize cursor
- Hover-to-remove interaction with 5px hit testing, red+dashed visual feedback, pointing hand cursor, and shrink-toward-click animation
- Color cycling with 5 presets (dynamic, red, green, orange, blue) and arc-based visual indicator with debounced auto-hide
- Multi-monitor support with capture-before-window for all screens, global color state sync via callbacks
- Hint bar content infrastructure with HintBarMode enum supporting both inspect and alignment guides keycaps
- Polish: remove-state bug fix, color circle borders/animation, keycap rendering, multi-monitor coordinate conversion

---


## v1.3 Code Unification (Shipped: 2026-02-17)

**Phases completed:** 6 phases (12-17), 10 plans, 19 tasks
**Timeline:** 7 days (Feb 10 - Feb 17, 2026)
**Codebase:** ~3,300 LOC Swift (+624 net lines: +2,097 / -1,473)
**Git range:** `8dcde60`..`908066e`

**Key accomplishments:**
- Centralized all design tokens (colors, radii, durations, blend mode) into DesignTokens.swift — zero inline magic numbers
- Created PillRenderer with 3 factory methods, eliminating 388 lines of duplicated pill rendering across CrosshairView, GuideLine, SelectionOverlay
- Extracted OverlayCoordinator base class — Ruler.swift dropped from 170 to 71 lines, AlignmentGuides.swift from 205 to 82 lines
- Extracted OverlayWindow base class with shared window config, tracking, throttle, hint bar — ~200 lines of window duplication eliminated
- Unified CursorManager from 4 to 6 states, replacing AlignmentGuidesWindow's parallel cursor system
- Cleaned up HintBarContent duplication (HintBarTextStyle) and CursorManager documentation accuracy

---


## v2.0 Standalone App (Shipped: 2026-02-20)

**Phases completed:** 6 phases (18-23), 14 plans
**Timeline:** 3 days (Feb 18 - Feb 20, 2026)
**Codebase:** ~5,562 LOC Swift + 73 LOC TypeScript
**Git range:** `1b0e2d0`..`29978e0`
**Changes:** 45 files changed, +1,353 / -384 lines

**Key accomplishments:**
- Extracted DesignRulerCore SPM library shared by both Raycast extension and standalone Xcode app
- Added RunMode lifecycle so overlay sessions end without killing the standalone app process
- Created persistent menu bar app with NSStatusItem dropdown for both overlay commands
- Built SwiftUI settings window with preferences, launch-at-login, and Sparkle auto-updates
- Implemented configurable global hotkeys via KeyboardShortcuts with conflict detection and toggle/cross-switch dispatch
- Configured code signing, notarization, and dual GitHub Actions CI workflows for automated DMG distribution

---

