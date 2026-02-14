# Research Summary: Hint Bar Redesign

**Domain:** macOS pixel inspector hint bar -- glass background, split animation, multi-state, appearance-aware styling
**Researched:** 2026-02-13
**Overall confidence:** MEDIUM

## Executive Summary

This milestone redesigns the hint bar with a glass background, a split animation that transforms one bar into two keycap capsules, and appearance-aware ESC key tinting. The central technology decision is **NSVisualEffectView with `.withinWindow` blending and `.hudWindow` material** rather than the macOS 26+ SwiftUI `.glassEffect()` API.

This decision was driven by three factors: (1) `.glassEffect()` requires macOS 26+ while the deployment target is macOS 13+, (2) a known regression (FB21375029) breaks `.glassEffect()` in floating/non-standard windows on macOS 26.2+, and (3) the split animation requires independent frame-based positioning of two glass panels, which `.glassEffect()` cannot support because it is tied to SwiftUI's view layout system. NSVisualEffectView is a mature, stable API available since macOS 10.10 that provides GPU-accelerated blur compositing via WindowServer's `CABackdropLayer`.

The highest-risk unknown is whether `.withinWindow` blending correctly samples the frozen screenshot background in the Ruler's opaque borderless window. This must be prototyped before building the full split animation. If sampling fails, the fallback is a semi-transparent solid background (visually inferior but functionally correct).

The architecture shifts from a single NSHostingView to a hybrid model: AppKit NSVisualEffectView panels for glass backgrounds and positioning, with SwiftUI NSHostingViews nested inside for content rendering (keycaps, text). A state machine in HintBarView (`expanded` / `collapsing` / `collapsed`) drives NSAnimationContext frame animations for the split and CAKeyframeAnimation for the existing slide.

## Key Findings

**Stack:** NSVisualEffectView (.hudWindow, .withinWindow) for glass; NSAnimationContext for split animation; SwiftUI via NSHostingView for content; NSAppearance + colorScheme for ESC tint. All APIs available at macOS 13+ -- no conditional compilation needed.

**Architecture:** HintBarView becomes a multi-panel state machine managing 1-3 NSVisualEffectViews (one expanded bar OR two collapsed capsules). SwiftUI content is hosted inside each glass panel. The existing slide animation is preserved and extended to animate multiple panels as a unit.

**Critical pitfall:** `.withinWindow` blur sampling against a CGImage-based background layer in an opaque borderless window is undocumented. Must prototype first.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Phase 1: Glass Background Prototype** - Validate NSVisualEffectView with .withinWindow in the exact Ruler window configuration
   - Addresses: Core visual upgrade (glass blur over screenshot)
   - Avoids: Building the full split animation on an unvalidated foundation
   - Research needed: YES -- verify .withinWindow sampling behavior empirically

2. **Phase 2: State Machine + Collapse/Expand** - Add expanded/collapsed state machine with simple fade transitions
   - Addresses: Multi-state hint bar, idle timer, keycap-only collapsed layout
   - Avoids: Debugging state logic and animation simultaneously
   - Research needed: NO -- standard enum state machine, NSAnimationContext

3. **Phase 3: Split Animation** - Replace fades with cross-fade + position interpolation
   - Addresses: The signature animation (one bar splits into two)
   - Avoids: Premature animation polish before state machine is solid
   - Research needed: NO -- NSAnimationContext frame animations, tested patterns

4. **Phase 4: ESC Tint + Appearance Polish** - Appearance-reactive ESC tint, animation tuning
   - Addresses: ESC key visual distinction, dark/light mode correctness
   - Avoids: Tuning cosmetics before structure is complete
   - Research needed: NO -- @Environment(\.colorScheme) already working, viewDidChangeEffectiveAppearance documented

**Phase ordering rationale:**
- Phase 1 first because it validates the highest-risk unknown (glass sampling). Everything else builds on this.
- Phase 2 before Phase 3 because the state machine must be correct before animating transitions.
- Phase 4 last because appearance handling is cosmetic polish that does not affect structure.
- Strictly sequential: each phase builds on the previous.

**Research flags for phases:**
- Phase 1: NEEDS prototype research (glass sampling behavior in opaque window)
- Phases 2-4: Standard patterns, unlikely to need additional research

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | NSVisualEffectView, NSAnimationContext, CAKeyframeAnimation all stable since macOS 10.x; zero new dependencies |
| Features | HIGH | Glass background, split animation, ESC tint are well-defined; keycap spec dimensions provided |
| Architecture | MEDIUM | Hybrid NSVisualEffectView + NSHostingView is a documented pattern, but the specific window config (opaque, borderless, statusBar level) adds uncertainty to blur sampling |
| Pitfalls | MEDIUM | `.withinWindow` sampling in opaque windows is the primary unknown; all other pitfalls (animation timing, appearance reactivity) are well-documented |

## Gaps to Address

- **`.withinWindow` blur sampling verification:** The highest-priority gap. Must prototype NSVisualEffectView with `.withinWindow` blending inside the Ruler's exact window configuration to confirm the blur samples the screenshot bgView, not black. This is a Phase 1 deliverable.
- **NSVisualEffectView frame animation blur resampling:** During the split animation (0.3s), does WindowServer resample the blur on every frame as the panels move? If blur lags, may need to temporarily set `state = .inactive` during animation. Test during Phase 3.
- **Collapsed bar sizing:** Exact fittingSize for collapsed keycap capsules (arrow cluster + shift vs. ESC only) needs to be measured after implementing the SwiftUI content. Horizontal positioning depends on these measurements.

## Sources

### Primary (HIGH confidence)
- [NSVisualEffectView - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [NSVisualEffectView.BlendingMode.withinWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/withinwindow)
- [NSVisualEffectView.Material.hudWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material/hudwindow)
- [NSAnimationContext - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsanimationcontext)
- [Build an AppKit app with the new design - WWDC25 Session 310](https://developer.apple.com/videos/play/wwdc2025/310/)
- Codebase analysis: HintBarView.swift, HintBarContent.swift, RulerWindow.swift

### Secondary (MEDIUM confidence)
- [Reverse Engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview) -- CABackdropLayer internals
- [NSWindow Styles showcase](https://github.com/lukakerr/NSWindowStyles) -- borderless + visual effect configurations
- [NSGlassEffectView - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsglasseffectview) -- macOS 26+ alternative (deferred)
- [GlassEffectTest - GitHub (siracusa)](https://github.com/siracusa/GlassEffectTest) -- FB21375029 regression demo

### Tertiary (LOW confidence)
- [CABackdropLayer & CAPluginLayer](https://medium.com/@avaidyam/capluginlayer-cabackdroplayer-f56e85d9dc2c) -- private API sampling behavior
- [Adopting Liquid Glass: Experiences and Pitfalls](https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences) -- community glass adoption experiences

---
*Research completed: 2026-02-13*
*Ready for roadmap: yes*
