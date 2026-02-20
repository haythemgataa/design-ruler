# Phase 21: Settings and Preferences - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Settings window with all overlay preferences, launch at login, About information, and Sparkle update check — accessible from the menu bar dropdown. Global hotkeys configuration is Phase 22 (Shortcuts section exists in the window but is populated in Phase 22).

</domain>

<decisions>
## Implementation Decisions

### Settings window design
- Single scrollable page, no tabs — all sections visible at once
- 4 sections on the page: General, Measure, Shortcuts, About
- macOS grouped style — rounded boxes with section headers (like System Settings groups)
- Always centered on screen when opened (no position memory)
- Shortcuts section exists as a placeholder in Phase 21 — populated with hotkey recorders in Phase 22

### Preference controls
- Hide Hint Bar: toggle switch (On/Off, macOS System Settings style)
- Corrections Mode: radio buttons showing all three options (Smart, Include, None)
- Storage: UserDefaults only, local — no iCloud sync

### Section assignments
- **General section:** Launch at Login (toggle, top of page), Hide Hint Bar (toggle), Auto-check for Updates (toggle)
- **Measure section:** Corrections Mode (radio buttons: Smart, Include, None)
- **Shortcuts section:** Placeholder for Phase 22 global hotkey recorders
- **About section:** App icon, name, version, copyright, GitHub link, website/contact, Check for Updates button

### Launch at Login
- Enabled by default on first launch (standard for menu bar apps)
- Toggle lives in the General section at the top of the settings page
- Uses SMAppService.mainApp (decided in PROJECT.md)

### About / Check for Updates
- About section shows: app icon, name, version number, copyright, GitHub link, website/contact
- Check for Updates: both a menu bar dropdown item AND a button in the About section
- Auto-check for updates: user choice via toggle in General section (Sparkle's SUUpdater automaticallyChecksForUpdates)

### Claude's Discretion
- Exact spacing, padding, and typography within sections
- Settings window dimensions
- SwiftUI vs AppKit implementation choice for the settings window
- How the Shortcuts placeholder section communicates "configure in Phase 22"

</decisions>

<specifics>
## Specific Ideas

- Visual style should match macOS System Settings grouped appearance (rounded boxes per section)
- Toggle switches should look and behave like native macOS toggles
- Radio buttons for corrections mode so all options are visible without clicking

</specifics>

<deferred>
## Deferred Ideas

- Welcome window / first-launch onboarding — user wants a one-time window explaining the app on first launch. This is a separate capability requiring its own design (layout, content, illustrations, dismiss behavior). Consider as a future phase or part of Phase 24 (Distribution).

</deferred>

---

*Phase: 21-settings-and-preferences*
*Context gathered: 2026-02-19*
