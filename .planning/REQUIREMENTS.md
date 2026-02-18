# Requirements: Design Ruler

**Defined:** 2026-02-18
**Core Value:** Instant, accurate pixel inspection of anything on screen — zero friction from invoke to dimension readout, whether launched from Raycast or a global hotkey.

## v2.0 Requirements

Requirements for standalone app milestone. Each maps to roadmap phases.

### Build System

- [ ] **BUILD-01**: Shared Swift code extracted into DesignRulerCore library target in Package.swift
- [ ] **BUILD-02**: Standalone app built via Xcode project referencing DesignRulerCore as local package
- [ ] **BUILD-03**: Raycast extension still builds successfully via `ray build` after restructure

### App Lifecycle

- [ ] **LIFE-01**: OverlayCoordinator supports RunMode flag (raycast vs standalone) gating `app.run()` and `NSApp.terminate()`
- [ ] **LIFE-02**: Overlay session ends cleanly without killing the standalone app process
- [ ] **LIFE-03**: CursorManager state resets at the start of every new overlay session

### Menu Bar

- [ ] **MENU-01**: User sees NSStatusItem icon in the menu bar when standalone app is running
- [ ] **MENU-02**: User can click menu bar icon to see dropdown with Measure and Alignment Guides commands
- [ ] **MENU-03**: Menu bar icon changes state while an overlay session is active
- [ ] **MENU-04**: User can click a command in the dropdown to launch the corresponding overlay

### Settings

- [ ] **SETT-01**: User can open a Settings window from the menu bar dropdown
- [ ] **SETT-02**: User can toggle hideHintBar preference in Settings
- [ ] **SETT-03**: User can change corrections mode (smart/include/none) in Settings
- [ ] **SETT-04**: User can record custom keyboard shortcuts for both commands in Settings
- [ ] **SETT-05**: User can toggle launch at login in Settings
- [ ] **SETT-06**: User can view About Design Ruler window from the menu bar
- [ ] **SETT-07**: User can check for updates via Sparkle from the menu bar

### Global Hotkeys

- [ ] **HOTK-01**: User can trigger Measure via a configured global keyboard shortcut
- [ ] **HOTK-02**: User can trigger Alignment Guides via a configured global keyboard shortcut
- [ ] **HOTK-03**: App ships with no default hotkeys — user must assign on first launch

### Coexistence

- [ ] **COEX-01**: App detects when Raycast extension is also installed/running
- [ ] **COEX-02**: User sees a one-time nudge recommending they keep only one (Raycast recommended)

### Distribution

- [ ] **DIST-01**: App is code-signed with Developer ID
- [ ] **DIST-02**: App is notarized for Gatekeeper approval
- [ ] **DIST-03**: DMG installer created via create-dmg
- [ ] **DIST-04**: GitHub Actions CI workflow automates build, sign, notarize, and DMG creation

## Future Requirements

Deferred to after v2.0.

### Auto-Update

- **UPDATE-01**: App auto-checks for updates on launch via Sparkle appcast
- **UPDATE-02**: User can configure update check frequency

### Distribution Expansion

- **DISTX-01**: App available via Homebrew cask

## Out of Scope

| Feature | Reason |
|---------|--------|
| Copy dimensions to clipboard | Inspection tool, not measurement export |
| AX-based detection | Complexity with minimal benefit over image-based |
| Snap-to-edge cursor | Disorienting; arrow-key skipping is better |
| App Store distribution | Sandbox requirement blocks CGEventTap and CGWindowListCreateImage |
| Multiple simultaneous overlay sessions | One session at a time matches Raycast behavior |
| Custom menu bar icon themes | Placeholder icon now, user provides final art later |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUILD-01 | — | Pending |
| BUILD-02 | — | Pending |
| BUILD-03 | — | Pending |
| LIFE-01 | — | Pending |
| LIFE-02 | — | Pending |
| LIFE-03 | — | Pending |
| MENU-01 | — | Pending |
| MENU-02 | — | Pending |
| MENU-03 | — | Pending |
| MENU-04 | — | Pending |
| SETT-01 | — | Pending |
| SETT-02 | — | Pending |
| SETT-03 | — | Pending |
| SETT-04 | — | Pending |
| SETT-05 | — | Pending |
| SETT-06 | — | Pending |
| SETT-07 | — | Pending |
| HOTK-01 | — | Pending |
| HOTK-02 | — | Pending |
| HOTK-03 | — | Pending |
| COEX-01 | — | Pending |
| COEX-02 | — | Pending |
| DIST-01 | — | Pending |
| DIST-02 | — | Pending |
| DIST-03 | — | Pending |
| DIST-04 | — | Pending |

**Coverage:**
- v2.0 requirements: 26 total
- Mapped to phases: 0
- Unmapped: 26

---
*Requirements defined: 2026-02-18*
*Last updated: 2026-02-18 after initial definition*
