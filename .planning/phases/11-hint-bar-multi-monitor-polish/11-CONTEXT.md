# Phase 11: Hint Bar + Multi-Monitor + Polish - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Final integration layer for alignment guides: hint bar with guide-specific content using the existing liquid glass infrastructure, multi-monitor support with per-screen independent overlays, and polish fixes for issues from Phases 9-10. Covers REQ-AG-11 through REQ-AG-16. Does NOT add new interaction mechanics or change core guide placement/removal behavior.

</domain>

<decisions>
## Implementation Decisions

### Hint bar content & style
- Identical style to inspect hint bar — same liquid glass material, same launch-to-collapse animation
- Expanded text: "Press [tab] to switch direction, [space bar] to change color. [esc] to exit"
- Collapsed: [tab][space]  [esc] keycaps only
- Same bottom ↔ top repositioning when cursor approaches
- Same 3-second expanded display before collapsing on first mouse move

### Multi-monitor line management
- One window per screen with independent frozen screenshot overlays
- Preview line follows cursor to any screen — same behavior everywhere
- Placed lines persist and remain visible on their screen even when cursor moves away
- Interaction (hover/remove) only on the active screen where cursor currently is
- Color selection is shared across all screens — spacebar cycling applies globally
- Reuse same capture-before-window pattern as inspect command

### Exit behavior
- ESC closes all windows instantly — no exit animation, same as inspect command

### Performance
- CPU must stay under 5% with many lines placed
- CAShapeLayer-based rendering throughout (REQ-AG-15)

### Polish fixes (from Phases 9-10)
- **Remove state stuck**: after click-to-remove, if cursor doesn't move quickly, the view gets stuck in remove state (red pill with "Remove" text, preview line hidden). Must reset state properly after removal completes.
- **Pill opacity**: increase alignment guide pill opacity to match the inspect command's pill opacity
- **Color circle borders**: 2px border for default circles, 3px border for the active/selected circle. Border stroke position: Claude's discretion for what looks cleanest.
- **Dynamic color circle colors**: use #E2E2E2 and #292929 for the dynamic (difference blend) circle instead of current half-black/half-white
- **Cursor types**: use NSCursor.resizeLeftRight (↔) for vertical preview line, NSCursor.resizeUpDown (↕) for horizontal preview line (replacing whatever is currently used)

### Claude's Discretion
- Border stroke position on color circles (centered vs inset)
- Performance optimization approach for many placed lines
- Reuse strategy for shared utilities (CoordinateConverter, PermissionChecker, HintBarView, CursorManager)

</decisions>

<specifics>
## Specific Ideas

- Hint bar is a content swap on the existing infrastructure — no new hint bar architecture needed
- The remove-state-stuck bug is the highest priority polish fix (it breaks the core interaction)
- Dynamic circle colors (#E2E2E2 / #292929) should clearly communicate "adapts to background" without being literal black/white

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-hint-bar-multi-monitor-polish*
*Context gathered: 2026-02-16*
