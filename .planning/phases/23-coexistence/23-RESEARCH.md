# Phase 23: Coexistence - Research

**Researched:** 2026-02-19
**Domain:** Raycast extension detection + SwiftUI inline banner
**Confidence:** HIGH

## Summary

Phase 23 adds a one-time info banner to the Settings window when the Design Ruler Raycast extension is also installed. The implementation has three clean parts: (1) a filesystem detection heuristic that scans `~/.config/raycast/extensions/` for the extension, (2) a UserDefaults-backed dismissal flag, and (3) a SwiftUI inline banner view at the top of the General section.

The detection heuristic is well-understood from direct filesystem inspection. Raycast stores extensions in `~/.config/raycast/extensions/` with UUID-based folder names for store-installed extensions and human-readable names for dev-mode extensions. Both formats include a `package.json` with a `"name"` field. The app is non-sandboxed (menu bar agent), so filesystem access has no permission constraints.

The SwiftUI banner fits naturally into the existing `SettingsView.swift` Form structure. The existing codebase uses `UserDefaults.standard` directly for preference flags (e.g., `hasLaunchedBefore`, `hideHintBar`), and the same pattern applies to the dismissal flag.

**Primary recommendation:** Scan `~/.config/raycast/extensions/*/package.json` for `"name": "design-ruler"` on Settings `.onAppear`. Show an inline banner above the General section with a "Got it" dismiss button backed by a UserDefaults boolean.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Friendly heads-up tone — not a warning, not pushy
- Neutral message: "You have both installed. Pick whichever you prefer."
- No explanation of why running both could be an issue — keep it simple
- Single "Got it" dismiss button — no "Open Raycast" or action buttons
- No mention of conflicts, duplicate shortcuts, etc.
- Info banner at the top of the General tab in Settings
- NOT an NSAlert or system dialog — inline banner within the Settings view
- Once dismissed with "Got it", the banner disappears permanently from Settings
- If the user later uninstalls the Raycast extension, the banner auto-disappears (re-check on Settings open)
- Lazy detection: only check for the Raycast extension when Settings is opened
- No detection on app launch — no background checks
- No delay or grace period — show immediately if detected when Settings opens
- If the user never opens Settings, no detection happens
- "Got it" dismisses the banner forever (persisted in UserDefaults)
- Dismissed means dismissed permanently — even if the extension is reinstalled later
- If not yet dismissed: banner visibility depends on live detection (extension present = show, extension removed = hide)

### Claude's Discretion
- Banner visual design (color, icon, layout within the General tab)
- Exact detection heuristic for the Raycast extension (filesystem path check)
- UserDefaults key naming for the dismissed flag

### Deferred Ideas (OUT OF SCOPE)
- Onboarding window — user wants the coexistence notice to also appear in a future onboarding flow. This is a separate phase/feature.
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ | Inline banner view in Form | Already used by SettingsView.swift |
| Foundation/FileManager | macOS 14+ | Filesystem scanning for extension detection | Standard macOS API, no dependencies needed |
| UserDefaults | macOS 14+ | Persist "dismissed" flag | Already used throughout the app for preferences |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| JSONSerialization | macOS 14+ | Parse package.json from Raycast extension dirs | Needed to read `"name"` field from JSON files |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Scanning all package.json files | Direct folder-name check | Only catches dev-mode installs, misses store-installed (UUID dirs) |
| JSONSerialization | Codable struct | Overkill for reading one field from a small JSON |
| FileManager enumeration | Shell/Process | Unnecessary complexity, slower |

**Installation:** No new dependencies required. Everything is available in Foundation + SwiftUI.

## Architecture Patterns

### Recommended Project Structure
```
App/Sources/
├── SettingsView.swift           # Modified: add banner + detection state
├── RaycastExtensionDetector.swift  # NEW: detection heuristic (single file)
└── ... (existing files unchanged)
```

