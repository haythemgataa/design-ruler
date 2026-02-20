# Project Research Summary

**Project:** Design Ruler — Standalone macOS Menu Bar App
**Domain:** macOS menu bar utility distributing an existing Raycast extension as a persistent background app
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

Design Ruler is being extended from a Raycast-extension-only tool into a dual-distribution product: the existing Raycast extension remains unchanged while a new standalone macOS menu bar app wraps the same overlay/detection Swift code. The approach is architecturally clean — all existing Swift logic (overlay coordinators, edge detection, cursor management, rendering, hint bar) compiles into a shared `DesignRulerCore` library target with zero modifications. A thin `DesignRulerApp` shell (AppDelegate, NSStatusItem, HotkeyManager, SettingsWindow, LoginItemManager) sits on top. The recommended stack is all-native (no new UI frameworks), with two well-scoped third-party dependencies: `KeyboardShortcuts 2.4.0` for user-configurable global hotkeys and `Sparkle 2.8.1` for auto-updates (deferrable to v1.1).

The single largest architectural change is the `OverlayCoordinator` lifecycle. Currently it calls `app.run()` to start the event loop and `NSApp.terminate(nil)` on ESC — correct for a Raycast process that lives and dies per invocation. For the standalone app, the event loop is already running and ESC must close the overlay session without killing the process. Adding a `RunMode` enum (`.raycast` / `.standalone`) to `OverlayCoordinator` gates these two behaviors cleanly. This is a ~15-line addition to one file; it does not require a rewrite. All subsequent standalone-specific behavior (menu bar, hotkeys, settings) is additive.

The highest-risk area is not the overlay integration but the build system. SPM `.executableTarget` cannot produce a notarized `.app` bundle. The standalone app requires an Xcode project alongside the SPM package, with code signing, entitlements, and a notarization CI pipeline. This must be settled in Phase 1 before any feature work begins. A secondary risk is the dual-permission model: screen recording (TCC, triggered by first overlay use) and Accessibility (required for global `CGEventTap` hotkeys) are two separate user prompts that must each have clear in-app UI — silent failure on either is unacceptable and the current `PermissionChecker` does not handle denial gracefully for a persistent app.

---

## Key Findings

### Recommended Stack

The standalone app requires minimal new dependencies. All APIs needed for the menu bar shell (NSStatusItem, NSMenu, SMAppService, NSWorkspace, UserDefaults, NSWindowController, NSHostingView, setActivationPolicy) are available unconditionally at macOS 13+ with no conditional guards needed. Two third-party packages are recommended: `KeyboardShortcuts 2.4.0` (sindresorhus, MIT) wraps Carbon `RegisterEventHotKey` in a type-safe Swift interface with a built-in SwiftUI recorder view and automatic UserDefaults persistence, avoiding the need to build hotkey recording UI manually. `Sparkle 2.8.1` (sparkle-project, XPC-based) is the de-facto update framework for non-App-Store macOS apps; it is deferrable to v1.1.

The standalone app must be an Xcode project (`.xcodeproj`) — not an SPM target — because SPM cannot produce a signed, notarized `.app` bundle with an Info.plist and entitlements file. The existing `Package.swift` is modified minimally: the flat `Sources/` layout is reorganized into `Sources/DesignRulerCore/` (shared library) and `Sources/DesignRulerRaycast/` (Raycast-only `@raycast` entry point shim). The Xcode project references `DesignRulerCore` as a local package dependency. The Raycast build path is verified to work unchanged after the restructure before any app shell work begins.

**Core technologies:**
- `KeyboardShortcuts 2.4.0`: user-configurable global hotkeys — avoids building recorder UI and conflict detection from scratch; uses Carbon internally (no Accessibility permission needed for hotkey registration itself)
- `SMAppService.mainApp`: launch at login — Apple's macOS 13+ replacement for deprecated helper-bundle pattern; no admin password, no helper target
- `CGEventTap`: global hotkey event delivery — required for hotkeys to fire when the app is in the background; requires one-time Accessibility permission prompt
- `create-dmg 1.2.3`: DMG packaging — wraps `hdiutil` for a polished installer with app-drop-link
- `xcrun notarytool 1.1.0`: notarization — standard Xcode CLI tool, already available locally
- `NSStatusItem` + `NSMenu`: menu bar presence — native AppKit, no library needed

