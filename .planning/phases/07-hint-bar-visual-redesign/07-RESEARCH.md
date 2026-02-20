# Phase 7: Hint Bar Visual Redesign - Research

**Researched:** 2026-02-14
**Domain:** macOS AppKit -- NSVisualEffectView glass background, SwiftUI keycap redesign, ESC tint, two-section collapsed layout
**Confidence:** HIGH

## Summary

Phase 7 redesigns the hint bar's visual appearance: new keycap sizes/layout, a reddish ESC tint, a two-section collapsed layout (arrows+shift left, ESC right), and glass backgrounds using NSVisualEffectView with vibrancy fallback. Phase 8 (next) will add the launch-to-collapse animation. Phase 7 must build both the expanded and collapsed visual states but does NOT need to animate between them yet.

The existing codebase has already moved from bitmap-cached rendering to SwiftUI-hosted content via `NSHostingView<HintBarContent>`. This is the correct approach to maintain. The redesign requires: (1) wrapping SwiftUI content in `NSVisualEffectView` for glass backgrounds, (2) restructuring content into expanded (full text + keycaps) and collapsed (keycaps only, two bars) layouts, (3) resizing keycaps to new dimensions, and (4) adding ESC key reddish tinting.

The highest-risk item is whether `NSVisualEffectView` with `.withinWindow` blending correctly blurs the frozen screenshot in the Ruler's opaque borderless window. The existing research (`.planning/research/PITFALLS.md` Pitfall 1) identifies this risk and proposes a fallback (semi-transparent solid background). This phase should validate the glass approach first, then build everything else.

**Primary recommendation:** Build the glass background validation first (NSVisualEffectView with `.withinWindow` on the existing expanded bar), then restructure the layout into expanded + collapsed states with new keycap sizes, then add ESC tint. Defer all animation to Phase 8.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| NSVisualEffectView | macOS 10.10+ | Glass/vibrancy background for hint bar panels | Stable since 2014. `.withinWindow` blending samples window content. `.hudWindow` material designed for floating overlays. Available at macOS 13 deployment target. |
| SwiftUI (NSHostingView) | macOS 13+ | Content rendering -- keycaps, text, layout | Already in use. Declarative, appearance-reactive via `@Environment(\.colorScheme)`. |
| Core Animation | macOS 10.5+ | Layer composition, future animation hooks | Already used throughout codebase. Phase 7 sets up layers; Phase 8 animates them. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `@Environment(\.colorScheme)` | SwiftUI 1.0+ | Dark/light mode in SwiftUI content | Already used in HintBarContent.swift. Continues for all keycap/text color decisions. |
| NSAppearance | macOS 10.14+ | ESC tint layer appearance reactivity | `viewDidChangeEffectiveAppearance()` for the ESC tint overlay on the NSVisualEffectView. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSVisualEffectView (.withinWindow) | SwiftUI .glassEffect() | macOS 26+ only. Known regression (FB21375029) in floating windows. Cannot animate frame independently for Phase 8 split. |
| NSVisualEffectView (.withinWindow) | NSGlassEffectView | macOS 26+ only. Undocumented behavior in opaque borderless windows. |
| NSVisualEffectView (.withinWindow) | CIGaussianBlur (one-time) | Fallback if `.withinWindow` fails to sample screenshot. One-time crop + blur of screenshot region. 5-20ms cost at setup. |
| NSVisualEffectView (.withinWindow) | .behindWindow blending | Samples actual desktop, NOT the frozen screenshot. Breaks frozen-frame illusion. |
| SwiftUI via NSHostingView | Pure CATextLayer + NSBezierPath | Would lose declarative layout, appearance reactivity, animation support for keycap press. More code for same result. |

**Installation:**
```
No new dependencies. All APIs from system frameworks: AppKit, SwiftUI, QuartzCore, Foundation.
Package.swift unchanged. platforms: [.macOS(.v13)] correct.
```

## Architecture Patterns

### Current File Structure (Rendering/)

