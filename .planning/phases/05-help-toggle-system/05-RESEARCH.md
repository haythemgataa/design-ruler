# Phase 5: Help Toggle System - Research

**Researched:** 2026-02-13
**Domain:** macOS hint bar toggle, transient message overlay, UserDefaults persistence, Core Animation fade
**Confidence:** HIGH

## Summary

This phase adds the ability for users to dismiss the hint bar (backspace), rediscover it ("?"), and have that preference persist across sessions. The codebase already has partial infrastructure: backspace handling (keyCode 51) in `RulerWindow.keyDown` dismisses the hint bar with a fade-out animation and saves `UserDefaults.standard.set(true, forKey: "com.raycast.design-ruler.hintBarDismissed")`, and `RulerWindow.setupViews` reads that key to conditionally skip adding the hint bar. The `Ruler.run()` method also clears the dismissed flag when the Raycast `hideHintBar` preference is toggled on, providing a reset path.

What is MISSING: (1) a "?" key handler to re-add the hint bar during a session, (2) a transient "Press ? for help" message that appears briefly when the hint bar is dismissed (both on backspace press and on launch with previously-dismissed state), and (3) the transient message auto-fade behavior. The core challenge is creating a lightweight transient text overlay (not a full HintBarView) that appears centered at the bottom, fades in, holds briefly, then fades out -- all using Core Animation for zero CPU cost.

The "?" key cannot be detected by keyCode alone because it is Shift+Slash (keyCode 44) on US keyboards but varies by layout. The reliable approach is checking `event.characters == "?"` which handles all keyboard layouts. This pattern is already implicitly used in the codebase (the hint bar shows the backspace symbol, not a raw keycode).

**Primary recommendation:** Add a lightweight `TransientHelpLabel` (CATextLayer + CAShapeLayer background) managed by RulerWindow. On backspace: fade-out hint bar, fade-in transient label, auto-fade after 2s. On "?": fade-out transient label (if visible), add hint bar back with fade-in, clear UserDefaults key. On launch with dismissed state: show transient label, auto-fade after 2s. Use `event.characters == "?"` for key detection.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit `NSEvent.characters` | macOS 13+ | Detect "?" regardless of keyboard layout | Already available; keyCode is layout-dependent |
| Core Animation `CATextLayer` + `CAShapeLayer` | macOS 13+ | Transient message rendering | Same GPU-composited pattern as CrosshairView pill |
| Foundation `UserDefaults` | macOS 13+ | Persist dismissed state across sessions | Already in use for this exact purpose |
| Foundation `DispatchQueue.main.asyncAfter` | macOS 13+ | Auto-fade timer for transient message | Lightweight; no need for Timer since it fires once |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CATextLayer for transient message | NSHostingView with SwiftUI | Heavier; SwiftUI hosting adds overhead for a simple text label |
| CATextLayer for transient message | HintBarView instance with different text | Too heavy; HintBarView is a complex SwiftUI-hosted view with key caps and multiple cards |
| `event.characters == "?"` | `event.keyCode == 44 && shift` | Breaks on non-US keyboard layouts |
| `DispatchQueue.main.asyncAfter` | `Timer.scheduledTimer` | Timer needs invalidation tracking; asyncAfter is fire-and-forget for one-shot delays |

## Architecture Patterns

### Files Modified
```
swift/Ruler/Sources/
├── RulerWindow.swift           # Modified: "?" key handler, transient message lifecycle,
│                               #           hint bar re-add logic, launch-with-dismissed logic
├── Rendering/
│   └── HintBarView.swift       # Modified: Add fadeIn/fadeOut methods for animated show/hide
└── Ruler.swift                 # Modified: Pass dismissed state to RulerWindow for launch message
```

No new files needed. The transient label is a small collection of CALayers (background + text) that lives inline in RulerWindow, similar to how CrosshairView manages its pill layers.

### Pattern 1: Transient Message as CALayer Group
**What:** A small "Press ? for help" label using CAShapeLayer (rounded background) + CATextLayer (text), added to the container view's layer.
**When to use:** When you need a lightweight, GPU-composited text overlay that fades in/out without any view hierarchy overhead.

