# Technology Stack: Hint Bar Redesign

**Project:** Design Ruler -- hint bar redesign with glass background, split animation, multi-state
**Researched:** 2026-02-13
**Scope:** NSVisualEffectView glass background, bar split animation via frame animations, state machine, appearance-aware ESC tint

---

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| NSVisualEffectView | macOS 10.10+ | Glass/vibrancy background for hint bar | Already available at macOS 13 target. `.withinWindow` blending blurs the frozen screenshot behind the bar. No new SDK requirement. |
| SwiftUI (via NSHostingView) | macOS 13+ | Content rendering (keycaps, text, layout) | Already in use for HintBarContent. Keep for declarative UI; add glass backgrounds at the AppKit layer around it. |
| Core Animation (CAKeyframeAnimation, CATransaction) | macOS 10.5+ | Split/merge animation, position swap animation | Already used for the existing slide animation. Frame-based animations for splitting one bar into two. |
| NSAppearance | macOS 10.14+ | Appearance-reactive ESC tint | `viewDidChangeEffectiveAppearance()` callback + `effectiveAppearance.bestMatch()` for the tint overlay layer. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `@Environment(\.colorScheme)` | SwiftUI 1.0+ | Dark/light mode in SwiftUI content | Already used in HintBarContent.swift for keycap colors. Continues unchanged. |
| Timer (Foundation) | macOS 10.0+ | Idle timer for auto-collapse | 3s inactivity timer to trigger expanded -> collapsed transition. |
| NSAnimationContext | macOS 10.3+ | Coordinated AppKit view animations | Alternative to raw CATransaction for fade + position animations during split/merge. |

---

## Technology Decisions

### Decision 1: NSVisualEffectView (withinWindow) -- not SwiftUI .glassEffect()

**Chosen:** `NSVisualEffectView` with `.withinWindow` blending and `.hudWindow` material

**Why not SwiftUI `.glassEffect()`:**

| Criterion | NSVisualEffectView | SwiftUI .glassEffect() |
|-----------|-------------------|----------------------|
| Availability | macOS 10.10+ (well within 13+ target) | macOS 26.0+ only |
| Backward compat | No conditional compilation needed | Requires `#available(macOS 26, *)` + fallback |
| Known regressions | Stable, mature API | FB21375029: broken in floating/non-standard windows on 26.2+ |
| Split animation | Glass bg is an NSView -- animate its frame directly | Glass is a SwiftUI modifier -- cannot animate independently of content |
| Overlay window compat | `.withinWindow` blending documented for custom windows | Undocumented behavior in opaque borderless windows |

**The split animation is the deciding factor.** The bar splits into two independent pieces that move to different positions. Each piece needs its own glass background. With NSVisualEffectView, each piece IS an NSView with frame-based positioning -- Core Animation can animate them independently. With SwiftUI `.glassEffect()`, the glass is tied to the SwiftUI view tree, and frame positioning must go through SwiftUI layout, which fights against explicit CAKeyframeAnimation.

**Future enhancement:** When macOS 26 is the minimum deployment target (years away), consider migrating to `NSGlassEffectView` for true Liquid Glass refraction.

### Decision 2: Hybrid SwiftUI + AppKit Architecture

**Chosen:** AppKit NSViews for glass backgrounds and positioning; SwiftUI (NSHostingView) for content rendering inside the glass.

**Rationale:**
- Glass backgrounds = NSVisualEffectView (AppKit)
- Keycaps, text, layout = SwiftUI (already built, declarative, appearance-reactive)
- Position animations = Core Animation on NSView.layer (existing pattern)
- State machine = Swift enum in HintBarView (AppKit NSView)

This is the same hybrid pattern already used: `HintBarView` (NSView) hosts `NSHostingView<HintBarContent>` (SwiftUI). The new design adds NSVisualEffectView wrappers around the hosting views.

### Decision 3: Frame-Based Split Animation -- not SwiftUI Animation

**Chosen:** `NSAnimationContext` / `CATransaction` for split/merge animation with explicit frame positioning.

**Why not SwiftUI animation:**
- The split requires two NSVisualEffectViews moving to different positions simultaneously
- SwiftUI `withAnimation` cannot drive NSView frame changes
- The existing slide animation (bottom <-> top) uses CAKeyframeAnimation and must continue working
- Mixing SwiftUI animation (for content) with Core Animation (for glass bg position) creates timing mismatches

**Why NSAnimationContext for split, CAKeyframeAnimation for slide:**
- Split is a standard ease-in/ease-out transition (fade + position) -- `NSAnimationContext` is simpler
- Slide requires teleport behavior (exit bottom, enter top) which needs keyframe values -- `CAKeyframeAnimation` is necessary

### Decision 4: NSVisualEffectView.Material -- .hudWindow

**Chosen:** `.hudWindow` material

**Why:**
- Designed for heads-up display elements floating over arbitrary content
- Provides a dark translucent frosted appearance that works on both light and dark screenshots
- Automatically adapts to system appearance (dark/light mode)
- Alternative `.popover` is too opaque; `.sidebar` has wrong semantic meaning