```
swift/Ruler/Sources/Rendering/
  HintBarView.swift       # NSView wrapper -- positioning, slide animation
  HintBarContent.swift    # SwiftUI content -- MainHintCard, ExtraHintCard, KeyCap
  CrosshairView.swift     # CAShapeLayer crosshair (reference pattern)
  SelectionOverlay.swift  # CALayer selection rectangle (reference pattern)
  SelectionManager.swift  # Selection lifecycle manager
```

### Target File Structure (Phase 7)

```
swift/Ruler/Sources/Rendering/
  HintBarView.swift       # NSView wrapper -- glass panels, positioning, state (expanded/collapsed)
  HintBarContent.swift    # SwiftUI content -- ExpandedContent, CollapsedLeftContent, CollapsedRightContent, KeyCap
  (no new files needed)
```

### Pattern 1: NSVisualEffectView Glass Background

**What:** Wrap SwiftUI content in NSVisualEffectView for frosted glass appearance.
**When to use:** For each hint bar panel (expanded bar, left collapsed bar, right collapsed bar).

```swift
// Source: Apple NSVisualEffectView docs + codebase HintBarView pattern
private func makeGlassPanel() -> NSVisualEffectView {
    let vev = NSVisualEffectView()
    vev.blendingMode = .withinWindow  // blur window content (screenshot)
    vev.material = .hudWindow          // dark translucent, adapts to appearance
    vev.state = .active                // always active, don't follow window focus
    vev.wantsLayer = true
    vev.layer?.cornerRadius = 18
    vev.layer?.cornerCurve = .continuous  // squircle corners
    vev.layer?.masksToBounds = true
    return vev
}
```

**Key constraints:**
- `.withinWindow` blurs sibling views within the same window -- the screenshot bgView must be BELOW in the view hierarchy
- `state = .active` prevents deactivation when window loses focus
- `cornerCurve = .continuous` matches the existing SwiftUI `RoundedRectangle(style: .continuous)`

### Pattern 2: Hybrid NSVisualEffectView + NSHostingView

**What:** Glass background as AppKit view, content as SwiftUI view hosted inside.
**When to use:** For all hint bar panels. NSVisualEffectView provides the blur; NSHostingView inside renders keycaps + text.

```swift
// Source: codebase HintBarView.swift pattern (already uses NSHostingView)
let glassPanel = makeGlassPanel()
let content = NSHostingView(rootView: ExpandedHintContent(state: state))
content.frame = glassPanel.bounds
content.autoresizingMask = [.width, .height]
glassPanel.addSubview(content)
```

**Why not SwiftUI background modifiers?** The current HintBarContent uses `.background(RoundedRectangle(...).fill(...))` for solid backgrounds. These MUST be removed when the glass panel provides the background -- otherwise the solid fill sits under the glass and defeats translucency (Pitfall 14 from research).

### Pattern 3: Two-Section Collapsed Layout

**What:** Collapsed state has two independent bars: left (arrow cluster + shift) and right (ESC keycap with reddish tint).
**When to use:** Phase 7 builds these as hidden views; Phase 8 will animate them into view.

```
[COLLAPSED layout]:
  Screen edge
  |  16px  |  [leftBar: arrows + shift]  24px gap  [rightBar: ESC]  |  16px  |
                           centered on screen width

  leftBar: NSVisualEffectView (.hudWindow, .withinWindow)
    +-- NSHostingView<CollapsedLeftContent>  (arrow cluster + shift keycap)

  rightBar: NSVisualEffectView (.hudWindow, .withinWindow)
    +-- NSHostingView<CollapsedRightContent> (ESC keycap)
    +-- escTintLayer (CALayer, semi-transparent red overlay)
```

### Pattern 4: ESC Tint Overlay

**What:** A semi-transparent reddish overlay on the right collapsed bar to visually signal "exit."
**When to use:** On the collapsed right bar (ESC keycap).

```swift
// Source: codebase research/ARCHITECTURE.md Section 5
private let escTintLayer = CALayer()

private func setupEscTint() {
    escTintLayer.cornerRadius = 14  // match collapsed bar radius
    escTintLayer.cornerCurve = .continuous
    rightBar.layer?.addSublayer(escTintLayer)
    updateEscTint()
}

private func updateEscTint() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    escTintLayer.backgroundColor = isDark
        ? CGColor(srgbRed: 1.0, green: 0.3, blue: 0.3, alpha: 0.08)
        : CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 0.06)
    escTintLayer.frame = rightBar.bounds
}

override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateEscTint()
}
```

