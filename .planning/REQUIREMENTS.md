# Requirements: Design Ruler

**Defined:** 2026-03-05
**Core Value:** Instant, accurate pixel inspection of anything on screen — zero friction from invoke to dimension readout, whether launched from Raycast or a global hotkey.

## v2.1 Requirements

Requirements for zoom feature. Each maps to roadmap phases.

### Zoom Core

- [ ] **ZOOM-01**: User can press Z to zoom the overlay to 2x centered on cursor
- [ ] **ZOOM-02**: User can press Z again to cycle to 4x, then back to 1x
- [ ] **ZOOM-03**: Zoom transitions are animated (smooth scale, not instant jump)
- [ ] **ZOOM-04**: View pans to follow cursor movement while zoomed
- [ ] **ZOOM-05**: Zoom level indicator visible on screen (shows "2x" or "4x")

### Measure Integration

- [ ] **MEAS-01**: Edge detection works correctly on zoomed pixel data
- [ ] **MEAS-02**: W×H dimensions show accurate point values at any zoom level
- [ ] **MEAS-03**: Arrow key edge skipping works while zoomed
- [ ] **MEAS-04**: Drag-to-select and snap-to-edges work at zoom level
- [ ] **MEAS-05**: Dimension pill renders correctly and stays readable while zoomed

### Guides Integration

- [ ] **GUID-01**: Preview line follows cursor correctly in zoomed view
- [ ] **GUID-02**: Click places guide at correct screen coordinate while zoomed
- [ ] **GUID-03**: Hover-to-remove hit testing works at zoom level
- [ ] **GUID-04**: Existing guide lines render at correct positions when zoom changes

### Shared UX

- [ ] **SHUX-01**: Hint bar shows Z key shortcut for zoom
- [ ] **SHUX-02**: Zoom state is per-window (multi-monitor independent)
- [ ] **SHUX-03**: Zoom resets to 1x on session exit

## Future Requirements

### Zoom Enhancements

- **ZFUT-01**: Pixel grid overlay at 4x+ zoom showing individual pixel boundaries
- **ZFUT-02**: Configurable zoom levels in Settings (standalone app)
- **ZFUT-03**: Scroll wheel zoom (alternative to Z key)
- **ZFUT-04**: Color picker integration at zoom level

## Out of Scope

| Feature | Reason |
|---------|--------|
| Zoom beyond 4x | 4x is sufficient for pixel inspection; higher requires sub-pixel interpolation |
| Pinch-to-zoom (trackpad) | Gesture conflicts with macOS system zoom; Z key is sufficient |
| Zoom on standalone app Settings UI | Zoom is overlay-only; Settings is a standard SwiftUI window |
| Persistent zoom preference | Zoom should always start at 1x — consistent baseline per session |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ZOOM-01 | — | Pending |
| ZOOM-02 | — | Pending |
| ZOOM-03 | — | Pending |
| ZOOM-04 | — | Pending |
| ZOOM-05 | — | Pending |
| MEAS-01 | — | Pending |
| MEAS-02 | — | Pending |
| MEAS-03 | — | Pending |
| MEAS-04 | — | Pending |
| MEAS-05 | — | Pending |
| GUID-01 | — | Pending |
| GUID-02 | — | Pending |
| GUID-03 | — | Pending |
| GUID-04 | — | Pending |
| SHUX-01 | — | Pending |
| SHUX-02 | — | Pending |
| SHUX-03 | — | Pending |

**Coverage:**
- v2.1 requirements: 17 total
- Mapped to phases: 0
- Unmapped: 17 ⚠️

---
*Requirements defined: 2026-03-05*
*Last updated: 2026-03-05 after initial definition*
