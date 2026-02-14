# Domain Pitfalls: Hint Bar Redesign with Liquid Glass and Split Animation

**Domain:** macOS overlay window -- adding blur/glass effects and morphing animations to existing CALayer UI
**Researched:** 2026-02-13
**Milestone context:** Redesigning existing hint bar from SwiftUI (NSHostingView) to a liquid glass style with a bar-splitting animation

---

## Critical Pitfalls

Mistakes that cause visual breakage, performance regression, or require architectural rework.

---

### Pitfall 1: NSVisualEffectView Cannot Blur an Opaque Window's Own Content

**What goes wrong:** The current window is opaque (`window.isOpaque = true`, RulerWindow.swift line 43) with a frozen screenshot as background. `NSVisualEffectView` with `.behindWindow` blending mode samples content *behind the window* from the window server -- not from sibling views within the same window. Since the window is opaque, the window server sees a solid rectangle, and the blur shows a solid rectangle. No blur effect is visible. Switching to `.withinWindow` blending mode *can* work but has constraints: it blurs content from behind the view within the window's layer tree, and the screenshot must be correctly positioned as a layer below the effect view.

**Why it happens:** `NSVisualEffectView` relies on `CABackdropLayer`, a private Core Animation class that samples pixels from the window server's composited output. An opaque window tells the window server "there is nothing behind me" -- so `.behindWindow` backdrop sampling returns nothing meaningful. The frozen screenshot exists as a bitmap assigned to a `CALayer.contents` property (RulerWindow.swift line 98), which is within the window but requires the `.withinWindow` mode and proper layer ordering to sample.

**Consequences:**
- Hint bar background appears as solid gray/black instead of frosted glass
- Or the blur works during development (non-opaque test config) but breaks in production
- Switching `isOpaque = false` to "fix" this destroys the frozen-screenshot illusion and introduces flicker on launch

**Prevention:**
1. Do NOT use `NSVisualEffectView` with `.behindWindow` for this use case. The window must stay opaque.
2. Use `.withinWindow` blending mode with careful view hierarchy ordering: place the `NSVisualEffectView` *above* the background image view so it can sample through the image content. Both must be in the same `NSView` subtree.
3. Alternative: skip `NSVisualEffectView` entirely and implement blur manually -- render the screenshot region under the hint bar into a small `CIImage`, apply `CIGaussianBlur`, composite as `CALayer.contents` bitmap. One-time render (frozen screenshot), so performance is not a concern.
4. Third option: use a separate non-opaque child `NSWindow` positioned over the hint bar area. The child window can use `.behindWindow` because the main window's content IS behind it from the window server's perspective. But this adds multi-window coordination complexity.

**Detection:** If the hint bar background is a solid color with no visible blur/transparency of the screenshot beneath it, this pitfall has been hit.