### Anti-Patterns to Avoid

- **behindWindow blending:** Samples actual desktop, not the frozen screenshot. The window is opaque (`isOpaque = true`) with a screenshot background. `.behindWindow` would show different content than what the user sees.
- **Solid SwiftUI backgrounds under glass:** Current `.background(RoundedRectangle(...).fill(...))` must be removed from content views when glass panel provides the background. Solid fill defeats translucency.
- **Layer-hosting in same subtree as NSVisualEffectView:** NSVisualEffectView creates internal `CABackdropLayer`. Adding it as a child/parent of a layer-hosting view (one that directly manipulates CALayer sublayers) breaks the blur. Keep HintBarView and CrosshairView as separate peer views in the container.
- **NSGlassEffectView/glassEffect() without availability check:** Requires macOS 26+. Crashes on macOS 13-25.
- **Animating NSVisualEffectView frame for split in this phase:** Phase 8 handles animation. Phase 7 should build both states and toggle visibility, not animate transitions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Glass/frosted background | CIGaussianBlur + CALayer.contents | NSVisualEffectView (.withinWindow, .hudWindow) | GPU-accelerated via WindowServer's CABackdropLayer. Zero per-frame cost. Automatic appearance adaptation. |
| Blur in opaque window (if withinWindow fails) | Manual CIFilter pipeline | CIGaussianBlur one-time crop + blur of screenshot region | One-time 5-20ms cost at setup. Assign result to CALayer.contents as bitmap. |
| Dark/light mode detection | Manual KVO on NSApp.effectiveAppearance | @Environment(\.colorScheme) in SwiftUI + viewDidChangeEffectiveAppearance() in AppKit | SwiftUI handles automatically for content. AppKit callback handles the ESC tint layer. |
| Squircle corner shapes | Manual CGPath with cubic bezier curves | CALayer.cornerRadius + cornerCurve = .continuous | System-level continuous (squircle) corners. Matches SwiftUI `.continuous` style. |

**Key insight:** NSVisualEffectView is the right abstraction for glass backgrounds in this context. It delegates blur compositing to WindowServer, which is hardware-accelerated and has zero ongoing CPU cost once layers are flattened (~1s after last change). The only uncertainty is `.withinWindow` sampling behavior in an opaque borderless window -- prototype validates this.

## Common Pitfalls

### Pitfall 1: withinWindow Blur Shows Black Instead of Screenshot
**What goes wrong:** NSVisualEffectView with `.withinWindow` blending may not correctly sample the frozen screenshot when the background is a `CALayer.contents` CGImage in an opaque borderless window.
**Why it happens:** `CABackdropLayer` samples rendered content from sibling views. A `layer.contents` CGImage on a plain NSView may not be "rendered" in the way `CABackdropLayer` expects. The screenshot is set directly on `bgView.layer?.contents` (RulerWindow.swift line 98), bypassing AppKit's normal drawing pipeline.
**How to avoid:** Prototype FIRST. If `.withinWindow` shows black:
  - Fallback A: Use `NSImageView` for the background instead of `layer.contents` (forces AppKit rendering pipeline).
  - Fallback B: One-time `CIGaussianBlur` on cropped screenshot region, assigned as `layer.contents` on a backing layer.
  - Fallback C: Semi-transparent solid background (visually inferior but functional).
**Warning signs:** Glass background appears as solid gray/black with no visible blurred screenshot content underneath.
**Confidence:** MEDIUM -- `.withinWindow` is documented to blur "contents behind the view in the current window." Whether `layer.contents` CGImage qualifies as "contents" for sampling purposes is undocumented.

