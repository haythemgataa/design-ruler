# Phase 20: Menu Bar Shell - Context

**Gathered:** 2026-02-18
**Status:** Ready for planning

<domain>
## Phase Boundary

NSStatusItem with dropdown menu that launches both overlay commands (Measure and Alignment Guides) from a persistent menu bar app. The app survives ESC — overlay sessions end but the process stays alive. Settings window and global hotkeys are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Menu bar icon
- Use an SF Symbol as placeholder icon (user will provide custom asset later)
- Template-style image — adapts to light/dark menu bar automatically
- Standard 18x18pt size (matches Bartender, Rectangle, iStat conventions)
- Active-overlay state: filled variant of the same SF Symbol (e.g. ruler → ruler.fill)
- Icon reverts to idle state instantly on ESC (no delay)
- Since all screens are captured by the overlay, the icon state change is only observable during brief setup/teardown — not while the overlay is running

### Dropdown menu content
- Menu structure (top to bottom):
  1. Measure
  2. Alignment Guides
  3. Separator
  4. Settings... (disabled/grayed out — wired in Phase 21)
  5. Separator
  6. Quit Design Ruler
- Labels match Raycast command names exactly: "Measure" and "Alignment Guides"
- No header or app name at top of menu (jump straight to commands)
- No keyboard shortcut hints in this phase (added in Phase 22)

### Session-active behavior
- Fullscreen overlay captures ALL screens — menu bar is inaccessible during a session
- No need for in-session menu interaction (ESC is the only exit)
- Icon state (idle → filled) changes before overlay starts, reverts instantly on ESC

### Menu interaction style
- Standard NSMenu dropdown (not custom NSPopover)
- Left-click opens the menu — user picks which command (like Rectangle, Bartender)
- Quit immediately — no confirmation dialog
- No special double-click or right-click behavior

### Claude's Discretion
- Tooltip text (whether to show "Design Ruler" on hover or skip it)
- Exact SF Symbol choice for the placeholder icon
- Any minor polish details (menu item icons, etc.)

</decisions>

<specifics>
## Specific Ideas

- Menu behavior should feel like Rectangle or Bartender — standard macOS menu bar app conventions
- LSUIElement = YES already set in Info.plist from Phase 18 (no Dock icon, no Cmd+Tab entry)
- AppDelegate already exists from Phase 19 with standalone mode wiring

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 20-menu-bar-shell*
*Context gathered: 2026-02-18*
