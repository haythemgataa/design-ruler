<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/design-ruler-icon@dark.png">
    <img src="assets/design-ruler-icon.png" width="96" alt="Design Ruler">
  </picture>

  # Design Ruler

  **Pixel-perfect measurement and alignment for macOS.**

  Design Ruler gives you two fullscreen overlay tools for inspecting UI: one for measuring pixel distances with automatic edge detection, and one for placing alignment guides anywhere on screen. Zoom to 4x to work pixel by pixel. Works across all monitors.

  Available as a **standalone menu bar app** or a **Raycast extension**.
</div>

---

## Commands

### <picture><source media="(prefers-color-scheme: dark)" srcset="assets/measure-icon@dark.png"><img src="assets/measure-icon.png" width="20" valign="middle" alt=""></picture> Measure

Freeze your screen and measure pixel distances between any two edges — instantly.

- **Fullscreen overlay** with a frozen screenshot as background — no visual disruption
- **Automatic edge detection** scans outward from your cursor in all 4 directions
- **Live W × H pill** updates as you move, showing exact pixel dimensions
- **Crosshair renders in difference blend mode** — always visible on light and dark backgrounds
- **Arrow keys** skip to the next detected edge; **Shift + Arrow** brings it back
- **Drag to select a region** — snaps to detected edges, shakes if too small
- **Hover a selection** and click to remove it
- **Smart 1px border corrections** — configurable: smart (default), include, or none
- **Zoom-aware** — edge detection, crosshair, and selections stay accurate at 2x and 4x; arrow-key skipping peek-pans to reveal edges outside the zoomed viewport
  [Measure.webm](https://github.com/user-attachments/assets/3a9c0342-d1f8-4033-9911-1ebeaa24700d)


### <picture><source media="(prefers-color-scheme: dark)" srcset="assets/alignment-guides-icon@dark.png"><img src="assets/alignment-guides-icon.png" width="20" valign="middle" alt=""></picture> Alignment Guides

Place horizontal and vertical guide lines anywhere on screen to check element alignment.

- **Fullscreen overlay** — click anywhere to place a guide line
- **Tab** toggles between vertical and horizontal guide orientation
- **Spacebar** cycles through 5 color presets: dynamic, red, green, orange, blue
- **Color circle indicator** shows the current color and fades after ~1 second
- **Hover a placed line** to enter remove mode — it turns red and dashed with a "Remove" pill
- **Click a hovered line** to remove it (shrink-to-point animation)
- **Position pill** on each placed line shows its exact X or Y coordinate
- **Zoom-aware** — guide lines are stored in capture space, so they stay pinned to the same pixels at 2x and 4x
  [Alignment Guides.webm](https://github.com/user-attachments/assets/66af28a6-a65f-4ce8-830d-3570e88bab0c)



---

## Shared Features

### Zoom

Press **Z** in either command to magnify the frozen screenshot. Available in both Measure and Alignment Guides.

- **Cycles 1x → 2x → 4x → 1x** on each press, animating over 0.25s
- **Anchored on the cursor** — the pixel under your cursor stays put as the zoom level changes
- **Crisp pixels** — nearest-neighbor magnification, so individual pixels stay sharp instead of blurring
- **Pans as you move** — the view follows the cursor 1:1 while zoomed, clamped to the screenshot bounds
- **Overlay UI stays screen-sized** — the crosshair, pills, guide lines, and hint bar don't scale with the content
- **Zoom level feedback** — the hint bar's Z keycap flashes the current level; a pill shows it instead when the hint bar is hidden
- **Per-screen** — each monitor's overlay has its own zoom state, and moving to another screen resets the one you left
- **Resets on exit** — ESC returns everything to 1x

### Overlay Behavior

- **Multi-monitor support** — one overlay window per screen; cursor determines which is active
- **Hint bar** — glass panel with keyboard shortcut illustrations, expands on launch then collapses
- **Inactivity watchdog** — auto-exits after 10 minutes
- **ESC** to exit from either command, cleanly restoring cursor state
- **Low CPU** — all rendering via Core Animation GPU compositing, target <5% during mouse movement

---

## Standalone App Features

### Menu Bar
Click the ruler icon in the menu bar to launch either command. The icon fills in while an overlay is active.

### Global Keyboard Shortcuts
Assign custom hotkeys to Measure and Alignment Guides in Settings. Hotkeys work from any application. Press the same hotkey while an overlay is active to dismiss it, or press the other command's hotkey to switch.

### Settings
Open from the menu bar dropdown. Configure:
- **General** — Launch at Login, Hide Hint Bar, Automatically Check for Updates
- **Measure** — Border Corrections mode, Measure shortcut
- **Alignment Guides** — Alignment Guides shortcut
- **About** — Version info, GitHub link, manual update check

### Auto-Updates
Design Ruler uses [Sparkle](https://sparkle-project.org) to check for updates automatically. You can also check manually from the menu bar.

---

## Install

### Standalone App

Download the latest DMG from [GitHub Releases](https://github.com/haythemgataa/design-ruler/releases), open it, and drag Design Ruler to Applications. The app lives in your menu bar — no Dock icon, no Cmd+Tab entry.

### Raycast Extension

Build from source with `ray build` or, **coming soon**, install from the [Raycast Store](https://www.raycast.com/store).

---

## Preferences

### Standalone App (Settings Window)
| Setting | Section | Options | Description |
|---|---|---|---|
| Launch at Login | General | On / Off | Start Design Ruler when you log in |
| Hide Hint Bar | General | On / Off | Hide the keyboard shortcut hint bar (both commands) |
| Auto-check for Updates | General | On / Off | Sparkle automatic update checks |
| Border Corrections | Measure | Smart / Include / None | How 1px borders are handled in measurements |
| Measure Shortcut | Measure | Key combo | Global hotkey for Measure |
| Alignment Guides Shortcut | Alignment Guides | Key combo | Global hotkey for Alignment Guides |

### Raycast Extension
| Preference | Command | Options | Description |
|---|---|---|---|
| Hide Hint Bar | Both | On / Off | Hide the keyboard shortcut hint bar |
| Corrections | Measure | Smart / Include / None | How 1px borders are handled in measurements |

---

## Keyboard Reference

### <picture><source media="(prefers-color-scheme: dark)" srcset="assets/measure-icon@dark.png"><img src="assets/measure-icon.png" width="16" valign="middle" alt=""></picture> Measure

| Key | Action |
|---|---|
| Arrow keys | Skip to next detected edge |
| Shift + Arrow | Un-skip (move edge closer) |
| Mouse move | Reset all skip counts |
| Drag | Select a region (snaps to edges) |
| Z | Cycle zoom (1x → 2x → 4x → 1x) |
| ESC | Exit |

### <picture><source media="(prefers-color-scheme: dark)" srcset="assets/alignment-guides-icon@dark.png"><img src="assets/alignment-guides-icon.png" width="16" valign="middle" alt=""></picture> Alignment Guides

| Key | Action |
|---|---|
| Tab | Toggle guide direction (vertical ↔ horizontal) |
| Spacebar | Cycle color preset |
| Click | Place guide line |
| Click (on hovered line) | Remove guide line |
| Z | Cycle zoom (1x → 2x → 4x → 1x) |
| ESC | Exit |

---

## Building from Source

**Requirements:** macOS 14+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen)

### Standalone App
```bash
cd App
xcodegen generate
xcodebuild -project "Design Ruler.xcodeproj" -scheme "Design Ruler" -configuration Debug build
```

### Raycast Extension
```bash
ray build
```

Both targets share the same Swift overlay code via the `DesignRulerCore` SPM library.
