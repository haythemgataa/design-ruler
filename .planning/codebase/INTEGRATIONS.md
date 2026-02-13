# External Integrations

**Analysis Date:** 2026-02-13

## APIs & External Services

**Raycast Host Integration:**
- Raycast API - Command execution environment
  - SDK/Client: @raycast/api
  - Functions: `closeMainWindow()`, `getPreferenceValues()`
  - No authentication needed (runs in Raycast context)

**macOS System Services:**
- No external web APIs used
- No cloud services integrated
- No third-party SDKs or APIs called

## Data Storage

**Databases:**
- None. Not applicable for this extension.

**File Storage:**
- Local filesystem only (macOS UserDefaults for persistent state)
- Storage location: `com.raycast.design-ruler.*` namespace in UserDefaults
  - Key: `com.raycast.design-ruler.hintBarDismissed` - Boolean flag tracking whether user dismissed hint bar via backspace
  - Used in: `RulerWindow.swift` (lines tracking dismissal state)
  - No file-based persistence (all state in-memory or UserDefaults)

**Caching:**
- None. No caching layer used.

## Authentication & Identity

**Auth Provider:**
- None required. Extension runs as accessory-level process with Raycast permissions.

**macOS Security:**
- Screen Recording Permission (required by macOS)
  - Checked via `CGPreflightScreenCaptureAccess()`
  - Requested via `CGRequestScreenCaptureAccess()`
  - Implementation: `PermissionChecker.swift` (enum with static methods)
  - No OAuth or token-based auth; permission is system-level (user grants in macOS Settings → Privacy & Security → Screen Recording)

## Monitoring & Observability

**Error Tracking:**
- None. No external error tracking service configured.

**Logs:**
- Debug output to stderr only (for development): `fputs("[DEBUG] ...", stderr)` in `EdgeDetector.swift`
- No persistent logging or external log aggregation
- No telemetry or analytics

## CI/CD & Deployment

**Hosting:**
- Raycast Store (centralized marketplace)
- No custom server or cloud infrastructure

**CI Pipeline:**
- None detected. Local development only via `ray develop` or `ray build` for testing
- No GitHub Actions or automated testing pipeline configured

**Build Process:**
- `ray build` - Compiles TypeScript and Swift, bundles extension for Raycast Store
- `ray develop` - Watches for file changes, hot-reloads in local Raycast instance
- Build artifacts: Swift binary only (no bundle resources deployed per CLAUDE.md constraints)

## Environment Configuration

**Required env vars:**
- None. All configuration via Raycast preferences UI or defaults.

**Preferences (User-Configurable):**
- `hideHintBar` (boolean, default: false) - Toggle visibility of keyboard hint bar
- `corrections` (dropdown: "smart"|"include"|"none", default: "smart") - Edge detection correction mode for 1px borders
- Both passed from TypeScript to Swift as function parameters in `design-ruler.ts`

**Secrets location:**
- Not applicable. No API keys, tokens, or credentials used.

## Webhooks & Callbacks

**Incoming:**
- None. Extension is not a server; it's a command-line application.

**Outgoing:**
- None. No outbound webhooks or external callbacks.

**Internal Callbacks:**
- RulerWindow → Ruler coordination via optional callbacks:
  - `onActivate` - Called when user switches focus to a different monitor's window
  - `onRequestExit` - Called when user presses ESC
  - `onFirstMove` - Called on first mouse movement (to unhide system cursor)
  - Defined in: `RulerWindow.swift` (lines 18-20)
  - Used in: `Ruler.swift` (lines 79-86)

## System Permissions

**macOS Sandbox & TCC (Transparency, Consent, and Control):**
- Screen Recording permission required and checked at runtime
  - macOS shows user prompt on first use
  - Permission stored in `~/Library/Application\ Support/com.apple.sharedfilelist/com.apple.CFNetwork.plist` or TCC database
  - Extension gracefully requests if missing (via `PermissionChecker.requestScreenRecordingPermission()`)

**No Other Permissions Required:**
- No file system access needed (no persistent data stored)
- No clipboard access (Raycast handles extension invocation)
- No network access (no remote communication)
- No camera/microphone access
- No keyboard monitoring beyond the hosting Raycast window

## Deployment & Distribution

**Release Channel:**
- Raycast Store only (via `npm run publish` → @raycast/api publish)
- Manual submission to Raycast review process
- No auto-update mechanism (Raycast handles updates centrally)

**Binary Deployment:**
- Raycast extracts the compiled Swift binary and executes via TypeScript bridge
- Only the binary is deployed; source code remains private to Raycast

---

*Integration audit: 2026-02-13*