### Expected Features

All features were assessed against macOS menu bar app conventions (xScope 4 is the primary reference).

**Must have (table stakes — v1):**
- NSStatusItem menu bar icon with dropdown (Measure, Alignment Guides, Settings..., Quit) — app is invisible without it
- Persistent app lifecycle — overlay exits but app stays in menu bar; without this, standalone offers nothing over Raycast
- Global hotkey registration with user-configurable bindings — the primary trigger mechanism and main differentiator over Raycast
- Hotkey configuration UI in settings (recorder pattern) — no default hotkeys; user must assign; avoids conflicts
- Settings window (General: Launch at Login, Hide Hint Bar; Measure: corrections mode; Shortcuts: hotkey bindings)
- Launch at Login toggle (SMAppService, OFF by default)
- Screen recording permission UX — show actionable dialog with System Settings link on denial; do not show blank/black overlay
- Coexistence nudge — one-time informational alert if Raycast extension detected; suppress after user dismissal

**Should have (competitive — v1.x after validation):**
- Menu bar icon state change during active overlay (icon swap to indicate "in use")
- Hotkey conflict detection — surface "shortcut already in use" with actionable guidance

**Defer (v2+):**
- Clipboard copy on ESC (scope creep; belongs in Raycast extension)
- Multiple hotkey profiles (power user edge case)
- Auto-detect Raycast extension path (LOW confidence; Raycast storage path undocumented)

**Anti-features (do not build):**
- Default hardcoded hotkeys — will conflict with designer tools (Figma/Sketch); always user-configurable
- App Sandbox — incompatible with `CGEventTap` and `CGWindowListCreateImage`; do not sandbox
- NSPopover for menu — requires app activation, causes Dock bounce; use NSMenu
- Dock icon — use `LSUIElement = YES` in Info.plist; do not show app in Dock or Cmd+Tab

### Architecture Approach

The architecture is strictly layered with clean boundaries. `DesignRulerCore` owns all overlay logic and has zero knowledge of the app shell. `AppDelegate` wires the shell components together without touching overlay internals. The overlay coordinators are invoked identically whether triggered from the menu, from a hotkey, or from Raycast — only the `runMode` parameter differs. SwiftUI is used only for settings view content inside `NSWindowController`; the app structure uses AppKit `NSApplicationDelegate` throughout, which is required for compatibility with the overlay system's activation policy and run loop management.

**Major components:**
1. `DesignRulerCore` (SPM library target) — all existing Swift: overlay windows, edge detection, cursor management, rendering, hint bar; zero Raycast dependency
2. `DesignRulerRaycast` (SPM executable target) — two-file shim: `@raycast func inspect()` and `@raycast func alignmentGuides()`; only target Raycast builds
3. `AppDelegate` — app startup/shutdown; wires MenuBarController, HotkeyManager, CoexistenceDetector
4. `MenuBarController` — NSStatusItem + NSMenu; reads AppPreferences; calls coordinator `run(runMode: .standalone)`
5. `HotkeyManager` — CGEventTap lifecycle; dispatches to same coordinator methods as menu
6. `AppPreferences` — typed UserDefaults wrapper; single source of truth for all settings
7. `SettingsWindow` — NSWindowController hosting SwiftUI SettingsView; binds to AppPreferences via @AppStorage
8. `LoginItemManager` — SMAppService.mainApp calls; no helper bundle needed
9. `CoexistenceDetector` — filesystem check for Raycast extension directory; one-time alert

### Critical Pitfalls

1. **NSApp.terminate(nil) in handleExit() quits the entire app** — Gate behind `runMode == .raycast`; standalone path calls `endSession()` which closes windows and returns without terminating. Addresses Pitfalls 1 and 7 (inactivity timer) simultaneously.

2. **app.run() called on an already-running event loop** — Gate behind `runMode == .raycast`; standalone never calls `app.run()`. Calling it on a running loop causes the second session to hang or yield corrupted state.

3. **SPM executableTarget cannot produce a notarized .app bundle** — Must create Xcode project before writing any standalone code. This is a HIGH recovery cost if discovered late.

4. **CursorManager singleton state leaks between sessions** — Call `CursorManager.shared.restore()` at the START of every `run()` call, not just at exit. In the Raycast model, process death resets all state. In a persistent app, ghost cursor state from a crashed session bleeds into the next.

