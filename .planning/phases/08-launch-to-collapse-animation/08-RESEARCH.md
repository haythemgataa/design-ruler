# Phase 8: Launch-to-Collapse Animation - Research

**Researched:** 2026-02-14
**Domain:** macOS Core Animation -- animating hint bar from expanded single-panel to collapsed two-panel layout
**Confidence:** HIGH

## Summary

Phase 8 adds the animated transition from the expanded hint bar (full text + keycaps in one glass panel) to the collapsed state (two separate keycap-only glass panels). Phase 7's 07-02 plan builds both visual states with a non-animated `setBarState()` visibility toggle. Phase 8 replaces that toggle with a smooth, GPU-composited animation.

The core challenge is animating from one glass panel to two glass panels. NSVisualEffectView/NSGlassEffectView cannot morph or split -- it is a single rectangular view with a blur backing. The recommended approach is a **snapshot-based crossfade**: (1) capture a bitmap of the expanded bar, (2) display it as a static `CALayer.contents` image, (3) hide the real expanded view, (4) show the two collapsed panels at their initial positions (overlapping the snapshot), (5) animate: fade out snapshot + fade out text labels in expanded content, while sliding keycap elements to their collapsed positions, (6) remove the snapshot layer. This avoids fighting NSVisualEffectView's internal layer hierarchy during animation and keeps the blur stable.

However, a simpler approach may work just as well and should be tried first: **direct frame animation** of the glass panels using `NSAnimationContext.runAnimationGroup` with the `animator()` proxy. NSVisualEffectView supports frame animation when `wantsLayer = true` and the view is layer-backed (which it is in this codebase). The expanded glass panel's frame animates to shrink and reposition to the left bar's target position while fading in opacity, and the two collapsed panels animate from hidden positions to their final positions. If the blur updates correctly during the frame animation (no flicker, no black artifacts), this approach is simpler and should be preferred. If the blur flickers during frame resize, fall back to the snapshot approach.

**Primary recommendation:** Use NSAnimationContext.runAnimationGroup with animator() proxy for coordinated multi-view frame + opacity animation. Trigger collapse on first mouse move. Duration 0.35s with easeOut timing. Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` by performing instant toggle when true.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| NSAnimationContext | macOS 10.5+ | Coordinate multi-view animations with completion handler | AppKit's standard animation coordination. Groups multiple `animator()` calls into one timing context. Already available at macOS 13 deployment target. |
| CATransaction | macOS 10.5+ | Low-level layer property animation (fallback) | Already used extensively in CrosshairView and HintBarView for pill flip and slide animations. |
| Core Animation (CABasicAnimation) | macOS 10.5+ | Per-layer animations for snapshot crossfade (if needed) | Already used for hint bar slide. Provides precise control over individual layer properties. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| NSWorkspace.accessibilityDisplayShouldReduceMotion | macOS 10.12+ | Check reduce-motion accessibility setting | Before every animation. If true, skip animation and do instant toggle. |
| NSView.bitmapImageRepForCachingDisplay / cacheDisplay | macOS 10.0+ | Snapshot expanded bar for crossfade animation | Only if direct frame animation causes blur flicker. Captures bitmap for static layer. |
| CAMediaTimingFunction | macOS 10.5+ | Custom easing curves | For easeOut timing on the collapse animation. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSAnimationContext + animator() | Raw CABasicAnimation per layer | More control but much more boilerplate. animator() handles frame/opacity natively for NSViews. |
| NSAnimationContext + animator() | SwiftUI .animation/.withAnimation | Cannot animate NSView frame/position from SwiftUI. The glass panels are AppKit NSViews. |
| NSAnimationContext + animator() | CATransaction on layer.position/bounds | Works for CALayers but NSVisualEffectView's backing layer is managed by AppKit -- must use animator() proxy for safe property modification. |
| Snapshot crossfade | No snapshot (animate live views only) | Preferred if blur stays clean during frame animation. Snapshot is fallback for blur flicker. |

**Installation:**
```
No new dependencies. All APIs from system frameworks: AppKit, QuartzCore.
Package.swift unchanged.
```

## Architecture Patterns

### Phase 7 Foundation (What Phase 8 Builds On)

After Phase 7 (07-02), HintBarView will have:
```
HintBarView (NSView, full screen width)
  +-- glassPanel (NSVisualEffectView/NSGlassEffectView) -- expanded bar
  |     +-- hostingView (NSHostingView<HintBarContent>)
  +-- leftCollapsedPanel (glass) -- collapsed left bar (hidden)
  |     +-- leftHostingView (NSHostingView<CollapsedLeftContent>)
  +-- rightCollapsedPanel (glass) -- collapsed right bar (hidden)
        +-- rightHostingView (NSHostingView<CollapsedRightContent>)
        +-- escTintLayer (CALayer)