### Pitfall 2: Solid SwiftUI Backgrounds Defeating Glass Transparency
**What goes wrong:** Current `MainHintCard` and `ExtraHintCard` have `.background(RoundedRectangle(...).fill(colorScheme == .dark ? Color(...) : .white))`. If glass panel wraps these views, the solid fill sits between the glass blur and the content, making the glass invisible.
**Why it happens:** SwiftUI view modifiers render in order. The `.background()` modifier paints an opaque rectangle before the glass panel's blur can show through.
**How to avoid:** When wrapping in glass panel, remove all `.background()` and `.shadow()` modifiers from the SwiftUI content. The glass panel provides the background and visual depth.
**Warning signs:** Hint bar looks exactly the same as before (solid background, no blur visible).
**Confidence:** HIGH -- straightforward SwiftUI modifier stacking.

### Pitfall 3: Layer-Hosting View Conflict with NSVisualEffectView
**What goes wrong:** NSVisualEffectView's internal `CABackdropLayer` malfunctions when placed in the same view subtree as a layer-hosting view (one that directly adds/removes CALayer sublayers).
**Why it happens:** Layer-hosting views take full control of the layer tree. NSVisualEffectView expects to manage its own internal layers through AppKit's layer-backed view system. The two approaches conflict.
**How to avoid:** HintBarView (which will contain NSVisualEffectViews) and CrosshairView (which uses CAShapeLayers directly) are already separate peer views in the container. Maintain this separation. Do NOT add CALayer sublayers directly to HintBarView's layer or any NSVisualEffectView's layer (except the escTintLayer, which goes on the NSVisualEffectView's layer AFTER the blur is established).
**Warning signs:** Blur works initially but disappears after ~1 second of window idleness (WindowServer layer flattening destroys the backdrop).
**Confidence:** HIGH -- documented in multiple sources and the existing research.

### Pitfall 4: New Keycap Sizes Breaking Layout
**What goes wrong:** Changing arrow keycaps from 20x16 to 26x11 changes the aspect ratio significantly (wider, shorter). The ArrowCluster VStack layout with fixed spacing may not look correct. The shift keycap going from 32x20 to 40x25 is a large jump that may throw off the HStack horizontal alignment.
**Why it happens:** The existing layout was designed for specific proportions. Changing dimensions without adjusting spacing, fonts, and padding will produce misalignment.
**How to avoid:** Adjust ArrowCluster spacing (`hGap`, `vGap`) to match new proportions. Test visually at both dark and light appearances. Ensure the up arrow + bottom row alignment still looks like a physical keyboard arrow cluster. Ensure font sizes for arrow symbols scale appropriately to the new 11pt height (may need smaller font size).
**Warning signs:** Arrow cluster looks squished, symbols overflow keycap bounds, shift keycap dominates the layout.
**Confidence:** HIGH -- dimensional changes always require layout tuning.

### Pitfall 5: NSHostingView Size Calculation with Glass Panel
**What goes wrong:** `NSHostingView.fittingSize` returns the intrinsic content size of the SwiftUI view tree. When the SwiftUI content no longer has its own `.background()` and `.padding()` modifiers (removed for glass), `fittingSize` may return different dimensions than expected.
**How to avoid:** After removing solid backgrounds from SwiftUI content, keep the `.padding()` modifiers on the content (they control spacing between keycaps and the glass edge). Verify `fittingSize` by logging dimensions during development. Set glass panel frame from hosting view's `fittingSize`.
**Warning signs:** Glass panel is too small (clips content) or too large (excess empty space).
**Confidence:** MEDIUM -- depends on how SwiftUI computes intrinsic size without background modifiers.

## Code Examples

Verified patterns from the existing codebase and official documentation:

### Current HintBarView Integration (to preserve)
```swift
// Source: RulerWindow.swift setupViews()
let hv = HintBarView(frame: .zero)
self.hintBarView = hv
if !hideHintBar {
    hv.configure(screenWidth: size.width, screenHeight: size.height)
    containerView.addSubview(hv)
}
```

### Current SwiftUI Content Hosting (to adapt)
```swift
// Source: HintBarView.swift setupHostingView()
private func setupHostingView() {
    let content = HintBarContent(state: state)
    let hosting = NSHostingView(rootView: content)
    addSubview(hosting)
    self.hostingView = hosting
}
```

### NSVisualEffectView Configuration (new)
```swift
// Source: Apple NSVisualEffectView docs + research/ARCHITECTURE.md Section 8
let glass = NSVisualEffectView()
glass.blendingMode = .withinWindow
glass.material = .hudWindow
glass.state = .active
glass.wantsLayer = true
glass.layer?.cornerRadius = 18
glass.layer?.cornerCurve = .continuous
glass.layer?.masksToBounds = true
```

### New Keycap Dimensions (from PROJECT.md requirements)
```swift
// Source: PROJECT.md active requirements
// Arrow keys: 26x11 (was 20x16)
// Shift: 40x25 (was 32x20)
// ESC: 32x25 (was 32x20)

// In ArrowCluster:
private let capW: CGFloat = 26  // was 20
private let capH: CGFloat = 11  // was 16

// In MainHintCard shift keycap:
KeyCap(.shift, symbol: "\u{21E7}", width: 40, height: 25, ...)  // was 32x20

// In ExtraHintCard / CollapsedRightContent ESC keycap:
KeyCap(.esc, symbol: "esc", width: 32, height: 25, ...)  // was 32x20
```

### Expanded Content (glass version -- no solid background)
```swift
// Source: adapted from current HintBarContent.swift MainHintCard
struct ExpandedHintContent: View {
    @ObservedObject var state: HintBarState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: -2) {
            // Main row: arrows + shift
            HStack(spacing: 6) {
                mainText("Use")
                ArrowCluster(state: state)
                mainText("to skip an edge.")
                mainText("Plus")
                KeyCap(.shift, symbol: "\u{21E7}", width: 40, height: 25, ...)
                mainText("to invert.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // NO .background() -- glass panel provides this

            // Extra row: ESC
            HStack(spacing: 4) {
                extraText("Press")
                KeyCap(.esc, symbol: "esc", width: 32, height: 25, ...)
                extraText("to exit.")
            }
            .padding(8)
            // NO .background() -- glass panel provides this
        }
    }
}
```

### Collapsed Left Content (keycaps only)
```swift
struct CollapsedLeftContent: View {
    @ObservedObject var state: HintBarState

    var body: some View {
        HStack(spacing: 6) {
            ArrowCluster(state: state)
            KeyCap(.shift, symbol: "\u{21E7}", width: 40, height: 25, ...)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // NO .background() -- glass panel provides this
    }
}
```

### Collapsed Right Content (ESC keycap)
```swift
struct CollapsedRightContent: View {
    @ObservedObject var state: HintBarState

    var body: some View {
        KeyCap(.esc, symbol: "esc", width: 32, height: 25, ...)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        // NO .background() -- glass panel provides this
        // Reddish tint applied at the AppKit layer (escTintLayer on the NSVisualEffectView)
    }
}
```

### ESC Keycap Tint (in SwiftUI for keycap border)
```swift
// The ESC keycap itself gets a subtle reddish border in collapsed state
// while the glass panel gets a tint overlay at the AppKit layer

// Option A: SwiftUI overlay on keycap
KeyCap(.esc, ...)
    .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(escTintColor, lineWidth: 1.5)
    )

// Where:
private var escTintColor: Color {
    colorScheme == .dark
        ? Color(nsColor: NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0))
        : Color(nsColor: NSColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0))
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSBezierPath bitmap-cached hint bar (CLAUDE.md original) | SwiftUI NSHostingView hint bar (current codebase) | Before v1.0 | Live SwiftUI rendering with automatic appearance adaptation. Better than bitmap for interactive keycaps. |
| Solid opaque backgrounds | NSVisualEffectView glass backgrounds | Phase 7 (this phase) | Frosted glass matching modern macOS design. `.hudWindow` material adapts to dark/light automatically. |
| Single hint bar | Two-section collapsed layout (left + right) | Phase 7 (this phase) | Compact keycap-only bars for experienced users. Foundation for Phase 8 split animation. |

**Deprecated/outdated:**
- `.light` / `.dark` / `.mediumLight` / `.ultraDark` NSVisualEffectView materials: Deprecated since macOS 10.14. Use semantic materials like `.hudWindow` instead.
- NSGlassEffectView: macOS 26+ only, known regression in floating windows (FB21375029). Do not use as primary path.

## Open Questions

1. **Does `.withinWindow` blur sample `layer.contents` CGImage?**
   - What we know: `.withinWindow` blurs "contents behind the view in the current window." The screenshot is set via `bgView.layer?.contents = cgImage` (RulerWindow.swift line 98).
   - What's unclear: Whether `CABackdropLayer` considers `layer.contents` as "rendered content" for sampling. Apple docs do not specify. No authoritative source confirms or denies this specific case.
   - Recommendation: Prototype first. If sampling fails, try Fallback A (NSImageView instead of layer.contents), then Fallback B (one-time CIGaussianBlur), then Fallback C (semi-transparent solid).

2. **Optimal font size for arrow symbols in 11pt-tall keycaps**
   - What we know: Current arrow keycaps are 16pt tall with 9pt font. New keycaps are 11pt tall -- 31% shorter.
   - What's unclear: Whether scaling font proportionally (9 * 11/16 = ~6pt) is readable, or whether a larger relative font is needed.
   - Recommendation: Start with 7pt font and tune visually. Unicode arrow symbols render at different sizes than their nominal font size.

3. **Phase 7/8 boundary: where does state machine logic live?**
   - What we know: Phase 7 builds visual states (expanded + collapsed). Phase 8 adds animation between them.
   - What's unclear: Should Phase 7 add the `BarState` enum and visibility toggling (hidden/shown) for the collapsed bars, or should Phase 8 own all state transitions?
   - Recommendation: Phase 7 should add the `BarState` enum and a simple `setBarState(_ state: BarState)` method that toggles visibility (no animation). Phase 8 replaces the visibility toggle with animated transitions. This gives Phase 8 a clean API to work with.

## Sources

### Primary (HIGH confidence)
- [NSVisualEffectView - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview) -- glass background API, blending modes, materials
- [NSVisualEffectView.BlendingMode.withinWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/withinwindow) -- blurs window content, not desktop
- [NSVisualEffectView.Material.hudWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material/hudwindow) -- HUD overlay material
- [NSVisualEffectView.Material](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material) -- all available materials, deprecation of .light/.dark
- Codebase analysis: HintBarView.swift, HintBarContent.swift, RulerWindow.swift, CrosshairView.swift

### Secondary (MEDIUM confidence)
- [Reverse Engineering NSVisualEffectView - Oskar Groth](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview) -- CABackdropLayer internals, layer flattening behavior
- [CABackdropLayer & CAPluginLayer - Aditya Vaidyam](https://medium.com/@avaidyam/capluginlayer-cabackdroplayer-f56e85d9dc2c) -- private API sampling behavior
- [NSVisualEffectView in Layer-Hosting Views](https://databasefaq.com/index.php/answer/164756/osx-calayer-nsview-nswindow-nsvisualeffectview-how-to-use-nsvisualeffectview-in-a-layer-host-nsview) -- layer-hosting incompatibility
- [NSWindow Styles showcase](https://github.com/lukakerr/NSWindowStyles) -- borderless window + visual effect configurations
- [Dark Side of the Mac: Appearance & Materials](https://mackuba.eu/2018/07/04/dark-side-mac-1/) -- hudWindow material behavior in dark/light mode
- Existing research: `.planning/research/ARCHITECTURE.md`, `FEATURES.md`, `PITFALLS.md`, `STACK.md`, `SUMMARY.md`

### Tertiary (LOW confidence)
- `.withinWindow` sampling of `layer.contents` CGImage -- no authoritative source found; must prototype
- New keycap font sizing at 11pt height -- visual tuning needed; no formula

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- NSVisualEffectView, SwiftUI NSHostingView, Core Animation all stable, available at macOS 13+. No new dependencies.
- Architecture: HIGH -- hybrid NSVisualEffectView + NSHostingView is a documented pattern. Existing codebase already uses this hybrid approach.
- Pitfalls: MEDIUM -- the `.withinWindow` sampling question in an opaque borderless window is the primary unknown. All other pitfalls (layout, appearance, layer conflicts) are well-documented.

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (stable domain, 30-day window)