5. **setActivationPolicy(.accessory) called on every overlay invocation** — Set once in `applicationDidFinishLaunching`; remove from coordinator in standalone build. Repeated runtime calls cause Dock icon flicker and unpredictable window ordering on macOS 13/14.

6. **LSUIElement missing from Info.plist** — Without it, a Dock icon flashes on launch even if activation policy is set to `.accessory`. Add `LSUIElement = YES` before any app testing.

7. **Two separate permission prompts (Screen Recording + Accessibility)** — Screen recording is already handled by `PermissionChecker`. Accessibility (required for CGEventTap) is a completely separate prompt. Both need pre-prompt in-app explanations and actionable denial UI.

---

## Implications for Roadmap

Based on combined research, the dependency graph is strictly linear. Each phase is a hard prerequisite for the next. There is no parallelizable work until Phase 5.

### Phase 1: Build System and Core Library Extraction
**Rationale:** Nothing else can proceed without this. SPM cannot produce a signed app bundle (Pitfall 9). The `DesignRulerCore`/`DesignRulerRaycast` library split must happen before any app target references shared code. This phase has the highest recovery cost if skipped.
**Delivers:** A `DesignRulerCore` library that the Xcode project can reference; a `DesignRulerRaycast` shim that keeps the Raycast build working unchanged; a minimal Xcode project that builds and quits cleanly.
**Addresses:** Pitfalls 9 (SPM can't produce .app), 10 (code signing mismatch)
**Verification gate:** `ray build` passes after SPM restructure; Xcode project compiles and produces a runnable binary.

### Phase 2: App Lifecycle Refactor (OverlayCoordinator RunMode)
**Rationale:** The `app.run()` and `NSApp.terminate()` calls in `OverlayCoordinator` are the only lines that conflict with a persistent app. Until they are gated behind `runMode`, every overlay invocation either hangs (Pitfall 2) or kills the process (Pitfall 1). This is a surgical ~15-line change but it unlocks all subsequent phases.
**Delivers:** A coordinator that can be invoked from AppDelegate without starting or killing the event loop; `endSession()` that tears down windows without terminating.
**Addresses:** Pitfalls 1 (terminate), 2 (app.run), 5 (activation policy), 6 (SIGTERM), 7 (inactivity timer), 8 (CursorManager reset)
**Uses:** `RunMode` enum in `OverlayCoordinator.swift`
**Verification gate:** Invoke Measure via AppDelegate, press ESC, invoke again — two clean sessions with no cursor glitch, menu bar icon persists throughout.

### Phase 3: Menu Bar Shell and Manual Invocation
**Rationale:** Menu bar presence is the delivery mechanism without which the app is invisible. This is the minimum viable standalone product — both commands reachable via menu, no hotkeys yet.
**Delivers:** NSStatusItem with NSMenu; "Measure" and "Alignment Guides" menu items that launch overlays; "Quit" that calls NSApp.terminate cleanly.
**Addresses:** Table-stakes features (NSStatusItem, dropdown menu, persistent lifecycle); Pitfall 12 (LSUIElement in Info.plist)
**Uses:** Native AppKit NSStatusItem + NSMenu; LSUIElement = YES in Info.plist
**Verification gate:** Click menu bar icon, invoke Measure, press ESC, icon remains in menu bar, second invocation works.

### Phase 4: Permissions and Settings Foundation
**Rationale:** Permission handling must precede hotkey configuration (Accessibility prompt) and must be correct before any user-facing release. The Settings window is the UI surface for all user preferences and must exist before wiring hotkeys, launch at login, or other settings.
**Delivers:** Screen recording denial dialog with System Settings link; AppPreferences (UserDefaults wrapper); Settings window with General, Measure, and About tabs; hideHintBar and corrections preferences wired to coordinator calls.
**Addresses:** Pitfall 3 (permission denial has no UI); table-stakes features (settings window, existing preferences exposed)
**Uses:** PermissionChecker + NSAlert; NSWindowController + SwiftUI SettingsView; AppPreferences via @AppStorage
**Verification gate:** Deny screen recording permission, invoke Measure — actionable dialog appears. Settings window opens, changes persist across launches.

### Phase 5: Global Hotkeys
**Rationale:** Global hotkeys are the primary differentiator of the standalone app over the Raycast extension. They require Accessibility permission (separate prompt) and user-configurable bindings via KeyboardShortcuts.Recorder UI. This phase is isolated enough to be implemented cleanly after settings exist.
**Delivers:** HotkeyManager with CGEventTap; KeyboardShortcuts integration; hotkey recorder UI in Settings Shortcuts tab; Accessibility permission pre-prompt with explanation; hotkey conflict surfacing.
**Addresses:** Pitfall 4 (Accessibility permission separate from screen recording); anti-feature (no hardcoded defaults); differentiator features (configurable hotkeys, conflict detection)
**Uses:** `KeyboardShortcuts 2.4.0` SPM dependency; `CGEventTap`; `AXIsProcessTrusted()`
**Research flag:** CGEventTap cleanup between sessions needs verification — EventTap must be disabled between overlay sessions to avoid accumulating handlers (performance trap identified in PITFALLS.md).
**Verification gate:** Assign hotkey in Settings, switch to Figma, press hotkey — overlay appears. Deny Accessibility permission — actionable dialog appears, menu bar invocation still works.

### Phase 6: Launch at Login and Coexistence Polish
**Rationale:** Launch at login requires the app to be in `/Applications` (SMAppService constraint), so it can only be properly tested with a distributed-style build. Coexistence detection is low-complexity, independent, and rounds out the v1 feature set.
**Delivers:** Launch at Login toggle in Settings (OFF by default); SMAppService register/unregister; CoexistenceDetector with one-time NSAlert if Raycast extension directory found; menu bar icon state change during active overlay (P2 polish).
**Addresses:** Differentiator features (Launch at Login, coexistence nudge); performance trap (warmup CGWindowListCreateImage should move to app startup, not per-session)
**Uses:** `SMAppService.mainApp`; `NSWorkspace.runningApplications`; filesystem check for Raycast extensions directory
**Note:** Coexistence detection via filesystem path is MEDIUM confidence (Raycast path undocumented). Implement as a best-effort heuristic; do not block on it.
**Verification gate:** Install in /Applications, enable Launch at Login — app appears in System Settings Login Items. Launch Raycast with extension installed — one-time nudge appears, not repeated.

### Phase 7: Distribution
**Rationale:** Notarization requires hardened runtime, correct entitlements, and Apple review. This is a separate workflow from feature development and must be the final phase.
**Delivers:** Notarized, stapled DMG via create-dmg; GitHub Actions release workflow; Sparkle appcast for auto-updates (or stub for v1.1).
**Addresses:** Pitfall 11 (notarization entitlements); security requirement (no unnotarized public distribution)
**Uses:** `xcodebuild archive`; `xcrun notarytool`; `xcrun stapler`; `create-dmg 1.2.3`
**Research flag:** Sparkle 2.8.1 integration into Xcode project (binaryTarget SPM pattern) should be verified during planning — the XPC service setup is non-trivial.
**Verification gate:** `spctl --assess --type execute DesignRulerApp.app` passes on a clean machine; `codesign --verify --deep --strict` passes.

### Phase Ordering Rationale

- Phase 1 before everything: build system is the foundation; SPM restructure must be verified with a passing Raycast build before the Xcode project is written
- Phase 2 before Phase 3: coordinator lifecycle must be fixed before any AppDelegate wires up to it, or the first overlay invocation will terminate the app
- Phase 4 before Phase 5: AppPreferences must exist before hotkey bindings can be stored; Settings window must exist before the Shortcuts tab can be added
- Phases 5 and 6 are ordered but could overlap with careful isolation
- Phase 7 is always last: notarization is a release gate, not a development gate

### Research Flags

Phases needing deeper research during planning:
- **Phase 1:** Source restructure must be verified with actual `ray build` run — the exact set of files in `Measure.swift` that contain `@raycast` entry points vs. coordinator logic needs confirmation before moving files
- **Phase 5:** CGEventTap session cleanup pattern — verify EventTap disable/re-enable between overlay sessions does not cause missed hotkey events; check for race conditions on rapid re-invocation
- **Phase 7:** Sparkle 2.8.1 XPC service configuration in Xcode project — binaryTarget SPM pattern for Sparkle is documented but non-trivial; verify EdDSA key generation and appcast hosting requirements

Phases with well-documented patterns (skip research-phase):
- **Phase 3:** NSStatusItem + NSMenu is the most thoroughly documented AppKit pattern; no unknowns
- **Phase 4:** NSWindowController + SwiftUI NSHostingController is an established hybrid pattern used by HintBarView already in this codebase
- **Phase 6:** SMAppService.mainApp is documented and verified; no research needed

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified in Swift REPL; KeyboardShortcuts and Sparkle inspected via GitHub API; xcrun notarytool confirmed on local system |
| Features | MEDIUM | Core feature set is HIGH confidence (stable AppKit APIs); Raycast extension detection path is LOW (undocumented filesystem path may change across Raycast versions) |
| Architecture | HIGH | Derived from direct source code analysis of OverlayCoordinator, CursorManager, Package.swift; RunMode fix is a direct read of the relevant lines |
| Pitfalls | HIGH | 12 concrete pitfalls with line-number citations from the actual codebase; all critical pitfalls are code-derived, not speculative |

**Overall confidence:** HIGH

### Gaps to Address

- **Raycast extension detection path** (LOW confidence): `~/Library/Application Support/com.raycast.macos/extensions/design-ruler` is an inferred path, not a documented API. Verify against an actual Raycast installation before implementing CoexistenceDetector. Fallback: detect only whether Raycast.app is running (higher confidence) and omit extension-specific check.

- **SMAppService with ad-hoc signed builds** (needs verification): `SMAppService.mainApp.register()` may require a properly signed app in `/Applications`. Verify during Phase 6 that development builds in Xcode produce the expected `.enabled` status, not `.requiresApproval`.

- **KeyboardShortcuts vs CGEventTap for hotkey delivery** (architecture decision deferred): STACK.md recommends KeyboardShortcuts (uses Carbon `RegisterEventHotKey`) while ARCHITECTURE.md recommends CGEventTap. These are not equivalent. Carbon hotkeys work from menu bar apps but may be unreliable in some macOS 14/15 edge cases. CGEventTap requires Accessibility permission. Decision: use KeyboardShortcuts (Carbon-based, no Accessibility permission needed) as the primary implementation; if reliability issues arise, switch to CGEventTap. This must be decided in Phase 5 planning.

- **Warmup CGWindowListCreateImage** (performance): Currently called per-session. PITFALLS.md identifies this as a 100-200ms stall on every Measure launch. Moving warmup to app startup (`applicationDidFinishLaunching`) would make all subsequent launches instant. Flag for Phase 6 polish.

---

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis: `OverlayCoordinator.swift`, `CursorManager.swift`, `PermissionChecker.swift`, `Package.swift`, `Measure.swift`, `AlignmentGuides.swift`
- Swift REPL verification: `NSStatusItem`, `NSStatusBarButton`, `SMAppService.mainApp`, `NSWorkspace.runningApplications`, `RegisterEventHotKey`, `UserDefaults.standard`
- `KeyboardShortcuts` 2.4.0 — github.com/sindresorhus/KeyboardShortcuts — Package.swift and releases inspected via GitHub API
- `Sparkle` 2.8.1 — github.com/sparkle-project/Sparkle — Installation.md and Security.md read; release date confirmed
- `create-dmg` 1.2.3 — github.com/create-dmg/create-dmg — releases and brew info confirmed
- `xcrun notarytool` 1.1.0 — confirmed via local system
- Apple Developer Documentation: `NSStatusItem`, `NSMenu`, `SMAppService`, `CGEventTap`, `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`, `NSApplication.ActivationPolicy`, `LSUIElement`

### Secondary (MEDIUM confidence)
- LinearMouse CI workflow — github.com/linearmouse/linearmouse `.github/workflows/build.yml` — real-world validation of xcodebuild + create-dmg + notarytool pipeline
- macOS menu bar app UX conventions — derived from xScope 4 (Iconfactory) as reference implementation
- Settings window UX patterns — macOS HIG and observed conventions

### Tertiary (LOW confidence)
- Raycast extension storage path (`~/Library/Application Support/com.raycast.macos/extensions/`) — inferred heuristic, not documented by Raycast
- MASShortcut current maintenance status — not verified; KeyboardShortcuts preferred instead

---
*Research completed: 2026-02-17*
*Ready for roadmap: yes*
