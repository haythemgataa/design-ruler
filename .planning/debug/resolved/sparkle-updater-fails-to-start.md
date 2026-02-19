---
status: resolved
trigger: "Sparkle updater fails to start on app launch: Unable to Check For Updates - The updater failed to start."
created: 2026-02-19T00:00:00Z
updated: 2026-02-19T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - placeholder SUPublicEDKey fails base64 decode, Sparkle rejects it as invalid
test: traced Sparkle source code validation chain
expecting: placeholder string fails base64 -> SUSigningInputStatusInvalid -> startUpdater returns NO
next_action: document root cause and return diagnosis

## Symptoms

expected: Sparkle updater starts silently on app launch, enables background update checks
actual: Dialog appears "Unable to Check For Updates - The updater failed to start"
errors: "The EdDSA public key is not valid for Design Ruler."
reproduction: Launch app - error appears immediately on first launch
started: Since Phase 21-02 added Sparkle with placeholder keys

## Eliminated

(none - root cause found on first hypothesis)

## Evidence

- timestamp: 2026-02-19
  checked: Info.plist SUPublicEDKey value
  found: Value is literal string "PLACEHOLDER_EDDSA_PUBLIC_KEY"
  implication: Not valid base64, will fail decode

- timestamp: 2026-02-19
  checked: AppDelegate.swift SPUStandardUpdaterController initialization
  found: startingUpdater: true - starts updater immediately at init time
  implication: Validation runs before applicationDidFinishLaunching even completes

- timestamp: 2026-02-19
  checked: Sparkle SPUUpdater.m -startUpdater: method (line 157-202)
  found: Calls checkIfConfiguredProperlyAndRequireFeedURL:NO validateXPCServices:YES
  implication: Key validation happens at startup, feed URL not required yet

- timestamp: 2026-02-19
  checked: Sparkle SPUUpdater.m -checkIfConfiguredProperlyAndRequireFeedURL:validateXPCServices:error: (line 343-349)
  found: Explicitly checks `if (publicKeys.ed25519PubKeyStatus == SUSigningInputStatusInvalid)` and returns NO with error "The EdDSA public key is not valid for %@"
  implication: This is the exact error path being hit

- timestamp: 2026-02-19
  checked: Sparkle SUSignatures.m SUPublicKeys -initWithEd:dsa: (line 155-178)
  found: The `decode()` function (line 34-46) calls `[[NSData alloc] initWithBase64EncodedString:stripped options:0]`. "PLACEHOLDER_EDDSA_PUBLIC_KEY" is not valid base64 -> returns nil -> status = SUSigningInputStatusInvalid. Even if it were valid base64, the decoded bytes must be exactly 32 bytes (ed25519 key size) or status is also set to Invalid.
  implication: Placeholder string fails TWO validation checks: not base64, and wrong length

- timestamp: 2026-02-19
  checked: Sparkle SPUUpdater.m line 170
  found: feedURL check uses requireFeedURL:NO at startup - feed URL is NOT validated during startUpdater
  implication: The feed URL placeholder is NOT causing the startup failure; only the EdDSA key is

## Resolution

root_cause: The placeholder string "PLACEHOLDER_EDDSA_PUBLIC_KEY" in Info.plist's SUPublicEDKey fails Sparkle's base64 decode validation (it is not valid base64 and not 32 bytes), causing ed25519PubKeyStatus to be SUSigningInputStatusInvalid, which makes SPUUpdater.startUpdater: return NO with error "The EdDSA public key is not valid".
fix: (not applied - diagnosis only)
verification: (not applicable)
files_changed: []