```swift
// In RulerWindow
private var transientBgLayer: CAShapeLayer?
private var transientTextLayer: CATextLayer?

private func showTransientHelp(in containerView: NSView, screenWidth: CGFloat) {
    let text = "Press ? for help"
    // ... create CATextLayer + CAShapeLayer, position at bottom center
    // Fade in over 0.3s, then auto-fade after 2s hold
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { [weak self] in
        self?.fadeOutTransientHelp()
    }
}

private func fadeOutTransientHelp() {
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.5)
    CATransaction.setCompletionBlock { [weak self] in
        self?.transientBgLayer?.removeFromSuperlayer()
        self?.transientTextLayer?.removeFromSuperlayer()
        self?.transientBgLayer = nil
        self?.transientTextLayer = nil
    }
    transientBgLayer?.opacity = 0
    transientTextLayer?.opacity = 0
    CATransaction.commit()
}
```

**Why CALayers, not SwiftUI:** The transient message is trivially simple (one string, one rounded rect). SwiftUI hosting adds unnecessary overhead. The codebase already uses raw CALayers extensively (CrosshairView, SelectionOverlay). CATextLayer supports NSAttributedString for font styling.

### Pattern 2: Key Detection via characters, not keyCode
**What:** Check `event.characters` for "?" instead of checking keyCode + shift modifier.
**When to use:** Detecting characters that require modifier keys and vary by keyboard layout.

```swift
// In RulerWindow.keyDown:
case 44: // Slash key (US layout) -- but "?" depends on layout
    // DON'T DO THIS: if shift { handle ? }
    break

// INSTEAD, add a characters check after the keyCode switch:
if event.characters == "?" {
    handleQuestionMark()
}
```

**Why:** On a US keyboard, "?" is Shift+/ (keyCode 44). On a French AZERTY keyboard, "?" is a direct key (different keyCode entirely). On a German QWERTZ keyboard, "?" is Shift+SS. Checking `event.characters` handles all layouts.

**Important:** The `event.characters` check should be placed after (or alongside) the existing keyCode switch, not inside a specific keyCode case. This way it catches "?" regardless of which physical key produced it.

### Pattern 3: Hint Bar Re-Add with Fade-In
**What:** When "?" is pressed, add the HintBarView back to the container and fade it in.
**When to use:** Restoring a previously-removed view with animation.

```swift
private func showHintBar() {
    guard hintBarView.superview == nil else { return }
    guard let container = contentView else { return }

    hintBarView.alphaValue = 0
    hintBarView.configure(screenWidth: screenBounds.width, screenHeight: screenBounds.height)
    container.addSubview(hintBarView)

    // Update position for current cursor location
    let mouse = NSEvent.mouseLocation
    let wp = NSPoint(x: mouse.x - screenBounds.origin.x, y: mouse.y - screenBounds.origin.y)
    hintBarView.updatePosition(cursorY: wp.y, screenHeight: screenBounds.height)

    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.3
        hintBarView.animator().alphaValue = 1
    })

    UserDefaults.standard.removeObject(forKey: "com.raycast.design-ruler.hintBarDismissed")

    // Remove transient help if visible
    fadeOutTransientHelp()
}
```

### Pattern 4: Launch-with-Dismissed State
**What:** On launch, if hint bar was previously dismissed, show transient "Press ? for help" instead.
**When to use:** DISC-04 requirement -- providing discoverability on launch.

The existing flow in `RulerWindow.setupViews` already checks `dismissed` and skips adding the hint bar. The change is: when `dismissed && !hideHintBar`, show the transient message instead of showing nothing.

This requires either (a) calling a method on RulerWindow after `setupViews` but before display, or (b) having `setupViews` itself create the transient message layers. Option (b) is cleaner -- `setupViews` already knows the dismissed state and has access to the container view.

### Anti-Patterns to Avoid
- **DO NOT create a new NSView subclass for the transient message:** It is a trivial 2-layer overlay. An NSView adds unnecessary view hierarchy overhead and event routing complexity.
- **DO NOT use NSTextField or NSLabel for the transient message:** These are views, not layers. They participate in the responder chain and hit testing. The transient message should be invisible to events.
- **DO NOT use a Timer for auto-fade:** `DispatchQueue.main.asyncAfter` is simpler for one-shot delays and does not need invalidation tracking. However, do track a generation counter or flag to avoid fading out a message that was already removed by "?" key press.
- **DO NOT remove the hint bar from the view hierarchy permanently on backspace:** Keep the `hintBarView` instance alive as a property. Only remove it from superview. This avoids recreating it when "?" re-enables it.
- **DO NOT check keyCode for "?" detection:** Use `event.characters == "?"` for keyboard-layout independence.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Keyboard-layout-independent "?" detection | keyCode + modifier checking | `event.characters == "?"` | "?" is produced by different physical keys on different layouts |
| Transient message view | NSView/NSTextField subclass | CAShapeLayer + CATextLayer | Lighter weight, no event routing, matches existing pill pattern |
| Auto-fade scheduling | Custom Timer with invalidation | `DispatchQueue.main.asyncAfter` + generation counter | Simpler for one-shot delayed actions |

