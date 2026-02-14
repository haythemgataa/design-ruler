# Architecture Patterns: Hint Bar Redesign

**Domain:** macOS pixel inspector (Raycast extension) -- hint bar redesign with liquid glass, split animation, multi-state
**Researched:** 2026-02-13
**Overall confidence:** MEDIUM (NSGlassEffectView is macOS 26+ only; within-overlay blur behavior unverified)

---

## 1. Current Architecture (As-Is)

### HintBarView Layer Stack

```
RulerWindow (NSWindow, borderless, fullscreen per-screen)
  contentView (NSView container)
    +-- bgView (NSView, frozen screenshot as layer.contents)
    +-- CrosshairView (NSView, CAShapeLayer hierarchy)
    +-- HintBarView (NSView, peer of CrosshairView)
          +-- NSHostingView<HintBarContent> (SwiftUI)
               +-- VStack(spacing: -2)
                    +-- MainHintCard (arrows + shift text, dark bg, shadow)
                    +-- ExtraHintCard (esc text, darker bg, shadow)
```

### Current Rendering Approach

- HintBarView is an `NSView` hosting SwiftUI content via `NSHostingView`
- SwiftUI handles all rendering: `RoundedRectangle` fills, shadows, text layout
- Background colors are hardcoded per `colorScheme` (.dark/.light environment)
- No blur, no vibrancy, no glass -- solid opaque backgrounds with shadows
- Key press feedback via `@Published pressedKeys` set on `HintBarState` ObservableObject

### Current Animation

- Slide animation: `CAKeyframeAnimation` on `position.y` with 4 keyframes (current -> offscreen -> offscreen-opposite -> final)
- Duration: 0.3s, ease-in for exit, custom cubic for entry
- `isAnimating` guard prevents overlapping animations
- Frame-based positioning: `frame.origin.y` set immediately, animation overrides presentation

### Current Integration Points

| Caller | Method | Purpose |
|--------|--------|---------|
| `RulerWindow.setupViews()` | `HintBarView(frame: .zero)` | Creation |
| `RulerWindow.setupViews()` | `hv.configure(screenWidth:screenHeight:)` | Initial positioning |
| `RulerWindow.mouseMoved()` | `hintBarView.updatePosition(cursorY:screenHeight:)` | Proximity-based top/bottom swap |
| `RulerWindow.keyDown()` | `hintBarView.pressKey(.left/.right/.up/.down/.esc)` | Visual key feedback |
| `RulerWindow.keyUp()` | `hintBarView.releaseKey(...)` | Release visual feedback |
| `RulerWindow.flagsChanged()` | `hintBarView.pressKey/releaseKey(.shift)` | Modifier tracking |
| `Ruler.run()` | `hideHintBar` parameter on `RulerWindow.create()` | Hide preference |

---

## 2. Design Decision: Glass Technology

### The Core Question

The window has a **frozen screenshot as background** (not desktop content). This fundamentally affects which blur technology works.

### Option A: NSVisualEffectView (behindWindow)

**Problem:** `behindWindow` blending samples content from behind the *window*, i.e., the actual desktop. But the RulerWindow is opaque (`window.isOpaque = true`) with a screenshot background. The blur would sample the real desktop (which may have changed since capture), not the frozen screenshot. This creates a visual mismatch -- the blurred glass would show different content than the screenshot behind it.

**Verdict: NOT SUITABLE.** The window is intentionally opaque with a static screenshot. Behind-window blur defeats the "frozen frame" illusion.

### Option B: NSVisualEffectView (withinWindow)

**How it works:** `withinWindow` blending samples content from sibling views *within the same window*. The blur would sample the screenshot bgView that sits behind it in the view hierarchy.

**This is the correct approach.** The frozen screenshot IS the content to blur. `withinWindow` blending will blur the screenshot pixels beneath the hint bar, creating a frosted glass appearance that matches the frozen frame.

**Setup:**
```swift
let vev = NSVisualEffectView(frame: barFrame)
vev.blendingMode = .withinWindow
vev.material = .hudWindow    // dark translucent, good for overlays
vev.state = .active           // always active, don't follow window state
vev.wantsLayer = true
```

