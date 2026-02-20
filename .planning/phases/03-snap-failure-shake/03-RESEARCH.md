# Phase 3: Snap Failure Shake - Research

**Researched:** 2026-02-13
**Domain:** Core Animation shake feedback on CALayer sublayers (macOS/Swift)
**Confidence:** HIGH

## Summary

The "snap failure shake" is a well-understood macOS UI idiom (login rejection dialog). It requires a damped horizontal oscillation animation on the selection overlay's CALayers, followed by a fade-out removal. The codebase already has `SelectionOverlay` with 4 independent sublayers (`rectLayer`, `fillLayer`, `pillBgLayer`, `pillTextLayer`) and an existing `remove(animated:)` method that does a 0.15s opacity fade. The `SelectionManager.endDrag()` method is the exact trigger point -- when `edgeDetector.snapSelection()` returns `nil`, it currently calls `sel.remove(animated: true)`.

The implementation is straightforward: add a `shakeAndRemove()` method to `SelectionOverlay` that applies an additive `CAKeyframeAnimation` on `position.x` to all 4 layers simultaneously, then chains the existing fade-out via `CATransaction.setCompletionBlock`. The critical correctness concern is ensuring no layers jump to wrong positions after animation completes -- the `isAdditive = true` pattern handles this natively since values are relative offsets from the current position, and the model layer values are never changed.

**Primary recommendation:** Add a `shakeAndRemove()` method to `SelectionOverlay` using additive `CAKeyframeAnimation` on `position.x` with damped values, chained to the existing fade-out removal via `CATransaction` completion block. Change `SelectionManager.endDrag()` to call `shakeAndRemove()` instead of `remove(animated: true)` on snap failure.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| QuartzCore (Core Animation) | System | CAKeyframeAnimation for shake + fade | Already used throughout codebase; GPU-composited, ~0 CPU cost |

### Supporting
No additional libraries needed. This is pure Core Animation work using APIs already imported.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Additive CAKeyframeAnimation on each layer | Container CALayer wrapping all 4 sublayers | Cleaner (animate 1 layer instead of 4), but requires refactoring SelectionOverlay.setupLayers to use a container -- more invasive change for minimal benefit |
| CAKeyframeAnimation with values array | CAKeyframeAnimation with CGMutablePath | Path-based is the classic NSWindow shake pattern, but values array is simpler for sublayer position.x animation and matches the codebase's existing animation style |
| Manual damped oscillation formula | Hardcoded decreasing keyframe values | Formula (Ae^(-at)cos(wt)) is overkill for 3-4 shakes; hardcoded values are simpler and match every known implementation |

## Architecture Patterns

### Trigger Flow
```
SelectionManager.endDrag()
  → edgeDetector.snapSelection() returns nil
    → sel.shakeAndRemove()  // NEW (replaces sel.remove(animated: true))
      → Apply additive CAKeyframeAnimation on position.x to all layers
      → CATransaction.setCompletionBlock:
        → sel.remove(animated: true)  // existing 0.15s fade-out
```

### Pattern 1: Additive Keyframe Shake on CALayer
**What:** Apply a `CAKeyframeAnimation` with `isAdditive = true` on `position.x` to animate relative horizontal displacement. Values describe a damped oscillation: `[0, -10, 10, -6, 6, -2, 2, 0]`.
**When to use:** When you need to shake a layer without knowing or modifying its absolute position.
**Example:**
```swift
// Source: Verified pattern from hackingwithswift.com + Apple Core Animation Guide
func shakeAndRemove() {
    let shake = CAKeyframeAnimation(keyPath: "position.x")
    shake.values = [0, -10, 10, -6, 6, -2, 2, 0]
    shake.keyTimes = [0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]
    shake.duration = 0.4
    shake.isAdditive = true

    let layers: [CALayer] = [rectLayer, fillLayer, pillBgLayer, pillTextLayer]

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
        self?.remove(animated: true)
    }
    for layer in layers {
        layer.add(shake, forKey: "shake")
    }
    CATransaction.commit()
}
```

### Pattern 2: Chaining Animations via CATransaction Completion
**What:** Use `CATransaction.setCompletionBlock` to sequence shake -> fade-out. The completion fires after ALL animations in the transaction finish.
**When to use:** When animations must run sequentially (not overlapping).
**Example:**
```swift
// Source: Apple Core Animation Programming Guide - Advanced Animation Tricks
CATransaction.begin()
CATransaction.setCompletionBlock {
    // This runs after the shake finishes
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.15)
    CATransaction.setCompletionBlock {
        layers.forEach { $0.removeFromSuperlayer() }
    }
    layers.forEach { $0.opacity = 0 }
    CATransaction.commit()
}
// Add shake animations here
CATransaction.commit()
```