### Pattern 1: Lazy Detection on View Appear
**What:** Run the filesystem check in `.onAppear` of SettingsView, not on app launch. Store result in `@State`.
**When to use:** When detection is only needed in a specific UI context.
**Example:**
```swift
struct SettingsView: View {
    @State private var raycastExtensionDetected = false
    @State private var coexistenceDismissed = UserDefaults.standard.bool(forKey: "coexistenceBannerDismissed")

    var showCoexistenceBanner: Bool {
        raycastExtensionDetected && !coexistenceDismissed
    }

    var body: some View {
        Form {
            if showCoexistenceBanner {
                // Banner view here
            }
            Section("General") { ... }
        }
        .onAppear {
            raycastExtensionDetected = RaycastExtensionDetector.isDesignRulerInstalled()
        }
    }
}
```

### Pattern 2: Filesystem Scan with Early Exit
**What:** Enumerate `~/.config/raycast/extensions/`, check each subdirectory for `package.json` with `"name": "design-ruler"`, return `true` on first match.
**When to use:** Best-effort heuristic for detecting third-party app artifacts.
**Example:**
```swift
enum RaycastExtensionDetector {
    static func isDesignRulerInstalled() -> Bool {
        let extensionsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/raycast/extensions")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: extensionsPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for dir in contents {
            let packageJSON = dir.appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: packageJSON),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String,
                  name == "design-ruler"
            else { continue }
            return true
        }
        return false
    }
}
```

### Pattern 3: Inline Banner as Conditional Section
**What:** Place the banner as a section ABOVE the General section in the Form, using `if showCoexistenceBanner`.
**When to use:** SwiftUI Form `.grouped` style renders sections with consistent styling.
**Example:**
```swift
Form {
    if showCoexistenceBanner {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Raycast Extension Detected")
                        .fontWeight(.medium)
                    Text("You have both the standalone app and the Raycast extension installed. Pick whichever you prefer.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Spacer()

                Button("Got it") {
                    UserDefaults.standard.set(true, forKey: "coexistenceBannerDismissed")
                    coexistenceDismissed = true
                }
            }
            .padding(.vertical, 4)
        }
    }

    Section("General") { ... }
    // ...
}
```

### Anti-Patterns to Avoid
- **Checking on app launch:** User decision: lazy detection only when Settings is opened.
- **NSAlert or modal dialog:** User decision: inline banner within the Settings view.
- **Checking Raycast process running:** Unreliable (Raycast may be running but extension not installed), and user wants filesystem detection.
- **Hardcoding a specific UUID:** Store-installed UUIDs are unique per user/installation. Must scan all dirs.
- **Caching detection result across app sessions:** User wants live re-check on each Settings open (so removing the extension makes the banner disappear). Only the *dismissed* flag is persisted.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing | Custom string parsing of package.json | `JSONSerialization` | Handles edge cases (whitespace, encoding, nested objects) |
| Directory enumeration | Manual path string construction | `FileManager.contentsOfDirectory(at:)` | Handles symlinks, permissions, encoding |
| Home directory path | Hardcoded `"/Users/..."` | `FileManager.default.homeDirectoryForCurrentUser` | Works for any user account |

**Key insight:** The detection heuristic is deliberately simple — a best-effort filesystem check, not a guaranteed detection mechanism. Don't over-engineer it.

## Common Pitfalls

### Pitfall 1: Hardcoded Home Directory Path
**What goes wrong:** Using `"/Users/haythem/.config/..."` or `NSHomeDirectory()` fails for edge cases.
**Why it happens:** Developer tests on their own machine only.
**How to avoid:** Use `FileManager.default.homeDirectoryForCurrentUser` which handles all user account configurations.
**Warning signs:** Any hardcoded path containing a username.

### Pitfall 2: Symlinks in the Extensions Directory
**What goes wrong:** The `node_modules` entry in `~/.config/raycast/extensions/` is a symlink. If enumeration follows symlinks or doesn't filter properly, it could waste time or throw errors.
**Why it happens:** Raycast creates a symlink `node_modules -> /Applications/Raycast.app/...`.
**How to avoid:** Use `.skipsHiddenFiles` option, check `isDirectoryKey`, and wrap in `try?` so any single failure doesn't abort the scan.
**Warning signs:** Crashes or long hangs when scanning the extensions directory.

### Pitfall 3: Banner Not Disappearing After Dismissal
**What goes wrong:** SwiftUI `@State` initialized from UserDefaults in `init()` caches the value. If the user dismisses and reopens Settings in the same app session, the state might be stale.
**Why it happens:** `@State(initialValue:)` only runs once per view lifetime, not per appearance.
**How to avoid:** Update the dismissed state in both `.onAppear` AND the "Got it" button action. The `.onAppear` re-reads from UserDefaults each time Settings opens.
**Warning signs:** Banner reappears after dismissal without restarting the app.

