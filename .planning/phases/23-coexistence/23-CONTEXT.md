# Phase 23: Coexistence - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect when the Design Ruler Raycast extension is also installed and show a one-time info banner in the Settings window. Detection is lazy (only on Settings open). No popup alerts, no onboarding window (deferred).

</domain>

<decisions>
## Implementation Decisions

### Nudge messaging & tone
- Friendly heads-up tone — not a warning, not pushy
- Neutral message: "You have both installed. Pick whichever you prefer."
- No explanation of why running both could be an issue — keep it simple
- Single "Got it" dismiss button — no "Open Raycast" or action buttons
- No mention of conflicts, duplicate shortcuts, etc.

### Nudge placement
- Info banner at the top of the General tab in Settings
- NOT an NSAlert or system dialog — inline banner within the Settings view
- Once dismissed with "Got it", the banner disappears permanently from Settings
- If the user later uninstalls the Raycast extension, the banner auto-disappears (re-check on Settings open)

### Nudge timing
- Lazy detection: only check for the Raycast extension when Settings is opened
- No detection on app launch — no background checks
- No delay or grace period — show immediately if detected when Settings opens
- If the user never opens Settings, no detection happens

### Dismissal behavior
- "Got it" dismisses the banner forever (persisted in UserDefaults)
- Dismissed means dismissed permanently — even if the extension is reinstalled later
- If not yet dismissed: banner visibility depends on live detection (extension present = show, extension removed = hide)

### Claude's Discretion
- Banner visual design (color, icon, layout within the General tab)
- Exact detection heuristic for the Raycast extension (filesystem path check)
- UserDefaults key naming for the dismissed flag

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The banner should feel like a helpful FYI, not an upsell or warning.

</specifics>

<deferred>
## Deferred Ideas

- Onboarding window — user wants the coexistence notice to also appear in a future onboarding flow. This is a separate phase/feature.

</deferred>

---

*Phase: 23-coexistence*
*Context gathered: 2026-02-19*