```

State management: `BarState` enum (.expanded, .collapsed), `setBarState()` toggles `isHidden`.

### Pattern 1: Coordinated Multi-View Animation with NSAnimationContext

**What:** Animate expanded panel shrinking/fading while collapsed panels appear and slide to final positions, all synchronized.
**When to use:** Primary animation approach (try first).

```swift
// Source: Apple NSAnimationContext docs + codebase patterns
func animateToCollapsed(duration: TimeInterval = 0.35) {
    guard currentBarState == .expanded else { return }
    guard !isAnimatingCollapse else { return }
    isAnimatingCollapse = true

    // Respect accessibility
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        setBarState(.collapsed)
        isAnimatingCollapse = false
        return
    }

    // Prepare collapsed panels at starting positions (centered, zero alpha)
    leftCollapsedPanel?.alphaValue = 0
    rightCollapsedPanel?.alphaValue = 0
    leftCollapsedPanel?.isHidden = false
    rightCollapsedPanel?.isHidden = false

    NSAnimationContext.runAnimationGroup({ context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        context.allowsImplicitAnimation = true

        // Fade out expanded panel
        glassPanel?.animator().alphaValue = 0

        // Fade in collapsed panels
        leftCollapsedPanel?.animator().alphaValue = 1
        rightCollapsedPanel?.animator().alphaValue = 1
    }, completionHandler: { [weak self] in
        self?.glassPanel?.isHidden = true
        self?.glassPanel?.alphaValue = 1  // reset for potential reverse
        self?.currentBarState = .collapsed
        self?.isAnimatingCollapse = false
    })
}
```

### Pattern 2: Snapshot-Based Crossfade (Fallback)

**What:** Capture expanded bar bitmap, overlay it, animate position/opacity of snapshot + collapsed panels.
**When to use:** Only if Pattern 1 causes blur flicker during frame animation.

```swift
// Snapshot the expanded bar
func snapshotExpandedBar() -> CGImage? {
    guard let glass = glassPanel else { return nil }
    let rep = glass.bitmapImageRepForCachingDisplay(in: glass.bounds)
    guard let bitmap = rep else { return nil }
    glass.cacheDisplay(in: glass.bounds, to: bitmap)
    return bitmap.cgImage
}

// Create a snapshot layer, animate it, then remove
func animateToCollapsedWithSnapshot() {
    guard let snapshot = snapshotExpandedBar() else {
        setBarState(.collapsed)  // fallback to instant
        return
    }

    let snapshotLayer = CALayer()
    snapshotLayer.contents = snapshot
    snapshotLayer.frame = glassPanel!.frame
    snapshotLayer.cornerRadius = 18
    snapshotLayer.cornerCurve = .continuous
    snapshotLayer.masksToBounds = true
    layer?.addSublayer(snapshotLayer)

    // Hide real expanded, show collapsed at starting positions
    glassPanel?.isHidden = true
    leftCollapsedPanel?.isHidden = false
    rightCollapsedPanel?.isHidden = false
    leftCollapsedPanel?.alphaValue = 0
    rightCollapsedPanel?.alphaValue = 0

    // Animate snapshot fade-out + collapsed fade-in
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.35)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
    CATransaction.setCompletionBlock { [weak self] in
        snapshotLayer.removeFromSuperlayer()
        self?.currentBarState = .collapsed
        self?.isAnimatingCollapse = false
    }

    snapshotLayer.opacity = 0
    // collapsed panels animated via NSAnimationContext in parallel

    CATransaction.commit()
}
```

### Pattern 3: Animation Trigger Strategy

**What:** When and how to trigger the expanded-to-collapsed transition.
**When to use:** Wired into the existing event flow.

```
LAUNCH:
  1. HintBarView appears in .expanded state (full text visible)
  2. User reads instructions while seeing initial crosshair + pill