**Key insight:** The transient message is essentially a simpler version of the CrosshairView pill. It uses the exact same layer types (CAShapeLayer for background, CATextLayer for text) and the same animation patterns (CATransaction with opacity). No new rendering techniques are needed.

## Common Pitfalls

### Pitfall 1: Stale asyncAfter Firing After "?" Restores Hint Bar
**What goes wrong:** User presses backspace (transient message appears with 2s auto-fade), then quickly presses "?" to re-enable hint bar. The scheduled auto-fade fires and removes the transient message... but by then the transient message layers are already gone, and the code might accidentally affect other layers.
**Why it happens:** `DispatchQueue.main.asyncAfter` cannot be cancelled.
**How to avoid:** Use a generation counter (simple Int). Increment on every show/hide of the transient message. The asyncAfter closure captures the current generation and only executes if it still matches. This is a standard cancellation pattern for asyncAfter.
**Warning signs:** Hint bar flickers or disappears unexpectedly 2 seconds after "?" press.

```swift
private var transientGeneration: Int = 0

private func showTransientHelp(...) {
    transientGeneration += 1
    let gen = transientGeneration
    // ... show layers ...
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { [weak self] in
        guard let self, self.transientGeneration == gen else { return }
        self.fadeOutTransientHelp()
    }
}
```

### Pitfall 2: Hint Bar Position Wrong on Re-Add
**What goes wrong:** Pressing "?" adds the hint bar back, but it appears at the wrong vertical position (always bottom, even though cursor is near bottom).
**Why it happens:** `configure()` always places the hint bar at the bottom. `updatePosition()` needs to be called immediately after to correct for the current cursor position.
**How to avoid:** Call `updatePosition(cursorY:screenHeight:)` immediately after `configure()` and `addSubview()`.
**Warning signs:** Hint bar overlaps cursor when re-enabled near the bottom of the screen.

### Pitfall 3: "?" Key Consumed by Shift Modifier Handling
**What goes wrong:** Pressing "?" triggers the `flagsChanged` handler for Shift before `keyDown` fires, causing the hint bar's shift key cap to animate but the "?" handler to not fire.
**Why it happens:** Pressing Shift to type "?" fires `flagsChanged` first (Shift down), then `keyDown` (/ with Shift). The `flagsChanged` handler already handles Shift for the hint bar key cap animation.
**How to avoid:** The `keyDown` handler runs after `flagsChanged`. The `event.characters` check in `keyDown` will still see "?" correctly. The Shift key cap animation in the hint bar is cosmetic and harmless. No conflict.
**Warning signs:** None in practice -- this is a non-issue as long as `keyDown` checks `event.characters`.

### Pitfall 4: Transient Message Layers Not Cleaned Up on Exit
**What goes wrong:** Transient message layers are still fading when ESC is pressed, causing a brief visual glitch.
**Why it happens:** The auto-fade completion block fires after the window is already closing.
**How to avoid:** In `handleExit()` path (ESC key), there is no need to explicitly clean up the transient layers -- they are sublayers of the container view's layer and will be destroyed when the window closes. The weak self guard in the asyncAfter closure prevents crashes.
**Warning signs:** None likely, but good to verify ESC during auto-fade works cleanly.

### Pitfall 5: HintBarView Stale State on Re-Add
**What goes wrong:** When hint bar is re-added after "?", pressed key states from before dismissal are still set.
**Why it happens:** The HintBarState ObservableObject retains its `pressedKeys` set even after the view is removed from superview.
**How to avoid:** Clear `pressedKeys` when dismissing. Or, since the hint bar is removed via backspace animation which already calls `hintBarView.pressKey(.backspace)`, ensure `releaseKey` is called. Actually, since the hint bar is removed from superview, `keyUp` events won't route to it. Clear pressed keys in `showHintBar()` before re-adding.
**Warning signs:** Key cap appears visually "stuck" in pressed state when hint bar reappears.