### Pitfall 4: Race Between Detection and Dismissal State
**What goes wrong:** Detection runs on `.onAppear`, but dismissed state is read from `init()`. If timing is off, banner flickers.
**Why it happens:** Two independent state sources (filesystem + UserDefaults) checked at different times.
**How to avoid:** Read both states in `.onAppear`: `raycastExtensionDetected = ...detect()` AND `coexistenceDismissed = UserDefaults.standard.bool(...)`. Then the computed `showCoexistenceBanner` is always consistent.
**Warning signs:** Banner briefly appears then disappears on Settings open.

### Pitfall 5: Extension Installed but Raycast Not Installed
**What goes wrong:** Extension files may exist in `~/.config/raycast/extensions/` even after Raycast is uninstalled (leftover files).
**Why it happens:** Raycast may not clean up all files on uninstall.
**How to avoid:** This is acceptable — the banner is a best-effort FYI. False positives are low-harm because the message is neutral ("pick whichever you prefer"). No action needed.
**Warning signs:** N/A — acceptable behavior per the neutral tone requirement.

## Code Examples

### Complete Detection Implementation
```swift
// RaycastExtensionDetector.swift
import Foundation

enum RaycastExtensionDetector {
    /// Best-effort check for the Design Ruler Raycast extension.
    /// Scans ~/.config/raycast/extensions/*/package.json for name == "design-ruler".
    /// Returns false if Raycast is not installed or extension not found.
    static func isDesignRulerInstalled() -> Bool {
        let extensionsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/raycast/extensions")

        guard let subdirectories = try? FileManager.default.contentsOfDirectory(
            at: extensionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false  // Raycast not installed or dir not accessible
        }

        for dir in subdirectories {
            // Skip non-directories (e.g., symlinks like node_modules)
            guard let resourceValues = try? dir.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == true
            else { continue }

            let packageJSON = dir.appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: packageJSON),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String,
                  name == "design-ruler"
            else { continue }

            return true
        }

        return false
    }
}
```

### Banner Integration in SettingsView
```swift
// In SettingsView.swift — new state properties
@State private var raycastExtensionDetected = false
@State private var coexistenceDismissed = false

private var showCoexistenceBanner: Bool {
    raycastExtensionDetected && !coexistenceDismissed
}

// In body, BEFORE the General section:
if showCoexistenceBanner {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Raycast Extension Detected")
                    .fontWeight(.medium)
                Text("You have both the standalone app and the Raycast extension installed. Pick whichever you prefer.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button("Got it") {
                UserDefaults.standard.set(true, forKey: "coexistenceBannerDismissed")
                withAnimation {
                    coexistenceDismissed = true
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// In .onAppear modifier (update existing):
.onAppear {
    launchAtLogin = SMAppService.mainApp.status == .enabled
    coexistenceDismissed = UserDefaults.standard.bool(forKey: "coexistenceBannerDismissed")
    if !coexistenceDismissed {
        raycastExtensionDetected = RaycastExtensionDetector.isDesignRulerInstalled()
    }
}
```

### UserDefaults Key
```swift
// Key: "coexistenceBannerDismissed"
// Type: Bool
// Default: false (not dismissed)
// Set to true: permanently hides banner
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSAlert` for coexistence warnings | Inline SwiftUI banner in Settings | macOS design trend 2023+ | Non-intrusive, respects user flow |
| Check running processes for detection | Filesystem heuristic | N/A | More reliable (catches installed-but-not-running) |
| `~/Library/Application Support/com.raycast.macos/extensions/` | `~/.config/raycast/extensions/` | Raycast moved to XDG-style paths | Correct path confirmed by direct filesystem inspection |