FIRST MOUSE MOVE:
  3. RulerWindow.mouseMoved fires → onFirstMove callback
  4. Ruler.handleFirstMove() already exists → add collapse trigger here
  5. Call hintBarView.animateToCollapsed()

ALTERNATIVE: Timer-based collapse (e.g., after 3s even without mouse move)
  - Could add a DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)
  - But first-mouse-move is more natural: user has started inspecting

NO REVERSE ANIMATION:
  - Once collapsed, stay collapsed for the session
  - Re-expanding would be disorienting during inspection
  - The expanded state is only useful on first launch for instruction text
```

### Anti-Patterns to Avoid

- **Animating NSVisualEffectView.material or blendingMode:** These are not animatable properties. Changing them causes an instant visual jump, not a smooth transition.
- **Using CALayer.position directly on NSVisualEffectView's backing layer:** NSVisualEffectView manages its own backing layer. Directly modifying `layer.position` or `layer.bounds` without going through the `animator()` proxy can desync AppKit's view geometry from Core Animation's layer geometry. Always use `view.animator().frame` for NSViews.
- **Animating frame resize of NSVisualEffectView without testing:** The `CABackdropLayer` inside NSVisualEffectView may not update correctly during frame resize animations. The blur region is sampled based on the layer's geometry, and mid-animation frames may show artifacts. Test this first; if it fails, use the snapshot approach.
- **Creating new NSVisualEffectView instances during animation:** Constructing glass panels mid-animation is expensive and causes a visible pop. All panels must be pre-created in Phase 7's `setupHostingView()` and positioned before animation starts.
- **Forgetting to reset alphaValue after animation:** If the animation fades the expanded panel to 0, its `alphaValue` must be reset to 1 in the completion handler (in case of future reverse animation or reuse).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-view animation coordination | Manual CABasicAnimation per layer with manual timing sync | NSAnimationContext.runAnimationGroup + animator() proxy | Automatically syncs timing, handles completion, respects layer-backed view rules |
| Easing curves | Custom bezier math | CAMediaTimingFunction(name: .easeOut) | System-provided, GPU-optimized, matches platform conventions |
| View snapshot for animation | CGContext manual rendering | NSView.bitmapImageRepForCachingDisplay + cacheDisplay | Apple's official snapshot API, handles Retina scale, subview rendering |
| Reduce-motion check | Custom preference or ignoring it | NSWorkspace.shared.accessibilityDisplayShouldReduceMotion | System-level accessibility API. Ignoring it is an accessibility violation. |

**Key insight:** The animation is fundamentally a crossfade between two states of the same logical UI element. The complexity comes from the glass panel split (one to two), not from the animation itself. Pre-building both states in Phase 7 and animating visibility/opacity is far simpler than trying to dynamically create or morph views during the transition.

## Common Pitfalls

### Pitfall 1: NSVisualEffectView Blur Artifacts During Frame Animation
**What goes wrong:** When animating the frame of an NSVisualEffectView, the internal CABackdropLayer may not update its sampling region correctly on every animation frame, causing the blur to show black, flash, or display stale content.
**Why it happens:** CABackdropLayer samples rendered content from sibling views at the layer's current geometry. During frame animation, intermediate geometries are calculated by Core Animation's render server, but the backdrop sampling may lag or use the model layer's geometry rather than the presentation layer's.
**How to avoid:** Test the direct frame animation approach first. If blur artifacts appear, switch to the snapshot crossfade approach (Pattern 2) which avoids resizing the glass panel entirely -- it just fades opacity.
**Warning signs:** Black rectangles, flickering blur, or "doubled" blur during the transition.

### Pitfall 2: Animation Overlap with Slide Animation
**What goes wrong:** If the user moves the cursor to the bottom during the collapse animation, the hint bar tries to slide (bottom-to-top) at the same time as collapsing.
**Why it happens:** `updatePosition()` and `animateToCollapsed()` both modify the same views' properties simultaneously, creating conflicting animations.
**How to avoid:** Add an `isAnimatingCollapse` guard. During collapse animation, skip `updatePosition()` calls. The collapse animation is brief (0.35s), so missing one position update is acceptable.
**Warning signs:** Bar teleports, animation stutters, or bar gets stuck in wrong position.

### Pitfall 3: Collapsed Panels Visible at Wrong Position Before Animation Starts
**What goes wrong:** When `leftCollapsedPanel?.isHidden = false` is called, the panel appears at its final layout position for one frame before the animation moves it.
**Why it happens:** The layout is computed in `configure()` (Phase 7), so panels have their final positions. Setting `isHidden = false` instantly reveals them at those positions.
**How to avoid:** Set `alphaValue = 0` before `isHidden = false`. Then animate `alphaValue` to 1. The panel exists in the view hierarchy at the correct position but is invisible until the animation starts.
**Warning signs:** A single-frame flash of the collapsed bars at their final position before animation begins.

### Pitfall 4: Completion Handler Timing on Fast Machines
**What goes wrong:** The completion handler fires but the visual transition appears incomplete because Core Animation's render server hasn't flushed the final frame yet.
**Why it happens:** NSAnimationContext's completion handler fires when the animation is logically complete, which may be slightly before the render server displays the final frame.
**How to avoid:** Keep the completion handler light (just state bookkeeping like setting `isHidden` and resetting `alphaValue`). Don't add visual changes in the completion handler that would create a visible pop.
**Warning signs:** Brief visual glitch at the end of the animation.

### Pitfall 5: Forgetting Accessibility Reduce Motion
**What goes wrong:** Users with "Reduce Motion" enabled see the full animation, causing discomfort.
**Why it happens:** Developer doesn't check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
**How to avoid:** Check at the top of `animateToCollapsed()`. If true, call `setBarState(.collapsed)` (instant toggle from Phase 7) and return immediately.
**Warning signs:** No warning signs -- this is a silent failure that affects accessibility users.

### Pitfall 6: Stale Collapsed Panel Positions After Slide Animation
**What goes wrong:** The collapsed panels were positioned in `configure()` relative to the HintBarView's initial frame. If the bar has slid to the top (via `animateSlide()`), the collapsed panels appear at the bottom-relative position.
**Why it happens:** HintBarView's `frame.origin.y` changes during slide, but the collapsed panels' frames are relative to HintBarView's bounds (which don't change). This should actually work correctly because the collapsed panels are subviews of HintBarView, so their position is in HintBarView's coordinate space. When HintBarView slides, all subviews move with it.
**How to avoid:** Verify during testing that collapsed panels follow the container correctly. No code change needed -- this is how NSView parent-child relationships work. But worth verifying.
**Warning signs:** Collapsed bars appear at bottom when expanded bar was at top.

## Code Examples

Verified patterns from the existing codebase and official sources:

### Existing Slide Animation Pattern (HintBarView.swift -- reference)
```swift
// Source: HintBarView.swift lines 197-227
private func animateSlide(to finalY: CGFloat, screenHeight: CGFloat, exitDown: Bool) {
    guard let layer = self.layer else {
        frame.origin.y = finalY
        return
    }
    isAnimating = true
    let anim = CAKeyframeAnimation(keyPath: "position.y")
    anim.values = [currentPos, offscreenExit, offscreenEntry, finalY]
    anim.keyTimes = [0, 0.3, 0.3001, 1]
    anim.duration = 0.3
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
        self?.isAnimating = false
    }
    frame.origin.y = finalY
    layer.add(anim, forKey: "hintBarSlide")
    CATransaction.commit()
}
```

### Existing Pill Flip Animation Pattern (CrosshairView.swift -- reference)
```swift
// Source: CrosshairView.swift lines 305-312
CATransaction.begin()
if flipped {
    CATransaction.setAnimationDuration(0.15)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
} else {
    CATransaction.setDisableActions(true)
}
// ... layer property changes ...
CATransaction.commit()
```

### Recommended Collapse Animation Implementation
```swift
// Source: research synthesis -- new code for Phase 8