**Confidence:** HIGH -- based on [Apple NSVisualEffectView docs](https://developer.apple.com/documentation/appkit/nsvisualeffectview), [Reverse Engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview), and direct analysis of the codebase's opaque window setup.

---

### Pitfall 2: NSVisualEffectView and Layer-Hosting Views Are Incompatible

**What goes wrong:** The CrosshairView uses `wantsLayer = true` and directly manipulates `CAShapeLayer` sublayers (CrosshairView.swift lines 141-183). Adding an `NSVisualEffectView` as a sibling that shares the same layer tree causes the visual effect view's internal `CABackdropLayer` to malfunction. The blur effect disappears entirely.

**Why it happens:** `NSVisualEffectView` creates its own internal layer hierarchy including `CABackdropLayer`. In a layer-hosting view hierarchy, the view system's layer management conflicts with manual layer management. The window server either cannot see the backdrop layer or the layer tree gets "flattened" after ~1 second of inactivity (documented WindowServer behavior for performance), destroying the backdrop's ability to sample live content.

**Consequences:**
- Blur effect silently fails (no error, no crash)
- May appear to work initially, then breaks after 1 second of window idleness
- Intermittent: works on some macOS versions but not others

**Prevention:**
1. Keep `NSVisualEffectView` in a *separate* NSView subtree from any layer-hosting views. The hint bar is already a separate NSView (HintBarView) added as a sibling of CrosshairView (RulerWindow.swift lines 72-77). This is the correct architecture.
2. Verify that HintBarView itself does not become a layer-hosting view. The current `wantsLayer = true` (line 30) makes it layer-backed (safe). But adding CALayers directly to its `layer` property would make it layer-hosting (breaks blur).
3. If you need both blur AND custom CALayers in the hint bar, stack them: `hintBarView > [NSVisualEffectView (bottom), customLayerView (top)]` where the blur view and the layer-hosting content view are siblings, not parent-child.

**Detection:** If blur works initially but disappears after the window has been idle for about one second, the WindowServer layer flattening is destroying the backdrop layer.

**Confidence:** HIGH -- based on [NSVisualEffectView layer-hosting incompatibility](https://databasefaq.com/index.php/answer/164756/osx-calayer-nsview-nswindow-nsvisualeffectview-how-to-use-nsvisualeffectview-in-a-layer-host-nsview), [CABackdropLayer flattening behavior](https://medium.com/@avaidyam/capluginlayer-cabackdroplayer-f56e85d9dc2c).

---

### Pitfall 3: NSGlassEffectView / .glassEffect() Requires macOS 26 -- Breaks Deployment Target

**What goes wrong:** `NSGlassEffectView` (AppKit) and `.glassEffect()` (SwiftUI) are only available on macOS 26.0 (Tahoe). The project targets macOS 13+ (Package.swift line 7: `.macOS(.v13)`). Using these APIs without availability checks causes a compile error. Using them with `if #available(macOS 26.0, *)` means the glass effect is only visible to macOS 26+ users, while macOS 13-15 users see a fallback.

**Additional regression risk:** On macOS 26.2+, a known regression (FB21375029) causes `.glassEffect()` to stop working in floating/non-standard windows (which the Ruler uses -- `.statusBar` level, `.borderless`, `isOpaque = true`). The glass effect may degrade to a simple blur or disappear entirely.

**Consequences:**
- Compile error if used unconditionally
- Two completely different code paths to maintain (glass vs. fallback)
- Even on macOS 26, glass may not work in this window configuration

**Prevention:**
1. Do NOT use `NSGlassEffectView` or `.glassEffect()` as the primary implementation. The project targets macOS 13+ and the Ruler's window configuration may trigger the 26.2 regression.
2. Implement the "liquid glass" visual style manually using `NSVisualEffectView` (`.withinWindow`, `.hudWindow` or `.popover` material) or CIFilter-based blur. Both work on macOS 13+.
3. If native Liquid Glass is desired as a future enhancement, add it behind `if #available(macOS 26.0, *)` with the manual implementation as the fallback. But do not make it the primary path for this milestone.

**Detection:** Build fails with "NSGlassEffectView is only available in macOS 26 or newer." Or: glass appears as opaque panel on macOS 26.2+.

**Confidence:** HIGH -- [Apple NSGlassEffectView docs](https://developer.apple.com/documentation/appkit/nsglasseffectview) confirm `@available(macOS 26.0, *)`. Regression documented via FB21375029.

---

### Pitfall 4: Replacing Bitmap-Cached View with Live Rendering Causes CPU Regression

**What goes wrong:** The current HintBarView uses NSHostingView wrapping SwiftUI. SwiftUI only redraws on state changes (key press/release). If the redesign replaces this with live CALayer rendering that recalculates blur, redraws text, or updates tint colors on every mouse move, the hint bar goes from ~0% CPU to continuous work on every mouse event.

**Why it happens:** The current architecture is efficient: `updatePosition()` animates `position.y` via CAAnimation (zero CPU per frame); `pressKey()`/`releaseKey()` trigger SwiftUI diffing (rare, lightweight). Replacing this with per-frame custom rendering is a regression.

**Consequences:**
- CPU during mouse movement increases from <5% to 15-30%
- Battery drain, potential frame drops in edge detection
- CLAUDE.md testing checklist requires "CPU stays low (<5%) during mouse movement"

**Prevention:**
1. Render blur background ONCE when hint bar is created (screenshot is frozen). Assign to `layer.contents` as bitmap.
2. If using `NSVisualEffectView`, it caches internally -- but verify with Instruments.
3. Text content should be rendered once and cached. Only re-render on state changes.
4. Split/merge animation should use CALayer property animations (frame, opacity, path) -- NOT per-frame redraws.
5. Profile before and after with Instruments Core Animation template.

**Detection:** Activity Monitor shows Ruler >5% CPU during mouse movement.

**Confidence:** HIGH -- CLAUDE.md Section 8 ("HintBarView (static, renders ONCE)"), MEMORY.md documents previous CPU issues with SVG rendering.

---

### Pitfall 5: CAShapeLayer Path Morphing Requires Identical Point Counts

**What goes wrong:** Animating `CAShapeLayer.path` from one shape to another (single bar morphing into two bars) produces undefined behavior if the paths have different control point counts. A single rounded rect has ~12-16 control points; two separate rounded rects have ~24-32. These cannot be directly morphed.

**Consequences:**
- Animation looks like a melting blob instead of a clean split
- No runtime error -- just visually broken
- May vary across macOS versions

**Prevention:**
1. Do NOT animate `CAShapeLayer.path` for the split/merge animation. Use two separate `CAShapeLayer` instances (left bar, right bar) that are always present.
2. In "merged" state, they overlap perfectly (same frame, same path). In "split" state, they separate via `frame` animation.
3. Animate `frame` of each layer, not `path`. This is already the pattern used for the pill in CrosshairView.swift (lines 316-341): section backgrounds use `layer.frame` for position and local-origin `path` for shape.
4. If corner radii must change during animation (outer vs inner as bars separate), ensure both path versions have exactly the same number of `moveTo`, `addLine`, and `addCurve` calls.
5. CLAUDE.md Section 3 explicitly warns: "Use `layer.frame` for position + local-origin `path` so Core Animation can interpolate the frame's position."

**Detection:** Split animation shows distortion, warping, or flickering of bar shapes.

**Confidence:** HIGH -- [Apple CAShapeLayer docs](https://developer.apple.com/documentation/quartzcore/cashapelayer): "The result of animating a path is undefined if the two paths have a different number of control points or segments." Confirmed by [calayer.com guide](https://www.calayer.com/core-animation/2017/12/25/cashapelayer-in-depth-part-ii.html).

---

## Moderate Pitfalls

---

### Pitfall 6: Appearance Detection Returns Wrong Value in Overlay Window Context

**What goes wrong:** Using `NSApp.effectiveAppearance` or `NSAppearance.current` to determine light/dark mode for tinting may return the wrong appearance. The window is borderless with no titlebar, so it may not inherit system appearance changes. Additionally, the `appearance` property may be nil, and `effectiveAppearance` may not reflect the user's setting because the window was created before an appearance change.

**Why it matters:** The current HintBarContent.swift uses `@Environment(\.colorScheme)` (lines 29, 67). SwiftUI handles this correctly via NSHostingView. If you replace SwiftUI with manual CALayer rendering, you lose automatic propagation.

**Consequences:**
- Hint bar tint colors wrong (dark on light or vice versa)
- Does not update when user toggles dark mode while overlay is open

**Prevention:**
1. If keeping SwiftUI (NSHostingView), rely on `@Environment(\.colorScheme)` -- it works.
2. If using manual CALayer rendering, detect at creation:
   ```swift
   let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
   ```
3. For mid-session changes, observe via KVO:
   ```swift
   NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
       self?.updateAppearance()
   }
   ```
4. Since overlay is short-lived, static appearance at creation time is usually sufficient.

**Confidence:** MEDIUM -- current SwiftUI hint bar works correctly, suggesting propagation works. Concern is for the case where the view hierarchy changes significantly.

---

### Pitfall 7: Split Animation and Mouse-Move Position Update Race Condition

**What goes wrong:** The hint bar split animation fires after a timeout (e.g., 3 seconds). If the user moves the mouse during the split, `updatePosition(cursorY:screenHeight:)` is called, which may try to slide the hint bar to top/bottom. The slide animation and split animation compete for the same layers' `frame`/`position` properties.

**Why it happens:** The existing `isAnimating` guard (HintBarView.swift line 75) prevents overlapping slide animations. But the split animation is new and does not set `isAnimating`. The slide code runs, sees `isAnimating == false`, and starts a slide mid-split.

**Consequences:**
- Layers teleport to unexpected positions
- Partial split + partial slide = visual mess
- Model values and presentation values diverge

**Prevention:**
1. Extend the animation guard to cover ALL animation types:
   ```swift
   enum AnimationState { case idle, sliding, splitting, merging }
   private var animationState: AnimationState = .idle
   ```
2. Block `updatePosition()` during split/merge: `guard animationState == .idle else { return }`
3. Use `CATransaction.setCompletionBlock` to reset to `.idle` after any animation completes
4. If cursor moves near bottom during split, DEFER the slide until split completes (queue it)

**Detection:** Move cursor to bottom of screen immediately after launching overlay. If hint bar jumps or shows partial split, race condition is present.

**Confidence:** MEDIUM -- the existing `isAnimating` guard (HintBarView.swift line 75) proves this bug class is known; the split animation is a new animation state not covered.

---

### Pitfall 8: CIFilter Blur on Main Thread Blocks Edge Detection

**What goes wrong:** If implementing manual blur using `CIGaussianBlur`, applying the filter on the main thread blocks mouse event processing. A blur on a Retina region (800x60 points = 1600x120 pixels at 2x) takes 5-20ms. During this time, the first mouse move is delayed.

**Consequences:**
- 5-20ms delay on first appearance
- Stacks with CGWindowListCreateImage cold-start penalty (MEMORY.md)
- On older Macs, 50-100ms

**Prevention:**
1. Apply blur during window setup, BEFORE `makeKeyAndOrderFront`. User sees window with blur already applied.
2. Use `CIContext(options: [.useSoftwareRenderer: false])` for GPU rendering.
3. Crop screenshot to ONLY the hint bar region before blurring.
4. Use small blur radius (8-12px) -- larger radii are exponentially more expensive.
5. Pre-render on background queue during capture phase if needed.
6. Alternative: use `NSVisualEffectView` with `.withinWindow`, which delegates blur to the window server (zero main-thread cost).

**Detection:** Instruments Time Profiler shows `CIGaussianBlur` or `CIContext.createCGImage` in the launch hot path.

**Confidence:** MEDIUM -- impact depends on crop region size and hardware. One-time cost is tolerable if kept under 10ms.

---

### Pitfall 9: GlassEffectContainer Spacing Animation May Not Produce Fluid Morphing

**What goes wrong:** If using the macOS 26 Liquid Glass path, the bar split animation relies on `GlassEffectContainer` / `NSGlassEffectContainerView` with animated spacing. However, the liquid morphing effect is documented for views appearing/disappearing (via `glassEffectID` + conditional rendering), not for spacing changes alone. Animating the `spacing` parameter may not trigger the liquid join/separate effect.

**Consequences:**
- Split shows cards moving apart with no glass morphing between them
- Looks like a plain spacing animation, not a liquid glass effect
- The "wow factor" is lost

**Prevention:**
1. Test spacing animation approach first with a minimal prototype
2. If spacing does not produce morphing, use the alternative: conditionally show/hide a "joined" single-card state vs. "split" two-card state with `glassEffectID` tracking
3. This requires two view structures (joined and split) toggled with `withAnimation` -- more code but the documented morphing pattern

**Detection:** Visual inspection. Does the glass between cards create a fluid "liquid pulling apart" effect, or do cards simply move apart with independent backgrounds?

**Confidence:** MEDIUM -- documented morphing uses conditional view insertion/removal, not spacing animation. Spacing is a reasonable hypothesis but unverified.

---

### Pitfall 10: NSHostingView Reentrant Layout Warning During Rapid State Updates

**What goes wrong:** If keeping NSHostingView for hint bar content and triggering `@Published` state changes from mouse event handlers, the warning fires: "NSHostingView is being laid out reentrantly while rendering its SwiftUI content." The view shows stale content for one or more frames.

**Prevention:**
1. Do NOT update SwiftUI state from within `mouseMoved`. Position updates already use CAAnimation, not SwiftUI state.
2. Batch state updates with `DispatchQueue.main.async { }` to defer them out of event handlers.
3. Better: keep SwiftUI content static and use CALayer for all dynamic elements.

**Confidence:** MEDIUM -- [documented issue](https://github.com/onmyway133/notes/issues/551), and the codebase already triggers SwiftUI updates from keyboard handlers.

---

## Minor Pitfalls

---

### Pitfall 11: compositingFilter String Typo Causes Silent Failure

**What goes wrong:** New blend modes for the glass effect (e.g., `"screenBlendMode"`, `"multiplyBlendMode"`) silently fail if the string has a typo. No error, no warning.

**Prevention:** Define as constants:
```swift
enum BlendMode {
    static let difference = "differenceBlendMode"
    static let screen = "screenBlendMode"
    static let multiply = "multiplyBlendMode"
}
```

**Confidence:** HIGH -- documented in MEMORY.md.

---

### Pitfall 12: CATransaction Completion Block Fires After ALL Animations

**What goes wrong:** If split and slide animations share a `CATransaction`, the completion block fires after BOTH complete. State transitions gated on completion are delayed.

**Prevention:**
1. Use separate `CATransaction.begin()/commit()` blocks for independent animations.
2. Use `CAAnimationDelegate.animationDidStop(_:finished:)` for per-animation completion.
3. Follow existing codebase pattern: CrosshairView uses separate transactions for lines/feet vs. pill.

**Confidence:** HIGH -- standard Core Animation behavior.

---

### Pitfall 13: Coordinate System Bug When Cropping Blur Region

**What goes wrong:** Cropping the screenshot for the hint bar blur region: hint bar position is AppKit coords (origin bottom-left), `CGImage.cropping(to:)` expects CG coords (origin top-left). Wrong vertical position if not converted.

**Prevention:**
```swift
let cgY = screenHeight - (hintBarFrame.origin.y + hintBarFrame.height)
let cropRect = CGRect(x: hintBarFrame.origin.x * scale, y: cgY * scale,
                       width: hintBarFrame.width * scale, height: hintBarFrame.height * scale)
```
Account for Retina scale factor. Use CoordinateConverter.swift.

**Confidence:** HIGH -- CLAUDE.md Section 4 documents coordinate system differences.

---

### Pitfall 14: Solid Background Interfering with Glass Material

**What goes wrong:** The current `MainHintCard` and `ExtraHintCard` have `.background(RoundedRectangle(...).fill(...))` modifiers rendering solid backgrounds. If `.glassEffect()` is added ON TOP, the glass has a solid color behind it instead of the screenshot, defeating translucency.

**Prevention:**
1. When using glass/blur, remove `.background()` and `.overlay()` (border) from the cards.
2. Use conditional modifiers: either glass OR solid background, never both.
3. Remove `.shadow()` when using glass -- glass provides its own depth cues.

**Confidence:** HIGH -- straightforward view modifier conflict.

---

### Pitfall 15: Multi-Monitor Animation State Desynchronization

**What goes wrong:** The hint bar currently exists only on the cursor screen (Ruler.swift line 76). If a split animation is mid-flight when the user switches screens, the animation continues on the old window while the new window has no hint bar. This is fine with the current design. But if the design changes to show hint bars on all screens, animation state must synchronize.

**Prevention:**
1. Keep hint bar on cursor screen only (current approach). No sync needed.
2. If hint bar follows active screen: store animation state in shared model, cancel in-progress animations on `deactivate()`, restore to current logical state on `activate()`.

**Confidence:** LOW -- only matters if design changes to span multiple monitors.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Glass/blur background | Opaque window blocks blur (Pitfall 1), layer-hosting conflict (Pitfall 2) | Use `.withinWindow` with proper view ordering, OR one-time CIFilter blur of cropped screenshot |
| Deployment target | NSGlassEffectView requires macOS 26 (Pitfall 3) | Do NOT use NSGlassEffectView as primary. Implement blur manually. Add glass as macOS 26+ enhancement. |
| Bitmap cache to live layers | CPU regression (Pitfall 4), reentrant layout (Pitfall 10) | Render blur once, cache as bitmap. Keep text static. Use CALayer animations, not per-frame redraws. |
| Split/merge animation | Path point mismatch (Pitfall 5), race with slide (Pitfall 7) | Two separate layers with frame animation, NOT single path morph. Extend isAnimating to all animation types. |
| Appearance-aware tinting | Wrong appearance in overlay (Pitfall 6) | Use NSApp.effectiveAppearance at creation. Observe via KVO if mid-session updates needed. |
| CIFilter manual blur | Main thread blocking (Pitfall 8) | Crop to hint bar region only. Apply during setup before window appears. |
| macOS 26 glass morphing | Spacing animation may not morph (Pitfall 9) | Prototype early. Fall back to conditional view toggle with glassEffectID. |
| Animation completion | Transaction scoping (Pitfall 12), coordinate bugs (Pitfall 13) | Separate CATransaction blocks. Use CoordinateConverter for crop rects. |
| SwiftUI glass backgrounds | Solid fill under glass (Pitfall 14) | Remove .background/.shadow when glass/blur is active. |

---

## Recommended Architecture for Blur + Split

Based on the pitfalls above, the safest architecture is:

### Primary Path (macOS 13+, no API availability issues)

1. **Blur background:** One-time `CIGaussianBlur` of the cropped screenshot region under the hint bar, assigned to a `CALayer.contents` bitmap. Zero per-frame cost. No NSVisualEffectView layer-hosting conflicts. Alternatively, `NSVisualEffectView` with `.withinWindow` as a sibling view below the content layers (NOT inside the layer-hosting tree).

2. **Split animation:** Two `CAShapeLayer` instances (main card bg, extra card bg) that are ALWAYS present. In "merged" state, they overlap perfectly with combined dimensions. In "split" state, they separate via `frame` animation. Use the existing `sectionPath()` squircle approach from CrosshairView.swift.

3. **Content rendering:** Keep NSHostingView for text content (key caps, labels) -- it handles appearance, text rendering, and layout correctly. Position via `frame` (no per-frame updates). OR render text into bitmap and use `CATextLayer`, matching the CrosshairView pattern.

4. **Appearance:** Detect once at creation via `NSApp.effectiveAppearance`. Use for tint colors on the blur layer.

### Enhancement Path (macOS 26+, optional)

5. **Native glass:** Behind `if #available(macOS 26.0, *)`, replace the CIFilter blur with `.glassEffect()` on the SwiftUI content views. Test in the exact window configuration first (Pitfall 3). If the 26.2 regression affects this window type, skip until Apple fixes it.

6. **Glass morphing:** Use `GlassEffectContainer` + `glassEffectID` with conditional view toggle (not spacing animation) for the split. Test that liquid morphing actually triggers.

This architecture avoids all critical pitfalls while maintaining the <5% CPU target and working on macOS 13+.

---

## Sources

- [Apple NSVisualEffectView documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [Apple NSVisualEffectView.BlendingMode documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode)
- [Reverse Engineering NSVisualEffectView -- Oskar Groth](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview)
- [CAPluginLayer & CABackdropLayer -- Aditya Vaidyam](https://medium.com/@avaidyam/capluginlayer-cabackdroplayer-f56e85d9dc2c)
- [NSVisualEffectView in Layer-Hosting Views](https://databasefaq.com/index.php/answer/164756/osx-calayer-nsview-nswindow-nsvisualeffectview-how-to-use-nsvisualeffectview-in-a-layer-host-nsview)
- [Apple NSGlassEffectView documentation (macOS 26+)](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [Apple NSGlassEffectContainerView documentation](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)
- [Liquid Glass Reference -- conorluddy](https://github.com/conorluddy/LiquidGlassReference)
- [Apple CAShapeLayer documentation](https://developer.apple.com/documentation/quartzcore/cashapelayer)
- [CAShapeLayer in Depth, Part II -- calayer.com](https://www.calayer.com/core-animation/2017/12/25/cashapelayer-in-depth-part-ii.html)
- [CATransaction in Depth -- calayer.com](https://www.calayer.com/core-animation/2016/05/17/catransaction-in-depth.html)
- [Apple Core Animation: Advanced Animation Tricks](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/AdvancedAnimationTricks/AdvancedAnimationTricks.html)
- [objc.io: Animations Explained](https://www.objc.io/issues/12-animations/animations-explained/)
- [Apple NSAppearance documentation](https://developer.apple.com/documentation/appkit/nsappearancecustomization/choosing_a_specific_appearance_for_your_macos_app)
- [Observing NSAppearance changes -- Derrick Ho](https://derrickho328.medium.com/observing-nsappearance-changes-in-macos-29fc4f44b0c4)
- [NSHostingView reentrant layout issue](https://github.com/onmyway133/notes/issues/551)
- [Apple CATransaction setCompletionBlock docs](https://developer.apple.com/documentation/quartzcore/catransaction/1448281-setcompletionblock)
- [Build an AppKit app with the new design -- WWDC25](https://developer.apple.com/videos/play/wwdc2025/310/)
- [GlassEffectTest regression demo -- FB21375029](https://github.com/siracusa/GlassEffectTest)
- [Adopting Liquid Glass -- Apple Developer Documentation](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
