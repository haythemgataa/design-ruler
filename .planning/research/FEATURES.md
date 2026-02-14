# Feature Landscape: Hint Bar Redesign

**Domain:** macOS pixel inspector hint bar -- glass background, split animation, multi-state, appearance-aware ESC tint
**Researched:** 2026-02-13

---

## Table Stakes

Features that define the redesigned hint bar. Missing = redesign feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Glass/frosted background | Solid opaque backgrounds look dated on macOS 14+. Vibrancy is the norm for floating HUD elements. | Medium | NSVisualEffectView with .hudWindow material, .withinWindow blending. Blurs the frozen screenshot beneath. |
| Expanded state: full instructional text + keycaps | First-time users need to learn arrow key + shift shortcuts. | Already built | Current HintBarContent (MainHintCard + ExtraHintCard) is the expanded state. |
| Collapsed state: keycap-only compact bars | After initial instruction, full text wastes screen space. Experienced users only need visual reminders. | Medium | Two small pill-shaped bars: left (arrow cluster + shift) and right (ESC keycap). |
| State machine: expanded -> collapsed transition | The collapse must be intentional, not jarring. | Medium | Timer-based (3s idle) or first-mouse-move trigger. Single direction: expanded -> collapsed. |
| Hit-test passthrough | Hint bar must not intercept mouse events (crosshair tracks underneath). | Already built | `hitTest(_:) -> nil` on all hint bar views. Must be preserved on new NSVisualEffectView wrappers. |
| Bottom/top repositioning | When cursor approaches bar, it slides out of the way. | Already built | Existing `updatePosition()` logic. Must work for both single expanded bar AND two collapsed bars. |
| Appearance-reactive keycaps | Keycaps must look correct in both dark and light mode. | Already built | `@Environment(\.colorScheme)` already handles this in KeyCap view. |

## Differentiators

Features that elevate the redesign beyond functional requirements.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Split animation (one bar -> two bars) | Unique, delightful transition. The glass background splits apart as the text fades. | High | Cross-fade expanded bar out + slide two collapsed bars in from center. NSAnimationContext for frame + opacity. |
| ESC keycap reddish tint in collapsed state | Visually communicates "exit" without text. Red tint on the right collapsed bar draws eye. | Low | Semi-transparent red overlay layer on the right NSVisualEffectView. Adapts to dark/light mode via `viewDidChangeEffectiveAppearance()`. |
| Merge animation (two bars -> one bar) | Reverse of split. Any key press or cursor hover re-expands the bar. | Medium | Reverse of split: collapsed bars slide toward center, expanded bar fades in. |
| Idle timer auto-collapse | Hint bar collapses automatically after 3s of no user interaction. Respects experienced users. | Low | Foundation Timer in HintBarView, reset on `noteActivity()`. |
| Coordinated slide for collapsed bars | Both collapsed bars move together during bottom/top position swap. | Medium | Apply same CAKeyframeAnimation to both leftBar and rightBar layers simultaneously. |
| Glass blur of screenshot content | The frosted glass shows blurred screenshot content underneath, tying the hint bar visually to the frozen frame. | Medium | NSVisualEffectView .withinWindow blending samples the bgView with the screenshot. |
| Keycap press animation in collapsed state | Key depression feedback continues working after collapse. | Low | Existing KeyCap SwiftUI view with `pressedKeys` state already handles this. Verify at new sizes. |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Re-expanding collapsed bars back to full text on timer | Adds complexity for zero value. Once the user has read instructions, they do not need them again. | One-way collapse triggered by idle timer. Only re-expands on key press or cursor hover. |
| behindWindow blur | Would blur the actual desktop, not the frozen screenshot. Creates visual mismatch. | Use .withinWindow which blurs in-window content (the screenshot). |
| SwiftUI .glassEffect() as primary | macOS 26+ only; known regression in floating windows; cannot animate frame independently for split. | NSVisualEffectView works on macOS 13+, frame-animatable. |
| Custom blur shader / CIFilter | High CPU, CIFilter(name:) can return nil silently, not GPU-composited by WindowServer. | NSVisualEffectView uses private CABackdropLayer for hardware-accelerated blur. |
| Glass on the screenshot background | Liquid glass is for navigation/HUD layers, not content. | Glass only on hint bar elements. Screenshot stays opaque. |
| Complex multi-stage staggered animation | Over-animating utility UI feels gratuitous. | Split/merge total duration under 0.3s. Cross-fade + slide simultaneously. |
| Persistent collapsed state across sessions | Adds UserDefaults complexity. Always fresh on launch -- show instructions first. | Reset to expanded on each launch. |
| Backspace dismiss (remove existing) | Being replaced by the split animation. Auto-collapse serves the same purpose. | Remove dismiss-on-backspace if it conflicts with new state machine. |

## Feature Dependencies

```
NSVisualEffectView (.withinWindow, .hudWindow)
  |
  +--> Glass background on expanded bar
  |      |
  |      +--> Glass background on collapsed bars (same tech, different frame)
  |             |
  |             +--> Split animation (fade expanded + slide-in collapsed)
  |                    |
  |                    +--> Merge animation (reverse of split)
  |
  +--> ESC tint overlay layer
         |
         +--> viewDidChangeEffectiveAppearance() handler

State machine (BarState enum)
  |
  +--> Idle timer (3s) triggers .collapsed
  |
  +--> Key press / cursor hover triggers .expanded
  |
  +--> Position swap triggers .repositioning (resolves to prior state)

Expanded bar (existing HintBarContent wrapped in NSVisualEffectView)
  |
  +--> Required BEFORE collapsed bars can be built

Hit-test passthrough (existing)
  |
  +--> Must be applied to ALL new NSVisualEffectView instances
```

## MVP Recommendation

### Priority 1: Glass background on existing bar (validate technology)
1. Wrap existing HintBarContent in NSVisualEffectView with .withinWindow blending
2. Verify blur correctly samples the frozen screenshot
3. Verify performance (CPU < 5% during mouse movement)
4. This is the highest-risk unknown -- validate before building everything else

### Priority 2: State machine + collapsed state
5. Add BarState enum (expanded/collapsed/animating)
6. Create collapsed content views (arrow cluster SwiftUI, ESC keycap SwiftUI)
7. Create leftBar and rightBar NSVisualEffectViews
8. Implement collapse/expand with simple fade transitions (no split animation yet)
9. Add idle timer (3s)
10. Wire noteActivity() from RulerWindow

### Priority 3: Split/merge animation
11. Replace fade transitions with split animation (cross-fade + slide)
12. Implement merge animation (reverse)
13. Ensure position swap works with dual bars

### Priority 4: ESC tint + polish
14. Add red tint overlay on rightBar
15. Implement viewDidChangeEffectiveAppearance() for tint reactivity
16. Tune animation curves
17. Verify multi-monitor behavior

### Defer
- NSGlassEffectView upgrade (requires macOS 26+ deployment target)
- Custom morph animation between shapes
- Persistence of collapsed state

## Sources

- [NSVisualEffectView -- Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [NSVisualEffectView.Material.hudWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material/hudwindow)
- [Build an AppKit app with the new design -- WWDC25](https://developer.apple.com/videos/play/wwdc2025/310/)
- [Reverse Engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview)
- Codebase: HintBarView.swift, HintBarContent.swift, RulerWindow.swift