**Confidence: MEDIUM.** `withinWindow` should sample the bgView's screenshot content, but this is unverified in practice with the specific window setup (opaque borderless window, CALayer contents-based background). Needs a prototype to confirm the blur actually samples the screenshot and not just black.

### Option C: NSGlassEffectView (macOS 26+)

**What it is:** New in macOS 26 Tahoe. `NSGlassEffectView` is an NSView subclass that provides Apple's new "Liquid Glass" material -- translucent with refraction, specular highlights, and adaptive shadows.

**API surface:**
```swift
let glass = NSGlassEffectView()
glass.contentView = myContentView  // content rendered ON the glass
glass.cornerRadius = 18
glass.tintColor = .systemBlue.withAlphaComponent(0.3)
```

**Key constraint:** NSGlassEffectView works by setting its `contentView` property. You do NOT place it behind content as a sibling -- you place content INSIDE it. This is different from NSVisualEffectView.

**Problem 1 -- Deployment target:** Package.swift currently targets `.macOS(.v13)` (Ventura). NSGlassEffectView requires macOS 26. Bumping the minimum deployment target would exclude users on macOS 13-25.

**Problem 2 -- Overlay context unknown:** NSGlassEffectView is documented for standard application UI (toolbars, sidebars, HUDs). Whether it produces correct visuals in a borderless fullscreen overlay with a screenshot background is undocumented. It may try to sample desktop content (like `behindWindow`) rather than the in-window screenshot.

**Problem 3 -- Raycast compatibility:** Raycast extensions must work on the Raycast-supported macOS versions. Requiring macOS 26 for the hint bar would break on older systems.

**Verdict: NOT YET.** Use NSVisualEffectView (withinWindow) as the primary approach. NSGlassEffectView can be adopted later via `#available(macOS 26, *)` runtime check once: (a) the behavior in overlay windows is verified, and (b) a fallback path for macOS 13-25 is implemented.

### Recommendation

**Use NSVisualEffectView with `.withinWindow` blending and `.hudWindow` material.** This:
- Works on macOS 13+ (current deployment target)
- Blurs the frozen screenshot (within-window content)
- Provides a frosted glass look that adapts to the screenshot underneath
- Is well-documented and widely used in overlay/HUD contexts

**Future enhancement:** Add `NSGlassEffectView` behind `#available(macOS 26, *)` for true liquid glass on Tahoe+.

---

## 3. Recommended Architecture: New HintBarView

### State Machine

The hint bar has three visual states:

```
                    mouse idle 3s                    cursor near hint
[EXPANDED] -----------------------> [COLLAPSED] <---------------------- [REPOSITIONING]
    ^                                    |                                     |
    |                                    |                                     |
    +--- any key press ------------------+                                     |
    +--- cursor near hint (hover) -------+                                     |
                                                                               |
    position swap (bottom <-> top) triggers REPOSITIONING, which resolves      |
    back to EXPANDED or COLLAPSED depending on prior state                     |
```

| State | Visual | Content |
|-------|--------|---------|
| `expanded` | Single bar, full width | "Use [arrows] to skip an edge. Plus [shift] to invert." + ESC hint below |
| `collapsed` | Two small floating bars | Left: arrow cluster only. Right: ESC keycap only (tinted). |
| `repositioning` | Animating position | Slide animation (existing pattern), then resolve to prior content state |

### Component Hierarchy (New)

```
HintBarView (NSView, container -- NO SwiftUI)
  +-- NSVisualEffectView (withinWindow, hudWindow material)
  |     +-- contentStack (NSView, hosts expanded content)
  |           +-- mainCardHost: NSHostingView<MainHintCard>
  |           +-- extraCardHost: NSHostingView<ExtraHintCard>
  |
  +-- leftGlassBar (NSVisualEffectView, withinWindow)  -- collapsed state
  |     +-- arrowClusterHost: NSHostingView<ArrowCluster>
  |
  +-- rightGlassBar (NSVisualEffectView, withinWindow) -- collapsed state
        +-- escKeyHost: NSHostingView<EscKeyCap>
```