### Pitfall 6: Multi-Monitor -- Transient Message Only On Cursor Screen
**What goes wrong:** Transient message shows on all screens or on the wrong screen.
**Why it happens:** Only one RulerWindow has `hideHintBar: false`, but the dismissed state is global.
**How to avoid:** The current architecture already handles this: only the cursor-screen window gets `hideHintBar: false` (via `isCursorScreen ? hideHintBar : true` in Ruler.run). Non-cursor windows always get `hideHintBar: true` which skips both hint bar and transient message. The transient message logic should follow the same condition -- it only shows when `!hideHintBar && dismissed`.
**Warning signs:** Transient message appearing on secondary monitors.

## Code Examples

### Key Detection for "?"

```swift
// Source: Apple NSEvent.characters documentation + keyboard layout independence
// In RulerWindow.keyDown, AFTER the existing keyCode switch:
if event.characters == "?" {
    handleQuestionMark()
    return  // Don't fall through to other handling
}
```

**Important implementation detail:** The "?" check should come BEFORE the keyCode switch or be added as a characters-based check alongside it. Since keyCode 44 (slash) is in the switch but currently unhandled, adding a characters check is the cleanest approach. The key insight is that `event.characters` is already layout-resolved by the time `keyDown` fires.

### Transient Help Label Setup

```swift
// Source: Same CALayer pattern as CrosshairView pill
private func createTransientHelp(screenWidth: CGFloat) {
    let text = "Press  ?  for help"
    let font = NSFont.systemFont(ofSize: 16, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -0.4 as CGFloat,
    ]
    let attrStr = NSAttributedString(string: text, attributes: attrs)
    let textSize = attrStr.size()

    let padH: CGFloat = 16
    let padV: CGFloat = 10
    let bgWidth = ceil(textSize.width) + padH * 2
    let bgHeight = ceil(textSize.height) + padV * 2
    let bgX = floor((screenWidth - bgWidth) / 2)
    let bgY: CGFloat = 20  // Bottom margin (AppKit coords)

    let bgLayer = CAShapeLayer()
    bgLayer.frame = CGRect(x: bgX, y: bgY, width: bgWidth, height: bgHeight)
    bgLayer.path = CGPath(roundedRect: CGRect(origin: .zero, size: bgLayer.frame.size),
                           cornerWidth: 12, cornerHeight: 12, transform: nil)
    bgLayer.fillColor = CGColor(gray: 0, alpha: 0.7)
    bgLayer.shadowColor = CGColor(gray: 0, alpha: 0.2)
    bgLayer.shadowOffset = CGSize(width: 0, height: -1)
    bgLayer.shadowRadius = 4
    bgLayer.shadowOpacity = 1

    let textLayer = CATextLayer()
    textLayer.string = attrStr
    textLayer.contentsScale = window?.backingScaleFactor ?? 2.0
    textLayer.frame = CGRect(
        x: bgX + padH,
        y: bgY + round((bgHeight - ceil(textSize.height)) / 2),
        width: ceil(textSize.width),
        height: ceil(textSize.height)
    )
    textLayer.alignmentMode = .center
    textLayer.isWrapped = false

    // Start invisible
    bgLayer.opacity = 0
    textLayer.opacity = 0

    return (bgLayer, textLayer)
}
```

### UserDefaults Key Constant

```swift
// Source: Already used in RulerWindow.setupViews (line 74) and keyDown (line 324)
// Consider extracting to a constant to avoid typo bugs:
private let kHintBarDismissedKey = "com.raycast.design-ruler.hintBarDismissed"
```

Currently the string `"com.raycast.design-ruler.hintBarDismissed"` appears in 3 places (setupViews, keyDown, Ruler.run). Extracting it to a constant reduces typo risk.

### Hint Bar Fade-Out (Existing Pattern, Enhanced)

