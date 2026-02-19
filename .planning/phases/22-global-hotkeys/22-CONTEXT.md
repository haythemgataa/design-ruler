# Phase 22: Global Hotkeys - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Configurable global keyboard shortcuts that trigger overlay commands from any application. Uses KeyboardShortcuts 2.4.0 (already decided). Recorder controls live in Settings; no onboarding window in this phase.

</domain>

<decisions>
## Implementation Decisions

### Recorder control behavior
- Inline recorder control (macOS System Settings style) — text field-like, says "Record Shortcut" when unassigned, captures next key combo when clicked
- At least one modifier key required (Cmd, Ctrl, Option, Shift) — prevents accidental triggers from bare keys
- Clear shortcut via X button next to recorder OR pressing Delete/Backspace while recorder is focused (both work)
- Remove the existing Shortcuts tab from Settings — each shortcut recorder lives in its respective mode section (Measure shortcut in Measure section, Alignment Guides shortcut in Alignment Guides section)

### Conflict handling
- Internal conflicts (same shortcut for both commands): block with inline message "Already assigned to [other command]" and reject
- System shortcut conflicts (Cmd+Space, Cmd+Tab, etc.): warn with yellow warning "This may conflict with [system feature]" but allow user to proceed
- External app conflicts (registration failure): show a notice in Settings that the shortcut couldn't be registered
- Use KeyboardShortcuts 2.4.0 built-in conflict detection — trust library defaults, no custom validation layer

### Hotkey-while-overlay-active
- Same-command hotkey (e.g., Measure hotkey while Measure active): toggle off — dismiss overlay instantly (same as ESC, no fade-out)
- Cross-command hotkey (e.g., Alignment Guides hotkey while Measure active): seamless switch reusing existing screen captures if technically feasible. Fallback if not: close current overlay, re-capture, open the other command (small delay acceptable)
- Menu bar dropdown: non-interactive during overlays (overlays capture all input)
- Hotkey toggle-off: instant dismiss, same behavior as ESC

### Unassigned state experience
- No first-launch nudge in this phase — user discovers shortcuts in Settings (onboarding window deferred to separate phase)
- Recorder shows "Record Shortcut" placeholder text when unassigned
- Menu bar dropdown shows assigned hotkey next to each command (e.g., "Measure  ⌘⇧M") — matches native macOS menu conventions
- When no shortcut assigned, dropdown just shows the command name without a shortcut hint

### Claude's Discretion
- Keycap rendering style for assigned shortcuts in Settings (styled caps vs plain text)
- Exact layout/spacing of recorder controls within mode sections
- How to surface the "couldn't register" notice (inline vs toast vs alert)

</decisions>

<specifics>
## Specific Ideas

- Shortcut display in menu bar dropdown should match native macOS menus (right-aligned shortcut symbols)
- "Record Shortcut" placeholder style should feel like macOS System Settings keyboard shortcut recorder
- Cross-command switching (reusing captures) is the ideal UX — researcher should investigate whether OverlayCoordinator architecture supports swapping overlay windows without re-capturing

</specifics>

<deferred>
## Deferred Ideas

- First-launch onboarding window combining screen recording permission request + shortcut setup — separate phase/effort
- Keycap-style shortcut rendering in settings (could be enhanced later)

</deferred>

---

*Phase: 22-global-hotkeys*
*Context gathered: 2026-02-19*