**Wait -- why NOT just use SwiftUI for everything like the current design?**

The current design wraps everything in a single `NSHostingView<HintBarContent>`. This works when there is one continuous bar. But the split animation requires:

1. Two independent views that move to different positions
2. Glass blur backgrounds that respond to position changes (blur samples different screenshot regions as they move)
3. Frame-based position animation (CAKeyframeAnimation on `position.y`)

SwiftUI's `matchedGeometryEffect` could handle the morph, but it cannot control `NSVisualEffectView` backgrounds, and NSHostingView within a CALayer animation context has known performance issues. The split animation is fundamentally a frame/position animation, which is Core Animation's strength.

### Revised Approach: Hybrid SwiftUI + AppKit

Keep SwiftUI for **content rendering** (keycaps, text) but use AppKit `NSView` + `NSVisualEffectView` for **glass backgrounds and positioning**.

```
HintBarView (NSView, manages state + animations)
  |
  [EXPANDED state]:
  +-- expandedBar (NSVisualEffectView, rounded rect mask, withinWindow)
  |     +-- NSHostingView<ExpandedHintContent> (text + keycaps)
  |
  [COLLAPSED state]:
  +-- leftBar (NSVisualEffectView, pill-shaped mask, withinWindow)
  |     +-- NSHostingView<ArrowClusterContent>
  |
  +-- rightBar (NSVisualEffectView, pill-shaped mask, withinWindow)
        +-- NSHostingView<EscContent>
```

Only one set of views is visible at a time. The split animation crossfades + repositions.

---

## 4. Split Animation Design

### Animation: Expanded to Collapsed

When the user is idle for 3 seconds, the expanded bar splits into two collapsed bars.

**Approach: Cross-fade with position interpolation**

The split cannot be a literal "one view tears into two" because NSVisualEffectView cannot be clipped mid-animation in a way that maintains blur sampling. Instead:

```
Phase 1 (0.0s - 0.15s): Expanded bar fades out, shrinks slightly (scaleX: 0.95)
Phase 2 (0.1s - 0.3s):  Two collapsed bars fade in at their target positions
                          Left bar slides in from center-left
                          Right bar slides in from center-right
```

**Implementation:**

```swift
func animateToCollapsed() {
    guard currentState == .expanded else { return }
    currentState = .collapsed

    // Position collapsed bars at center (where expanded bar was)
    let centerX = expandedBar.frame.midX
    leftBar.frame.origin.x = centerX - leftBar.frame.width
    rightBar.frame.origin.x = centerX
    leftBar.alphaValue = 0
    rightBar.alphaValue = 0
    leftBar.isHidden = false
    rightBar.isHidden = false

    // Animate expanded bar out
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
        expandedBar.animator().alphaValue = 0
    }

    // Animate collapsed bars in (slight delay)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            self.leftBar.animator().frame.origin.x = self.leftBarTargetX
            self.leftBar.animator().alphaValue = 1
            self.rightBar.animator().frame.origin.x = self.rightBarTargetX
            self.rightBar.animator().alphaValue = 1
        })
    }
}
```

**Why NOT use CAKeyframeAnimation (like the current slide)?**

The current slide animation uses `CAKeyframeAnimation` on `position.y` because it needs teleport behavior (exit one side, enter the other). The split animation is a standard ease-in/ease-out transition -- `NSAnimationContext` (which wraps Core Animation) is simpler and sufficient. The slide animation should remain as `CAKeyframeAnimation` because the teleport pattern cannot be expressed with `NSAnimationContext`.

### Animation: Collapsed to Expanded

Reverse of the above. On any key press or cursor hover near the bars:

```
Phase 1 (0.0s - 0.15s): Collapsed bars fade out, slide toward center
Phase 2 (0.1s - 0.3s):  Expanded bar fades in at position
```

### Position Swap During Collapsed State

When the cursor approaches the bottom (or top) and the bars need to swap position, BOTH collapsed bars must move together. The existing `updatePosition()` logic applies to both bars simultaneously:

```swift
func updatePosition(cursorY: CGFloat, screenHeight: CGFloat) {
    // Same proximity logic as before
    let shouldBeAtTop = cursorY < threshold
    guard shouldBeAtTop != isAtTop, !isAnimating else { return }

    let targetY: CGFloat = shouldBeAtTop
        ? screenHeight - barHeight - topMargin
        : barMargin

    // Animate ALL visible bars (expanded or both collapsed)
    animateSlide(to: targetY, screenHeight: screenHeight, exitDown: shouldBeAtTop)
}

private func animateSlide(to finalY: CGFloat, ...) {
    // Apply the SAME CAKeyframeAnimation to all visible bar layers
    let visibleBars = currentState == .expanded
        ? [expandedBar]
        : [leftBar, rightBar].compactMap { $0 }

    for bar in visibleBars {
        bar.layer?.add(slideAnimation, forKey: "hintBarSlide")
        bar.frame.origin.y = finalY
    }
}
```

---

## 5. ESC Tint and Appearance Changes

### Problem

The ESC keycap in collapsed state needs a distinctive tint (e.g., red/warm) to signal "exit". This tint must respond to `NSAppearance` changes (system dark/light mode switches while the overlay is active).

### Current Appearance Handling

The existing SwiftUI content uses `@Environment(\.colorScheme)`. This automatically updates when the hosting window's `effectiveAppearance` changes. Since the overlay window follows system appearance, SwiftUI views inside `NSHostingView` will re-render when appearance changes.

### Implementation

```swift
// In the SwiftUI EscContent view:
struct EscContent: View {
    @ObservedObject var state: HintBarState
    @Environment(\.colorScheme) private var colorScheme

    private var escTint: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0))
            : Color(nsColor: NSColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0))
    }

    var body: some View {
        KeyCap(.esc, symbol: "esc", ...)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(escTint, lineWidth: 1.5)
            )
    }
}
```

For the NSVisualEffectView tint on the right collapsed bar:

```swift
// NSVisualEffectView does NOT have a tintColor property (that's NSGlassEffectView).
// Instead, add a semi-transparent color overlay layer:
private func updateEscBarTint() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    escTintLayer.backgroundColor = isDark
        ? CGColor(srgbRed: 1.0, green: 0.3, blue: 0.3, alpha: 0.08)
        : CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 0.06)
}

// Called from:
override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateEscBarTint()
}
```

**Key insight:** `viewDidChangeEffectiveAppearance()` is called automatically by AppKit when the system appearance changes. The SwiftUI `@Environment(\.colorScheme)` will also update because `NSHostingView` bridges this automatically.

---

## 6. Performance Analysis: Bitmap vs Live Layers

### Current: Static Bitmap (layer.contents)

The CLAUDE.md originally described a bitmap-cached approach (`wantsUpdateLayer = true`, render once into `NSBitmapImageRep`, set as `layer.contents`). The current implementation has already departed from this -- it uses `NSHostingView<HintBarContent>` which is a live SwiftUI view tree. So the performance concern about "switching from bitmap to live layers" is somewhat moot -- the codebase already uses live SwiftUI rendering.

### New: NSVisualEffectView + Live SwiftUI

**Additional cost:**
- NSVisualEffectView creates a `CABackdropLayer` internally that samples content behind it
- `withinWindow` mode: WindowServer composites the layer hierarchy to produce the blur
- This is GPU-accelerated and handled by WindowServer, not the app's CPU
- **Idle cost:** After WindowServer flattens the layer tree (~1s of no changes), the blur is composited into a bitmap automatically. CPU cost returns to ~0.

**During animation:**
- While the hint bar is animating (slide, split), WindowServer must recomposite each frame
- For a 0.3s animation at 60fps = ~18 frames of compositing
- This is identical to the current slide animation cost (layer position changes already trigger recompositing)

**During mouse movement:**
- The hint bar does NOT change on mouse movement (only position-swaps when cursor is near bottom/top)
- Normal mouse movement only updates CrosshairView layers -- HintBarView layers are untouched
- **No additional CPU cost during normal mouse tracking**