### Anti-Patterns to Avoid
- **Modifying model layer position during shake:** The additive animation adds to the current model value. If you change `layer.position.x` during the shake, the animation jumps. Leave model values untouched.
- **Using fillMode + isRemovedOnCompletion = false:** This is a common anti-pattern. It hides the snap-back symptom but leaves model and presentation layers out of sync. Since our shake returns to origin (final value = 0) and is additive, the default `isRemovedOnCompletion = true` is correct -- removing the animation changes nothing because the final additive offset is 0.
- **Using CGMutablePath for sublayer shake:** The `path` property on CAKeyframeAnimation is designed for animating `position` (a CGPoint). It works great for NSWindow frame origin (the classic usage), but for sublayers where we only want horizontal movement, `values` on `position.x` is simpler and avoids having to construct a path that moves only horizontally.
- **Animating absolute position instead of using isAdditive:** Each of the 4 layers has a different position. Calculating absolute positions for each layer's shake would be error-prone. `isAdditive = true` means we just specify offsets: `[0, -10, 10, ...]` -- same values work for all layers regardless of their current position.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Damped oscillation curve | Mathematical formula with exponential decay | Hardcoded keyframe values `[0, -10, 10, -6, 6, -2, 2, 0]` | Every macOS shake implementation uses 3-4 hand-tuned keyframes. The formula adds complexity with no visual benefit for such a short animation. |
| Animation sequencing | Manual DispatchQueue.main.asyncAfter timing | CATransaction.setCompletionBlock | CATransaction correctly fires after the GPU finishes the animation. Manual timing can drift and cause visual glitches. |
| Multi-layer synchronization | Separate animation objects per layer | Single CAKeyframeAnimation object shared across all layer.add() calls | Core Animation allows the same animation object to be added to multiple layers. They run in sync automatically. |

**Key insight:** The shake animation is ~15 lines of code total. The only design decision is the keyframe values and duration. Everything else is standard Core Animation API that the codebase already uses extensively.

## Common Pitfalls

### Pitfall 1: Layer Position Jumps After Animation Completes
**What goes wrong:** After the shake animation, layers snap to a different position than before the shake started.
**Why it happens:** Either (a) model layer position was modified during or after the animation, or (b) `isAdditive` was not set and absolute values were used incorrectly, or (c) another implicit animation was triggered on position.
**How to avoid:** Use `isAdditive = true` with values starting and ending at 0. The model layer position is never modified, so when the animation is removed, nothing changes. Wrap the shake in `CATransaction.begin()/commit()` to isolate it from other animation changes.
**Warning signs:** Layer jumps sideways immediately after the shake ends, before the fade begins.

### Pitfall 2: Shake and Fade Overlapping
**What goes wrong:** The fade-out starts before the shake finishes, making the overlay shimmer while shaking.
**Why it happens:** Starting both animations simultaneously instead of sequencing them.
**How to avoid:** Use `CATransaction.setCompletionBlock` to start the fade-out only after the shake transaction completes. Do NOT start both animations in the same transaction.
**Warning signs:** Overlay becomes transparent while still shaking.

### Pitfall 3: Pill Layers Not Shaking (Only Rect Shakes)
**What goes wrong:** The selection rectangle shakes but the dimension pill stays static, looking disconnected.
**Why it happens:** Only applying the shake animation to `rectLayer` and `fillLayer`, forgetting `pillBgLayer` and `pillTextLayer`. Note: pill layers start with `opacity = 0` and are only shown after snap succeeds. For snap failure, they may never have been shown (the pill is shown in `animateSnap()`). If pill was never shown, shaking invisible layers is harmless.
**How to avoid:** Apply shake to all 4 layers. If pill is invisible (snap never succeeded), the animation runs on invisible layers at zero cost.
**Warning signs:** Visual disconnect -- rectangle shakes but pill stays put (only visible if pill somehow became visible before snap).

### Pitfall 4: Shake Fires During Successful Snap
**What goes wrong:** Even successful selections shake before settling.
**Why it happens:** Calling `shakeAndRemove()` in the wrong code path (e.g., always on `endDrag` instead of only on snap failure).
**How to avoid:** The shake path ONLY triggers when `edgeDetector.snapSelection()` returns `nil`. The `endDrag()` method already has a clear if/else branch for this.
**Warning signs:** All selections shake, even ones that snap correctly.

### Pitfall 5: Minimum Drag Distance Check Bypasses Shake
**What goes wrong:** Very small drags (< 4px in either dimension) are removed without animation and without shake.
**Why it happens:** The `endDrag()` method has an early return for drags smaller than 4x4 pixels: `sel.remove(animated: false)`.
**How to avoid:** This is actually correct behavior -- tiny accidental drags should not trigger the shake animation. The shake should only play for intentional drags that fail to snap. No code change needed for this case.
**Warning signs:** N/A -- this is desired behavior.

## Code Examples

Verified patterns from official sources and codebase analysis:

