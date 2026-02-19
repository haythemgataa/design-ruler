# Phase 23: Distribution - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Code-signed, notarized DMG with GitHub Actions CI pipeline. Anyone can download a notarized DMG from GitHub releases and run Design Ruler without a Gatekeeper warning. Pushing a version tag triggers the full build-sign-notarize-package pipeline.

</domain>

<decisions>
## Implementation Decisions

### DMG experience
- Classic drag-install layout: app icon on left, Applications alias on right, arrow between them
- Custom branded background image with app name/logo
- Custom volume icon using the app icon
- Spacious window size (~600x400)

### Signing identity
- User needs to set up an Apple Developer ID ($99/yr program) — plan should document the required steps
- Signing credentials stored as GitHub Secrets (base64-encoded .p12 + password + Apple ID credentials)
- Hardened Runtime enabled with necessary entitlements for screen capture (CGEventTap, CGWindowListCreateImage)
- Entitlements handled by Claude — user trusts the technical decisions here

### Sparkle feed & auto-update
- Appcast XML hosted via GitHub Releases (appcast points to release assets, no separate hosting)
- Auto-check for updates on launch (toggle already built in Phase 21 Settings)
- Stable channel only — no beta/pre-release channel
- CI automatically generates/updates appcast.xml when publishing a release

### CI trigger & versioning
- Tag format: `v1.0.0` (semantic versioning with 'v' prefix)
- Tag-driven versioning: CI extracts version from the git tag and injects into the build
- Draft release: CI creates a draft with DMG attached, user reviews and publishes manually
- CI also generates/updates Sparkle appcast.xml on release publish

### Claude's Discretion
- EdDSA signing key generation and management (private key in GitHub Secrets, public key in Info.plist)
- Universal binary vs Apple Silicon only (architecture choice)
- Specific Hardened Runtime entitlements needed
- DMG creation tooling (create-dmg, hdiutil, etc.)
- Appcast XML generation approach

</decisions>

<specifics>
## Specific Ideas

- Phase 21 already has Sparkle 2 integrated with placeholder SUFeedURL and SUPublicEDKey in Info.plist — this phase needs to set real values
- Phase 21 decision: `startingUpdater: false` defers EdDSA key validation — this phase re-enables with real keys
- App Sandbox already disabled (CGEventTap + CGWindowListCreateImage incompatible) — documented in STATE.md decisions
- LSUIElement = YES already in Info.plist (no Dock icon)
- Xcode project uses xcodegen (Phase 18) — CI needs to run xcodegen before building

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 23-distribution*
*Context gathered: 2026-02-19*