### Performance Verdict

| Scenario | Current (SwiftUI) | New (NSVisualEffectView + SwiftUI) | Delta |
|----------|-------------------|-------------------------------------|-------|
| Idle (no cursor near bar) | ~0% CPU | ~0% CPU (flattened by WindowServer) | None |
| Mouse movement | ~0% (bar untouched) | ~0% (bar untouched) | None |
| Key press (keycap animation) | SwiftUI re-render | SwiftUI re-render + blur resample | Negligible |
| Position swap | CAKeyframeAnimation | CAKeyframeAnimation + blur resample | Negligible |
| Split/merge animation | N/A (new) | ~18 frames of compositing | Brief spike, acceptable |

**Conclusion:** The switch to NSVisualEffectView adds negligible overhead. The `<5% CPU during mouse movement` constraint is maintained because the hint bar layers are not touched during mouse movement.

---

## 7. New Component Breakdown

### Files to Modify

| File | Changes |
|------|---------|
| `HintBarView.swift` | Major rewrite: replace NSHostingView wrapper with multi-bar NSVisualEffectView architecture, state machine, split animation |
| `HintBarContent.swift` | Refactor: extract `MainHintCard`, `ExtraHintCard`, `ArrowCluster`, `KeyCap` into reusable components; add `EscContent` for collapsed state |
| `RulerWindow.swift` | Minor: add idle timer for auto-collapse, wire new state transitions |

### Files to Create

None. All changes fit within existing files. The hint bar is already a self-contained NSView -- expanding its internal complexity does not require new files.

### HintBarView New API Surface

```swift
final class HintBarView: NSView {
    // MARK: - State
    enum BarState { case expanded, collapsed, animating }
    private(set) var barState: BarState = .expanded

    // MARK: - Existing Public API (unchanged)
    func pressKey(_ key: KeyID)
    func releaseKey(_ key: KeyID)
    func configure(screenWidth: CGFloat, screenHeight: CGFloat)
    func updatePosition(cursorY: CGFloat, screenHeight: CGFloat)

    // MARK: - New Public API
    func collapse(animated: Bool)     // expanded -> collapsed
    func expand(animated: Bool)       // collapsed -> expanded

    // MARK: - Internal
    private var expandedBar: NSVisualEffectView    // glass bg for expanded
    private var leftBar: NSVisualEffectView        // glass bg for collapsed arrows
    private var rightBar: NSVisualEffectView       // glass bg for collapsed ESC
    private var expandedHost: NSHostingView<...>   // SwiftUI content
    private var arrowHost: NSHostingView<...>      // SwiftUI collapsed left
    private var escHost: NSHostingView<...>        // SwiftUI collapsed right
    private var escTintLayer: CALayer              // appearance-reactive tint
    private var idleTimer: Timer?                  // auto-collapse timer
}
```

### RulerWindow Integration Changes

```swift
// In RulerWindow:

// New: reset idle timer on mouse move
override func mouseMoved(with event: NSEvent) {
    // ... existing logic ...
    hintBarView.resetIdleTimer()  // or handle in RulerWindow with a timer
}

// New: expand on key press
override func keyDown(with event: NSEvent) {
    // ... existing logic ...
    if hintBarView.barState == .collapsed {
        hintBarView.expand(animated: true)
    }
}
```

**Alternative:** Keep the idle timer inside HintBarView itself (it already manages its own animation state). RulerWindow just calls `hintBarView.noteActivity()` on mouse move, and HintBarView internally resets its idle timer. This keeps the timer logic encapsulated.

---

## 8. NSVisualEffectView Configuration Details

### Material Choice

| Material | Appearance | Use Case |
|----------|-----------|----------|
| `.hudWindow` | Dark translucent | Best for floating overlays on arbitrary backgrounds |
| `.popover` | Lighter, more opaque | Too opaque for a hint bar |
| `.menu` | System menu appearance | Wrong semantic context |
| `.sidebar` | Sidebar appearance | Wrong semantic context |
| `.underWindowBackground` | Very subtle | Too transparent |