```swift
// Source: Current RulerWindow.keyDown case 51 (lines 312-325)
// The existing backspace handler already does:
// 1. Press animation on key cap
// 2. Delayed fade-out of hint bar
// 3. UserDefaults persistence
//
// Enhancement needed: After fade-out completes, show transient message
case 51: // Backspace
    if hintVisible {
        hintBarView.pressKey(.backspace)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.hintBarView.superview != nil else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self.hintBarView.animator().alphaValue = 0
            }, completionHandler: {
                self.hintBarView.removeFromSuperview()
                self.hintBarView.alphaValue = 1  // Reset for potential re-add
                self.showTransientHelp()  // NEW: show "Press ? for help"
            })
        }
        UserDefaults.standard.set(true, forKey: kHintBarDismissedKey)
    }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hint bar dismiss is permanent (no re-enable) | Toggle: backspace dismiss, "?" re-enable | This phase | Users can recover the hint bar without relaunching |
| No feedback on dismiss | Transient "Press ? for help" message | This phase | Users know how to get help back |
| Dismiss state lost on relaunch (before Phase 5 partial impl) | UserDefaults persistence (already partially done) | Phase 5 prep | State survives across sessions |

**Already implemented (partial):**
- Backspace dismissal with fade animation (RulerWindow.keyDown case 51)
- UserDefaults persistence of dismissed state (both read and write)
- hideHintBar preference clearing the dismissed flag (Ruler.run)

**Not yet implemented:**
- "?" key to re-enable hint bar
- Transient "Press ? for help" message (on dismiss and on launch-with-dismissed)
- Auto-fade behavior for transient message

## Open Questions

1. **Should the transient message have a "?" key cap visual (like the hint bar's key caps)?**
   - What we know: The hint bar has beautifully rendered 3D key caps using SwiftUI. The transient message is meant to be simpler/lighter.
   - What's unclear: Whether a plain text "?" looks good enough, or if a simplified key cap would be better.
   - Recommendation: Use plain text with slight emphasis (e.g., monospaced "?" or just bold). The transient message is meant to be subtle and ephemeral -- full key cap rendering would be overkill for a 2-second overlay. Keep it as a CALayer-only implementation.

2. **What is the ideal auto-fade timing?**
   - What we know: The requirements say "briefly shows" and "auto-fades without user action."
   - What's unclear: Exact duration. Too short (0.5s) and users miss it. Too long (5s) and it feels sticky.
   - Recommendation: 2s hold + 0.5s fade = 2.5s total visibility. This matches macOS notification banner timing (they appear for ~3-5s). The transient message is shorter because it has less content to read.

3. **Should pressing "?" while the transient message is still fading cancel the fade and restore the hint bar?**
   - What we know: The transient message auto-fades, but the user might press "?" during the fade.
   - What's unclear: Whether to handle this edge case explicitly.
   - Recommendation: Yes -- pressing "?" at any time (whether transient is visible, fading, or already gone) should re-enable the hint bar. The generation counter pattern handles this cleanly.

## Sources

### Primary (HIGH confidence)
- Local codebase analysis: `RulerWindow.swift` (keyDown, setupViews), `Ruler.swift` (UserDefaults clearing), `HintBarView.swift` (existing slide animation pattern), `CrosshairView.swift` (CALayer pill pattern), `HintBarContent.swift` (SwiftUI key cap rendering)
- [Apple NSEvent.characters documentation](https://developer.apple.com/documentation/appkit/nsevent/1534183-characters) -- layout-resolved character string
- [Apple NSEvent.keyCode documentation](https://developer.apple.com/documentation/appkit/nsevent/1534513-keycode) -- hardware-independent virtual key code (layout-dependent for letter keys)
- [Apple CATextLayer documentation](https://developer.apple.com/documentation/quartzcore/catextlayer) -- text rendering in Core Animation
- [Apple Core Animation: Creating Basic Animations](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CreatingBasicAnimations/CreatingBasicAnimations.html) -- opacity animation patterns

### Secondary (MEDIUM confidence)
- [Mac virtual key codes (kVK_ANSI_Slash = 0x2C = 44)](https://gist.github.com/swillits/df648e87016772c7f7e5dbed2b345066) -- confirms keyCode 44 is slash, "?" requires Shift on US layout
- [Raycast extensions-swift-tools](https://github.com/raycast/extensions-swift-tools) -- UserDefaults works normally in Raycast Swift binaries (not sandboxed)

### Tertiary (LOW confidence)
- None -- all findings verified against codebase and official documentation.

## Metadata

**Confidence breakdown:**
- Key detection ("?" via event.characters): HIGH -- Apple documentation is clear, and the codebase already uses keyCode-based detection for other keys
- Transient message implementation (CALayer): HIGH -- exact same pattern as CrosshairView pill and SelectionOverlay pill, both already working in the codebase
- UserDefaults persistence: HIGH -- already partially implemented and working in the codebase
- Auto-fade timing (2s hold + 0.5s fade): MEDIUM -- reasonable estimate but may need user testing to tune
- Multi-monitor behavior: HIGH -- existing architecture already isolates hint bar to cursor screen

**Research date:** 2026-02-13
**Valid until:** 2026-03-15 (stable -- NSEvent, Core Animation, and UserDefaults APIs are mature and unchanging)