// Add to HintBarView properties:
private var isAnimatingCollapse = false

/// Animate from expanded to collapsed state.
/// Call from Ruler.handleFirstMove() or after a delay.
func animateToCollapsed(duration: TimeInterval = 0.35) {
    guard currentBarState == .expanded else { return }
    guard !isAnimatingCollapse else { return }
    isAnimatingCollapse = true

    // Accessibility: instant toggle if reduce motion is enabled
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        setBarState(.collapsed)
        isAnimatingCollapse = false
        return
    }

    // Prepare collapsed panels: visible but transparent
    leftCollapsedPanel?.alphaValue = 0
    rightCollapsedPanel?.alphaValue = 0
    leftCollapsedPanel?.isHidden = false
    rightCollapsedPanel?.isHidden = false

    NSAnimationContext.runAnimationGroup({ context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        context.allowsImplicitAnimation = true

        // Fade out expanded bar
        self.glassPanel?.animator().alphaValue = 0

        // Fade in collapsed bars
        self.leftCollapsedPanel?.animator().alphaValue = 1
        self.rightCollapsedPanel?.animator().alphaValue = 1
    }, completionHandler: { [weak self] in
        guard let self else { return }
        self.glassPanel?.isHidden = true
        self.glassPanel?.alphaValue = 1  // reset for potential reuse
        self.currentBarState = .collapsed
        self.isAnimatingCollapse = false
    })
}
```

### Trigger Point in Ruler.swift
```swift
// Source: adapted from Ruler.swift handleFirstMove()
private func handleFirstMove() {
    firstMoveReceived = true

    // Collapse hint bar on first mouse move
    if let cursorWindow = activeWindow {
        cursorWindow.collapseHintBar()
    }
}