**Recommendation: `.hudWindow`** -- designed specifically for heads-up display elements floating over arbitrary content. Matches the overlay context perfectly.

### Rounded Corners

NSVisualEffectView does not have a `cornerRadius` property. Use a mask layer:

```swift
expandedBar.wantsLayer = true
expandedBar.layer?.cornerRadius = 18
expandedBar.layer?.cornerCurve = .continuous  // squircle
expandedBar.layer?.masksToBounds = true
```

**`cornerCurve = .continuous`** gives the iOS-style squircle corners that match the current `RoundedRectangle(cornerRadius:style:.continuous)` in SwiftUI.

### State Management

Set `state = .active` to prevent the visual effect from deactivating when the window loses focus (which should not happen in this fullscreen overlay, but guards against edge cases):

```swift
vev.state = .active
```

---

## 9. Appearance-Reactive Design

### Dark/Light Mode in Overlay Context

The overlay window uses `.isOpaque = true` and does not set an explicit appearance. It inherits the system appearance. When the system switches between dark and light mode:

1. `NSView.viewDidChangeEffectiveAppearance()` fires on all views
2. SwiftUI `@Environment(\.colorScheme)` updates in all `NSHostingView` instances
3. `NSVisualEffectView` automatically adjusts its material rendering

The hint bar needs to handle:

| Element | Dark Mode | Light Mode |
|---------|-----------|------------|
| Glass background | `.hudWindow` auto-adjusts | `.hudWindow` auto-adjusts |
| Text color | White (existing) | Black (existing) |
| Keycap colors | Dark caps, white border (existing) | Light caps, black border (existing) |
| ESC tint overlay | Red at 8% opacity | Red at 6% opacity |

**SwiftUI handles most of this automatically** via `@Environment(\.colorScheme)`. The only manual handling needed is the ESC tint layer on the NSVisualEffectView (see Section 5).

---

## 10. Multi-Monitor Considerations

### Current Behavior

- Hint bar is created only on the cursor's screen at launch
- Other screens get `hideHintBar: true`
- When cursor moves to another screen, `activate(firstMoveAlreadyReceived:)` is called but hint bar is not transferred

### New Behavior (Unchanged)

The hint bar stays on the original screen. This is correct -- the hint bar is informational, not interactive. Moving it between screens would be disorienting during the split animation.

### Collapsed Bars Positioning

Both collapsed bars must maintain consistent positioning relative to each other across the bottom/top swap:

```
[BOTTOM position]:
  Screen edge
  |  16px margin  |  [leftBar]  24px gap  [rightBar]  |  16px margin  |
                         centered on screen width

[TOP position]:
  Same horizontal layout, y = screenHeight - barHeight - 48px (notch clearance)
```

---

## 11. Data Flow Diagram

```
User Activity                    HintBarView State Machine              Visual Output
============                     ========================              =============

Launch                           .expanded                              Full hint bar visible
  |
  v
Mouse idle 3s ------timer------> .collapsed                             Split: two small bars
  |
  v
Arrow key press ------------------> .expanded                           Merge: full bar
  |
  v
Mouse idle 3s ------timer------> .collapsed                             Split again
  |
  v
Cursor near bottom ------------> .collapsed + repositioning             Both bars slide to top
  |
  v
ESC --------------------------> [exit, no state change needed]          Window closes
```

### Idle Timer Flow

```
mouseMoved in RulerWindow
  --> hintBarView.noteActivity()
    --> idleTimer?.invalidate()
    --> if barState == .collapsed { expand(animated: true) }
    --> idleTimer = Timer(3s) { self.collapse(animated: true) }

keyDown in RulerWindow
  --> hintBarView.noteActivity()  (same as above)
  --> if barState == .collapsed { expand(animated: true) }
```

**Note:** `noteActivity()` both resets the timer AND expands if collapsed. This means any user interaction immediately shows the full hint bar, and inactivity collapses it.

---

## 12. Build Order (Suggested Phases)

### Phase 1: Glass Background Prototype

**Goal:** Verify NSVisualEffectView with `.withinWindow` blending works correctly in the overlay context.