**Deprecated/outdated:**
- Prior decision noted `~/Library/Application Support/com.raycast.macos/extensions/` — this directory exists but contains **no extension subdirectories** (it's empty). The actual extensions live at `~/.config/raycast/extensions/`.

## Raycast Extension Storage — Verified Facts

### Path
**`~/.config/raycast/extensions/`** is the correct directory. Verified by direct filesystem inspection on a machine with 25 installed extensions.

### Folder Naming
| Installation Method | Folder Name | Example |
|---------------------|-------------|---------|
| Raycast Store | UUID | `05dcf33b-6a0b-4034-bc30-28428b6a1828` |
| Dev mode (`ray develop`) | Extension name | `design-ruler` |

### Identification
Every extension folder contains a `package.json` with a `"name"` field matching the extension's npm-style name. For Design Ruler: `"name": "design-ruler"`.

### Design Ruler Extension Artifacts
```
~/.config/raycast/extensions/design-ruler/  (or UUID/)
├── alignment-guides.js
├── alignment-guides.js.map
├── assets/
│   ├── compiled_raycast_swift/
│   │   └── DesignRuler          # Swift binary
│   ├── design-ruler-icon.png
│   └── ...
├── measure.js
├── measure.js.map
└── package.json                  # {"name": "design-ruler", ...}
```

### Edge Cases
- The `node_modules` entry is a **symlink** to Raycast.app internals — must be skipped during enumeration.
- A user may have 0-100+ extensions installed. Scanning is fast (< 10ms for 25 extensions in shell; Swift FileManager will be faster).
- If Raycast is not installed, `~/.config/raycast/` won't exist — `try?` returns nil gracefully.

## Open Questions

1. **Store-installed UUID stability**
   - What we know: Store-installed extensions use UUID folder names. The UUID appears to be stable per installation.
   - What's unclear: Whether the UUID changes on extension updates from the store.
   - Recommendation: Irrelevant for our approach — we scan `package.json` content, not folder names. No action needed.

2. **Raycast uninstall cleanup**
   - What we know: Raycast may leave `~/.config/raycast/` behind after uninstall.
   - What's unclear: Whether Raycast cleanly removes its config directory on uninstall.
   - Recommendation: Acceptable false positive — the banner message is neutral ("pick whichever you prefer"), so detecting a leftover is harmless. No action needed.

## Design Recommendation: Banner Visual

The banner should use SwiftUI's standard `.blue` accent for the info icon, matching macOS system conventions. Layout as an HStack with icon, text VStack, spacer, and "Got it" button. Place it as a Section above the existing "General" section in the Form.

Recommended: `Image(systemName: "info.circle.fill")` with `.foregroundStyle(.blue)` — this is the standard macOS info indicator. The "Got it" button should use the default button style (no `.bordered` or `.borderedProminent` needed — in a Form context the default rendering is appropriate).

Use `withAnimation` on dismissal so the banner smoothly collapses out of the Form layout rather than popping away.

## Sources

### Primary (HIGH confidence)
- Direct filesystem inspection of `~/.config/raycast/extensions/` on developer machine with 25 installed extensions — verified folder structure, naming conventions, package.json content
- Direct inspection of existing `SettingsView.swift`, `AppPreferences.swift`, `AppDelegate.swift` in the codebase — verified UserDefaults patterns, SwiftUI Form structure, non-sandboxed configuration
- `App/Design Ruler.xcodeproj/project.pbxproj` — verified macOS 14.0 deployment target, no sandbox entitlements

### Secondary (MEDIUM confidence)
- [Raycast Developer Docs: Install an Extension](https://developers.raycast.com/basics/install-an-extension) — general extension installation info
- [Raycast Developer Docs: File Structure](https://developers.raycast.com/information/file-structure) — extension file structure documentation

### Tertiary (LOW confidence)
- Prior phase decision noting `~/Library/Application Support/com.raycast.macos/extensions/` — **OUTDATED, path is wrong**. The `extensions/` subdirectory there exists but is empty. Real extensions are at `~/.config/raycast/extensions/`.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new dependencies, all Foundation + SwiftUI already in use
- Architecture: HIGH - Direct codebase inspection, well-understood SwiftUI Form patterns
- Detection heuristic: HIGH - Verified by direct filesystem inspection on real machine
- Pitfalls: HIGH - Identified from actual codebase patterns (SwiftUI @State lifecycle, symlinks)
- Extension path: HIGH - Verified empirically, supersedes prior LOW-confidence guess

**Research date:** 2026-02-19
**Valid until:** 2026-04-19 (stable domain, no moving parts)