// In RulerWindow:
func collapseHintBar() {
    guard hintBarView.superview != nil else { return }
    hintBarView.animateToCollapsed()
}
```

### Guard Against Slide Animation Overlap
```swift
// Source: adapted from HintBarView.swift updatePosition()
func updatePosition(cursorY: CGFloat, screenHeight: CGFloat) {
    // Block position updates during collapse animation
    guard !isAnimatingCollapse else { return }

    // ... existing slide logic unchanged ...
}
```

### Reduce Motion Check
```swift
// Source: Apple NSWorkspace docs
// Check at animation entry point, not at a higher level
if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    setBarState(.collapsed)  // instant, no animation
    return
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSViewAnimation (older API) | NSAnimationContext.runAnimationGroup | macOS 10.7+ | Block-based, completion handlers, timing functions. NSViewAnimation is effectively deprecated in practice. |
| Manual CALayer.position manipulation | NSView.animator().frame | macOS 10.5+ (improved 10.7+) | Safe for layer-backed views. Respects AppKit's layer management. Avoids desync. |
| Ignoring reduce-motion | NSWorkspace.accessibilityDisplayShouldReduceMotion | macOS 10.12+ | Required for accessibility compliance. Check before any non-essential animation. |

**Deprecated/outdated:**
- `NSViewAnimation`: Still available but the older, less flexible approach. NSAnimationContext is preferred.
- Direct `layer.position` / `layer.bounds` manipulation on layer-backed NSViews: Unsafe. Use `animator()` proxy instead.

## Animation Design Decisions

### Trigger: First Mouse Move (Recommended)

**Rationale:** The expanded bar shows instructional text ("Use arrows to skip edges, plus shift to reverse. ESC to exit."). This text is useful on launch -- the user sees it while the initial pill is fading in and before they start moving. Once they move the mouse, they've begun inspection and no longer need the instructions. The collapse coincides with the "system crosshair hidden, custom CAShapeLayer takes over" transition, making it feel like a natural phase change.

**Alternative considered -- timer (3s delay):** Less natural. The user may have already started inspecting before 3s, or may still be reading. Mouse move is a clear intent signal.

**Alternative considered -- both (timer OR first move):** Adds complexity for marginal benefit. First move alone is sufficient.

### Duration: 0.35s with easeOut

**Rationale:** Matches the existing hint bar slide animation duration (0.3s) but slightly longer to give the crossfade more visual weight. The collapse is a one-time event per session, so it can be slightly more deliberate than the repeated slide animations. EaseOut makes it feel responsive (fast start, gentle settle).

### No Reverse Animation

**Rationale:** Once collapsed, the bar stays collapsed for the entire session. The instructions have been read; re-expanding them would be jarring during inspection. This simplifies the implementation significantly -- no need for `animateToExpanded()` or bidirectional state machine.

### Crossfade vs. Morphing

**Rationale:** A true morph (expanded bar reshaping into two bars) would require either: (a) clipping/masking tricks with multiple layers, or (b) path animation on the glass panel's shape. Both are fragile with NSVisualEffectView because the blur sampling region must match the view's geometry. A crossfade (fade out expanded, fade in collapsed) is visually clean, technically simple, and avoids any blur artifacts during transition.

### Expanded Panel Frame: Fade Only, No Resize