**What to build:**
1. Replace HintBarView's solid SwiftUI backgrounds with NSVisualEffectView
2. Keep existing SwiftUI content as-is (hosted inside the NSVisualEffectView)
3. Keep existing single-bar layout
4. Keep existing slide animation

**Why first:** This is the highest-risk unknown. If `.withinWindow` does not correctly blur the screenshot background, the entire glass approach needs rethinking. Validate this before building the split animation.

**Verification:**
- Glass bar should show blurred screenshot content underneath
- Blur should be consistent whether bar is at top or bottom
- Moving bar (slide animation) should maintain correct blur sampling
- CPU should remain under 5% during mouse movement

**Fallback if withinWindow fails:** Use a solid semi-transparent background (what we essentially have now but with alpha). This is visually inferior but functionally correct.

### Phase 2: State Machine + Collapse/Expand

**Goal:** Add the expanded/collapsed state machine without the split animation.

**What to build:**
1. Add `BarState` enum to HintBarView
2. Create collapsed content views (arrow cluster, ESC keycap)
3. Implement `collapse(animated:)` / `expand(animated:)` with simple fade transitions
4. Add idle timer
5. Wire `noteActivity()` from RulerWindow

**Why second:** The state machine is the foundation for the split animation. Getting the states and transitions right with simple fades first avoids debugging state logic and animation simultaneously.

### Phase 3: Split Animation

**Goal:** Replace fade transitions with the split/merge animation.

**What to build:**
1. Create separate `leftBar` and `rightBar` NSVisualEffectView instances
2. Implement split animation (expanded -> two bars sliding apart)
3. Implement merge animation (two bars sliding together -> expanded)
4. Ensure position swap works with both single and dual bars

**Why third:** This is purely visual polish. The state machine from Phase 2 already handles all the logic -- this phase only changes HOW the transitions look.

### Phase 4: ESC Tint + Appearance Polish

**Goal:** Add the ESC tint, appearance reactivity, and visual refinements.

**What to build:**
1. Add ESC tint overlay layer on rightBar
2. Implement `viewDidChangeEffectiveAppearance()` handler
3. Tune animation curves and timings
4. Verify multi-monitor behavior (hint bar only on cursor screen)

**Why last:** Appearance handling and tint are cosmetic details. They do not affect the structural architecture and can be tuned independently.

### Dependency Graph

```
Phase 1 (Glass Prototype)
    |
    v
Phase 2 (State Machine)
    |
    v
Phase 3 (Split Animation)
    |
    v
Phase 4 (ESC Tint + Polish)
```

Strictly sequential. Each phase builds on the previous.

---

## 13. Anti-Patterns to Avoid

### Anti-Pattern 1: Using behindWindow Blending

**What:** Setting `NSVisualEffectView.blendingMode = .behindWindow`
**Why bad:** The overlay window has a screenshot as its background. `behindWindow` would blur the *actual desktop* behind the window, not the screenshot. This creates a visual mismatch where the blur shows different content than what the user sees.
**Instead:** Use `.withinWindow` which blurs sibling view content within the same window.

### Anti-Pattern 2: Animating NSVisualEffectView's frame During Blur

**What:** Changing the frame of an NSVisualEffectView while expecting real-time blur updates during animation.
**Why bad:** WindowServer may not resample the backdrop on every frame of a Core Animation animation. The blur could show stale content or artifacts during movement.
**Instead:** Test the slide animation thoroughly. If blur lags during animation, consider temporarily setting `state = .inactive` during the animation and re-enabling `.active` in the completion block.

### Anti-Pattern 3: Creating NSGlassEffectView Without Availability Check

**What:** Using `NSGlassEffectView` directly without `#available(macOS 26, *)`.
**Why bad:** Crashes on macOS 13-25. The deployment target is macOS 13.
**Instead:** Always guard with availability checks. Provide NSVisualEffectView fallback.

### Anti-Pattern 4: Putting the Idle Timer in RulerWindow