### Decision 5: withinWindow Blending -- not behindWindow

**Chosen:** `.withinWindow` blending mode

**Why:**
- The overlay window is opaque with a frozen screenshot as background
- `.behindWindow` would sample the actual desktop (which may have changed), breaking the frozen-frame illusion
- `.withinWindow` samples sibling views within the same window -- the screenshot bgView
- The blur will show the screenshot content, which is the correct visual

**Risk:** Needs prototype verification. If `.withinWindow` does not correctly sample the bgView's `layer.contents` (CGImage), the blur may show black. See PITFALLS.md for mitigation.

---

## API Availability Summary

| API | Min macOS | Our Target | Conditional? | Purpose |
|-----|-----------|------------|-------------|---------|
| `NSVisualEffectView` | 10.10 | 13.0 | No | Glass background |
| `.withinWindow` blending | 10.10 | 13.0 | No | Blur frozen screenshot |
| `.hudWindow` material | 10.14 | 13.0 | No | HUD appearance |
| `CALayer.cornerCurve` | 10.15 | 13.0 | No | Squircle corners |
| `NSAnimationContext` | 10.3 | 13.0 | No | Split/merge animation |
| `CAKeyframeAnimation` | 10.5 | 13.0 | No | Slide animation (existing) |
| `viewDidChangeEffectiveAppearance()` | 10.14 | 13.0 | No | Appearance change callback |
| `@Environment(\.colorScheme)` | 10.15 | 13.0 | No | SwiftUI dark/light |
| `NSHostingView` | 10.15 | 13.0 | No | SwiftUI bridge |
| Timer (Foundation) | 10.0 | 13.0 | No | Idle timer |

**Everything is available unconditionally at macOS 13+. No `#available` guards needed.**

---

## Package.swift Changes

### None Required

All APIs are from system frameworks already imported:
- **AppKit** (`NSVisualEffectView`, `NSAnimationContext`, `NSAppearance`)
- **SwiftUI** (`NSHostingView`, `@Environment`)
- **QuartzCore** (`CAKeyframeAnimation`, `CATransaction`, `CALayer`)
- **Foundation** (`Timer`)

Current `platforms: [.macOS(.v13)]` is correct. No dependency additions.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Glass material | NSVisualEffectView (.hudWindow) | SwiftUI .glassEffect() | macOS 26+ only; regression in floating windows; cannot animate frame independently |
| Glass material | NSVisualEffectView (.hudWindow) | NSGlassEffectView | macOS 26+ only; deployment target would exclude macOS 13-25 users |
| Glass material | NSVisualEffectView (.hudWindow) | CALayer CIGaussianBlur filter | High CPU; CIFilter(name:) can silently return nil (MEMORY.md) |
| Glass material | NSVisualEffectView (.hudWindow) | Custom blur via CIImage | Requires manual rendering pipeline; not GPU-composited by WindowServer |
| Blending mode | .withinWindow | .behindWindow | Samples desktop, not screenshot; breaks frozen-frame illusion |
| Split animation | NSAnimationContext + frame | SwiftUI matchedGeometryEffect | Cannot control NSVisualEffectView positions; wrong abstraction level |
| Split animation | NSAnimationContext + frame | GlassEffectContainer morphing | macOS 26+ only; spacing animation may not produce fluid morph |
| Slide animation | CAKeyframeAnimation (keep existing) | NSAnimationContext | Teleport pattern (exit one side, enter other) requires keyframe values |
| State machine | Swift enum in HintBarView | SwiftUI @State | State drives NSView frame animations; must be in AppKit layer |
| Content rendering | SwiftUI via NSHostingView | Pure AppKit (NSBezierPath) | SwiftUI already built, declarative, appearance-reactive; rewriting wastes time |
| Idle timer | Foundation Timer | DispatchSourceTimer | Timer is simpler for single-threaded main queue use; no dealloc crash risk |

---

## Sources

- [NSVisualEffectView -- Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview) -- HIGH confidence
- [NSVisualEffectView.BlendingMode.withinWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/withinwindow) -- HIGH confidence
- [NSVisualEffectView.Material.hudWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material/hudwindow) -- HIGH confidence
- [NSGlassEffectView -- Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsglasseffectview) -- macOS 26+
- [Build an AppKit app with the new design -- WWDC25 Session 310](https://developer.apple.com/videos/play/wwdc2025/310/)
- [Reverse Engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview) -- CABackdropLayer internals
- [WindowServer on macOS](https://andreafortuna.org/2025/10/05/macos-windowserver) -- compositor performance
- [NSWindow Styles showcase](https://github.com/lukakerr/NSWindowStyles) -- borderless + visual effect configurations
- [CABackdropLayer & CAPluginLayer](https://medium.com/@avaidyam/capluginlayer-cabackdroplayer-f56e85d9dc2c) -- blur sampling behavior
- Codebase: HintBarView.swift, HintBarContent.swift, RulerWindow.swift, CrosshairView.swift