**Rationale:** Do NOT animate the expanded panel's frame shrinking. Just fade its opacity to 0. Resizing NSVisualEffectView during animation risks blur flicker (Pitfall 1). Fading is a safe layer-composited operation that doesn't affect the blur sampling.

## Open Questions

1. **Does NSVisualEffectView opacity fade show through the blur?**
   - What we know: `alphaValue` on an NSVisualEffectView should fade the entire view including its blur. This is a standard NSView property.
   - What's unclear: Whether fading a glass panel to 0 while another glass panel fades to 1 at an overlapping position creates visual artifacts (double blur, brightness spike).
   - Recommendation: Test the crossfade with both panels at 50% opacity simultaneously. If artifacts appear, stagger the timing (fade out expanded first 0-0.2s, then fade in collapsed 0.15-0.35s).

2. **Should the collapse animation start immediately on first move or after a brief delay?**
   - What we know: First mouse move triggers `hideSystemCrosshair()` and edge detection. Adding collapse animation here adds visual work.
   - What's unclear: Whether simultaneous hide-crosshair + collapse-bar + detect-edges feels too busy.
   - Recommendation: Start with immediate collapse on first move. If it feels too busy, add a 0.1-0.2s delay (`DispatchQueue.main.asyncAfter`).

3. **NSGlassEffectView (macOS 26+) -- does it behave the same for opacity animation?**
   - What we know: Phase 7's `makeGlassPanel()` returns NSGlassEffectView on macOS 26+, NSVisualEffectView on older versions. Both are NSView subclasses.
   - What's unclear: Whether NSGlassEffectView handles `alphaValue` animation identically.
   - Recommendation: Test on both paths. The `animator().alphaValue` API is NSView-level, so it should work identically. But NSGlassEffectView is new and less battle-tested.

## Sources

### Primary (HIGH confidence)
- [NSAnimationContext - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsanimationcontext) -- block-based animation API, completion handlers
- [NSWorkspace.accessibilityDisplayShouldReduceMotion - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion) -- reduce motion check
- [NSView.bitmapImageRepForCachingDisplay - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsview/1483440-bitmapimagerepforcachingdisplay) -- view snapshot API
- [CAAnimationGroup - Apple Developer Documentation](https://developer.apple.com/documentation/quartzcore/caanimationgroup) -- grouped layer animations
- [Advanced Animation Tricks - Apple Core Animation Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/AdvancedAnimationTricks/AdvancedAnimationTricks.html) -- transition animations, grouping
- Codebase: HintBarView.swift (slide animation pattern), CrosshairView.swift (pill flip pattern), Ruler.swift (first move callback)

### Secondary (MEDIUM confidence)
- [Scale, Rotate, Fade, and Translate NSView Animations in Swift](https://www.advancedswift.com/nsview-animations-guide/) -- NSAnimationContext examples with animator() proxy
- [Better iOS Animations with CATransaction](https://medium.com/@joncardasis/better-ios-animations-with-catransaction-72a7425673a6) -- CATransaction patterns
- [Reverse Engineering NSVisualEffectView - Oskar Groth](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview) -- CABackdropLayer internals, potential flicker causes
- [A short guide to OS X animations - Jonathan Willing](https://jwilling.com/blog/osx-animations/) -- NSView animation best practices
- [CALayer - Apple Developer Documentation](https://developer.apple.com/documentation/quartzcore/calayer) -- layer.contents for snapshot, animatable properties

### Tertiary (LOW confidence)
- NSVisualEffectView alphaValue crossfade behavior with overlapping panels -- no official docs on this specific scenario; must test
- NSGlassEffectView (macOS 26) animation behavior -- too new for documented patterns; must test on Tahoe
- Exact duration/timing that "feels right" for the collapse -- subjective; needs user testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- NSAnimationContext, CATransaction, animator() proxy are all stable, well-documented APIs available since macOS 10.5-10.12. No new dependencies.
- Architecture: HIGH -- the approach builds on Phase 7's pre-created panels and existing animation patterns (slide, pill flip). The trigger point (first mouse move) already exists as a callback.
- Animation technique: MEDIUM -- the crossfade approach is sound but the specific behavior of NSVisualEffectView/NSGlassEffectView during opacity animation with overlapping panels needs empirical testing.
- Pitfalls: HIGH -- all identified pitfalls have known mitigations. The main risk (blur flicker) has a fallback (snapshot approach).

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (stable domain, 30-day window)