**What:** Managing the collapse/expand idle timer in RulerWindow's mouseMoved.
**Why bad:** RulerWindow already has complex mouse event handling (drag, hover, multi-monitor). Adding timer management clutters it further. HintBarView should own its own animation state.
**Instead:** HintBarView exposes `noteActivity()`. RulerWindow calls it. Timer logic stays inside HintBarView.

### Anti-Pattern 5: Using matchedGeometryEffect for the Split

**What:** Using SwiftUI's `matchedGeometryEffect` to morph the expanded bar into two collapsed bars.
**Why bad:** `matchedGeometryEffect` works within SwiftUI's view diffing system. It cannot control `NSVisualEffectView` backgrounds. The glass backgrounds are AppKit views, not SwiftUI views. Trying to bridge these systems creates complexity without benefit.
**Instead:** Use explicit AppKit frame animations for the bars and let SwiftUI handle only the content rendering inside them.

### Anti-Pattern 6: Rendering Glass with CALayer Filters

**What:** Using `CALayer.compositingFilter` or `CALayer.filters` with `CIGaussianBlur` to simulate glass.
**Why bad:** As documented in MEMORY.md, `CIFilter(name:)` can return nil silently. Even when it works, layer-based blur filters are not GPU-accelerated the same way NSVisualEffectView's `CABackdropLayer` is. They cause significant CPU overhead for real-time blur.
**Instead:** Use NSVisualEffectView, which uses the private `CABackdropLayer` for hardware-accelerated WindowServer compositing.

---

## 14. Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| `withinWindow` blur does not sample screenshot bgView | HIGH | MEDIUM | Phase 1 prototype validates this first. Fallback: semi-transparent solid bg |
| WindowServer overhead during split animation | LOW | LOW | Animation is brief (0.3s). Monitor with Instruments. |
| Blur lag during position swap (slide) | MEDIUM | MEDIUM | Test thoroughly. Fallback: disable blur during animation. |
| NSHostingView performance in collapsed state | LOW | LOW | Collapsed bars host tiny SwiftUI views (1-2 keycaps). Negligible overhead. |
| macOS 26.3 borderless window regression | HIGH | LOW | This is a general macOS 26.3 issue affecting all borderless windows, not specific to this change. Monitor Apple Developer Forums for fixes. |
| Idle timer conflicts with position swap animation | MEDIUM | MEDIUM | Guard: do not collapse/expand while `isAnimating` for slide. |

---

## Sources

### Official Documentation
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview) -- Apple Developer Documentation
- [NSVisualEffectView.BlendingMode.withinWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/withinwindow) -- Apple Developer Documentation
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) -- Apple Developer Documentation (macOS 26+)
- [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview) -- Apple Developer Documentation (macOS 26+)
- [Build an AppKit app with the new design - WWDC25 Session 310](https://developer.apple.com/videos/play/wwdc2025/310/) -- NSGlassEffectView usage patterns
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) -- SwiftUI glassEffect modifier

### Technical References
- [Reverse Engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview) -- Internal layer hierarchy (CABackdropLayer), compositor behavior
- [CABackdropLayer & CAPluginLayer](https://medium.com/@avaidyam/capluginlayer-cabackdroplayer-f56e85d9dc2c) -- Private API details, WindowServer interaction
- [NSWindow Styles showcase](https://github.com/lukakerr/NSWindowStyles) -- Borderless window + NSVisualEffectView configurations
- [WindowServer on macOS](https://andreafortuna.org/2025/10/05/macos-windowserver) -- Compositor performance, layer flattening behavior
- [LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) -- Community-maintained Liquid Glass API reference

### macOS 26 Specific
- [macOS 26.3 borderless window regression](https://developer.apple.com/forums/thread/814798) -- Apple Developer Forums thread on mouse event interception changes
- [AppKit macOS xcode26.0 API diff](https://github.com/dotnet/macios/wiki/AppKit-macOS-xcode26.0-b1) -- NSGlassEffectView API surface

### Codebase
- All current architecture analysis derived from direct source code reading of HintBarView.swift, HintBarContent.swift, RulerWindow.swift, CrosshairView.swift, Ruler.swift