### Complete shakeAndRemove() Implementation
```swift
// Pattern: additive CAKeyframeAnimation on position.x
// Source: Verified from hackingwithswift.com, cimgf.com, Apple Core Animation Guide
// Adapted to match codebase conventions (CATransaction pattern from CrosshairView/HintBarView)

/// Shake horizontally (macOS login rejection idiom) then fade out and remove.
func shakeAndRemove() {
    let shake = CAKeyframeAnimation(keyPath: "position.x")
    // Damped oscillation: large → medium → small → center
    shake.values = [0, -10, 10, -6, 6, -2, 2, 0]
    shake.keyTimes = [0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]
    shake.duration = 0.4
    shake.isAdditive = true  // Critical: values are offsets from current position

    let layers: [CALayer] = [rectLayer, fillLayer, pillBgLayer, pillTextLayer]

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
        // After shake completes, fade out and remove
        self?.remove(animated: true)
    }
    for layer in layers {
        layer.add(shake, forKey: "shake")
    }
    CATransaction.commit()
}
```

### SelectionManager.endDrag() Modification
```swift
// BEFORE (current code):
} else {
    sel.remove(animated: true)
    return false
}

// AFTER (with shake):
} else {
    sel.shakeAndRemove()
    return false
}
```

### macOS Login Rejection Shake Parameters (Reference)
```
Classic macOS dialog shake:
  - numberOfShakes: 3-4
  - duration: 0.3-0.5s total
  - displacement: 4-5% of element width (for windows)
  - For CALayer sublayers: 8-12px displacement is standard

Recommended values for this project:
  - values: [0, -10, 10, -6, 6, -2, 2, 0]  (4 oscillations, damped)
  - duration: 0.4s
  - timing: linear keyTimes (equal spacing gives natural feel)
  - Followed by: 0.15s fade-out (existing remove(animated:) duration)
  - Total perceived duration: ~0.55s
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSWindow frame animation with CGMutablePath | CAKeyframeAnimation with additive values on position.x | Always available, but sublayer pattern became standard with modern Core Animation | Values-based approach is simpler for sublayers; path-based is still used for window-level animation |
| fillMode .forwards + isRemovedOnCompletion false | Set model layer to final value + let animation be removed normally | Community consensus ~2012-2015 | Avoids model/presentation layer desync bugs |

**Deprecated/outdated:**
- None. CAKeyframeAnimation API is stable and unchanged. All patterns used are current.

## Open Questions

1. **Exact shake displacement values**
   - What we know: 8-12px is standard for sublayer shake; macOS login dialog uses ~4-5% of window width
   - What's unclear: Whether 10px feels right for the selection overlay specifically (depends on typical selection size)
   - Recommendation: Start with `[0, -10, 10, -6, 6, -2, 2, 0]` and tune visually if needed. The values are trivially adjustable constants.

2. **Should the dash pattern revert before shake?**
   - What we know: During drag, `SelectionOverlay` uses a dashed stroke (`lineDashPattern = [4, 3]`). On successful snap, the dash is removed (`lineDashPattern = nil`). On failure, the dash is still present.
   - What's unclear: Whether the dashed outline shaking looks good or if it should become solid briefly before shaking.
   - Recommendation: Keep the dash pattern during shake -- it reinforces that this was an unfinalized selection. Visual testing will confirm.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `SelectionOverlay.swift`, `SelectionManager.swift`, `CrosshairView.swift`, `HintBarView.swift` -- verified existing animation patterns (CATransaction, CAKeyframeAnimation, completion blocks)
- [Apple Core Animation Programming Guide - Advanced Animation Tricks](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/AdvancedAnimationTricks/AdvancedAnimationTricks.html) -- CATransaction completion block chaining
- [Apple Core Animation Programming Guide - Animating Layer Content](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CreatingBasicAnimations/CreatingBasicAnimations.html) -- additive animations, layer animation fundamentals

### Secondary (MEDIUM confidence)
- [Hacking with Swift - CAKeyframeAnimation shake](https://www.hackingwithswift.com/example-code/calayer/how-to-create-keyframe-animations-using-cakeyframeanimation) -- shake values pattern `[0, 10, -10, 10, -5, 5, -5, 0]`
- [CIMGF - Core Animation Window Shake Effect](https://www.cimgf.com/2008/02/27/core-animation-tutorial-window-shake-effect/) -- classic macOS shake parameters: numberOfShakes=4, duration=0.5, vigour=0.05
- [Ole Begemann - Prevent CAAnimation Snap-Back](https://oleb.net/blog/2012/11/prevent-caanimation-snap-back/) -- why fillMode/isRemovedOnCompletion is an anti-pattern; proper model layer management
- [objc.io - Animations Explained](https://www.objc.io/issues/12-animations/animations-explained/) -- additive animations, isAdditive property semantics

### Tertiary (LOW confidence)
- None. All findings verified with multiple sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Core Animation is already used throughout the codebase; no new dependencies
- Architecture: HIGH - Trigger point (`endDrag`), target class (`SelectionOverlay`), and chaining pattern (`CATransaction.setCompletionBlock`) are all clearly identified in existing code
- Pitfalls: HIGH - The main risk (position jump after animation) is well-documented and directly addressed by `isAdditive = true` pattern; verified with multiple authoritative sources

**Research date:** 2026-02-13
**Valid until:** Indefinite -- Core Animation API is stable; no version-dependent behavior
