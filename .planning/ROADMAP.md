# Roadmap: Design Ruler

## Milestones

- ✅ **v1.0 Enhancement** — Phases 1-5 (shipped 2026-02-13)
- ✅ **v1.1 Hint Bar Redesign** — Phases 6-8 (shipped 2026-02-14)
- ✅ **v1.2 Alignment Guides** — Phases 9-11 (shipped 2026-02-16)
- ✅ **v1.3 Code Unification** — Phases 12-17 (shipped 2026-02-17)
- ✅ **v2.0 Standalone App** — Phases 18-23 (shipped 2026-02-20)
- 🚧 **v2.1 Zoom** — Phases 24-27 (in progress)

## Phases

<details>
<summary>✅ v1.0 Enhancement (Phases 1-5) — SHIPPED 2026-02-13</summary>

- [x] Phase 1: Debug Cleanup and Process Safety (1/1 plans) — completed 2026-02-13
- [x] Phase 2: Cursor State Machine (1/1 plans) — completed 2026-02-13
- [x] Phase 3: Snap Failure Shake (1/1 plans) — completed 2026-02-13
- [x] Phase 4: Selection Pill Clamping (1/1 plans) — completed 2026-02-13
- [x] Phase 5: Help Toggle System (1/1 plans) — completed 2026-02-13

</details>

<details>
<summary>✅ v1.1 Hint Bar Redesign (Phases 6-8) — SHIPPED 2026-02-14</summary>

- [x] Phase 6: Remove Help Toggle System (1/1 plans) — completed 2026-02-14
- [x] Phase 7: Hint Bar Visual Redesign (2/2 plans) — completed 2026-02-14
- [x] Phase 8: Launch-to-Collapse Animation (1/1 plans) — completed 2026-02-14

</details>

<details>
<summary>✅ v1.2 Alignment Guides (Phases 9-11) — SHIPPED 2026-02-16</summary>

- [x] Phase 9: Scaffold + Preview Line + Placement (1/1 plans) — completed 2026-02-16
- [x] Phase 10: Remove Interaction + Color System (2/2 plans) — completed 2026-02-16
- [x] Phase 11: Hint Bar + Multi-Monitor + Polish (6/6 plans) — completed 2026-02-16

</details>

<details>
<summary>✅ v1.3 Code Unification (Phases 12-17) — SHIPPED 2026-02-17</summary>

- [x] Phase 12: Leaf Utilities (2/2 plans) — completed 2026-02-16
- [x] Phase 13: Rendering Unification (2/2 plans) — completed 2026-02-16
- [x] Phase 14: Coordinator Base (2/2 plans) — completed 2026-02-17
- [x] Phase 15: Window Base + Cursor (2/2 plans) — completed 2026-02-17
- [x] Phase 16: Final Cleanup (1/1 plan) — completed 2026-02-17
- [x] Phase 17: Unified cursor manager fixes (1/1 plan) — completed 2026-02-17

</details>

<details>
<summary>✅ v2.0 Standalone App (Phases 18-23) — SHIPPED 2026-02-20</summary>

- [x] Phase 18: Build System (2/2 plans) — completed 2026-02-18
- [x] Phase 19: App Lifecycle Refactor (2/2 plans) — completed 2026-02-18
- [x] Phase 20: Menu Bar Shell (1/1 plan) — completed 2026-02-18
- [x] Phase 21: Settings and Preferences (3/3 plans) — completed 2026-02-19
- [x] Phase 22: Global Hotkeys (3/3 plans) — completed 2026-02-19
- [x] Phase 23: Distribution (3/3 plans) — completed 2026-02-20

</details>

### v2.1 Zoom (In Progress)

**Milestone Goal:** Add full-screen zoom to both Measure and Alignment Guides, cycling through 2x, 4x, 1x on Z key press, with fully functional crosshair, edge detection, and guide interaction at every zoom level.

- [x] **Phase 24: Zoom Transform Infrastructure** - Z key zoom cycle with animated transform and cursor-following pan in OverlayWindow base
- [x] **Phase 25: Measure Zoom Integration** - Edge detection, crosshair, dimensions, arrow keys, and drag-to-select all working correctly at 2x and 4x (completed 2026-03-06)
- [ ] **Phase 26: Guides Zoom Integration** - Preview line, placement, hover-remove, and existing guide rendering all working correctly while zoomed
- [ ] **Phase 27: Zoom UX Polish** - Zoom level indicator, hint bar Z key shortcut, and session reset

## Phase Details

### Phase 24: Zoom Transform Infrastructure
**Goal**: User can zoom the overlay to 2x and 4x centered on cursor, with smooth animation and view panning that follows cursor movement
**Depends on**: Phase 23 (v2.0 complete)
**Requirements**: ZOOM-01, ZOOM-02, ZOOM-03, ZOOM-04, SHUX-02, SHUX-03
**Success Criteria** (what must be TRUE):
  1. User presses Z and the overlay smoothly animates to 2x zoom centered on the cursor position
  2. User presses Z again and the overlay smoothly animates to 4x, then back to 1x on the third press
  3. User moves the mouse while zoomed and the view pans to keep the cursor visible (no clipping at edges)
  4. Each monitor maintains its own independent zoom level when using multiple screens
  5. Zoom resets to 1x when the user presses ESC to exit the session
**Plans**: 2 plans
Plans:
- [x] 24-01-PLAN.md -- ZoomState model, coordinate mapping, design tokens
- [x] 24-02-PLAN.md -- OverlayWindow zoom integration, coordinator reset

### Phase 25: Measure Zoom Integration
**Goal**: Edge detection, crosshair rendering, dimension readout, arrow key skipping, and drag-to-select all produce correct results at any zoom level
**Depends on**: Phase 24
**Requirements**: MEAS-01, MEAS-02, MEAS-03, MEAS-04, MEAS-05
**Success Criteria** (what must be TRUE):
  1. Crosshair lines extend to correct detected edges at 2x and 4x (edge detection reads the original pixel buffer, not the zoomed view)
  2. W x H dimension pill shows accurate point values regardless of zoom level (same values as at 1x for the same cursor position)
  3. Arrow key edge skipping advances to the next edge correctly while zoomed
  4. User can drag-to-select a region while zoomed and the selection snaps to edges with correct screen coordinates
  5. Dimension pill text remains readable and correctly positioned (not scaled up with the zoom)
**Plans**: 2 plans
Plans:
- [x] 25-01-PLAN.md -- Core coordinate conversion + zoom-aware selection
- [x] 25-02-PLAN.md -- Arrow key peek pan animation

### Phase 26: Guides Zoom Integration
**Goal**: Preview line, click placement, hover-to-remove, and existing guide line rendering all work correctly at any zoom level
**Depends on**: Phase 24
**Requirements**: GUID-01, GUID-02, GUID-03, GUID-04
**Success Criteria** (what must be TRUE):
  1. Preview line follows cursor at the correct screen coordinate while zoomed (not offset by the zoom transform)
  2. Clicking while zoomed places a guide line at the correct screen position (same coordinate as if placed at 1x)
  3. Hover-to-remove hit testing works at the correct screen coordinates while zoomed (5px threshold in screen space, not zoomed space)
  4. When zoom level changes, all existing placed guide lines render at their correct positions without shifting
**Plans**: 1 plan
Plans:
- [ ] 26-01-PLAN.md -- Zoom-aware guide line storage, rendering, and hit testing

### Phase 27: Zoom UX Polish
**Goal**: User has clear visual feedback about the current zoom level and hint bar teaches the Z key shortcut
**Depends on**: Phase 24, Phase 25, Phase 26
**Requirements**: ZOOM-05, SHUX-01
**Success Criteria** (what must be TRUE):
  1. A zoom level indicator (showing "2x" or "4x") is visible on screen when zoomed, and hidden at 1x
  2. Hint bar includes the Z key with "Zoom" label in both Measure and Alignment Guides modes
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 24 -> 25 -> 26 -> 27
(Phases 25 and 26 could execute in parallel since both depend only on 24, but sequential is simpler for a solo workflow.)

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Debug Cleanup | v1.0 | 1/1 | Complete | 2026-02-13 |
| 2. Cursor State Machine | v1.0 | 1/1 | Complete | 2026-02-13 |
| 3. Snap Failure Shake | v1.0 | 1/1 | Complete | 2026-02-13 |
| 4. Selection Pill Clamping | v1.0 | 1/1 | Complete | 2026-02-13 |
| 5. Help Toggle System | v1.0 | 1/1 | Complete | 2026-02-13 |
| 6. Remove Help Toggle | v1.1 | 1/1 | Complete | 2026-02-14 |
| 7. Hint Bar Redesign | v1.1 | 2/2 | Complete | 2026-02-14 |
| 8. Launch-to-Collapse | v1.1 | 1/1 | Complete | 2026-02-14 |
| 9. Scaffold + Preview | v1.2 | 1/1 | Complete | 2026-02-16 |
| 10. Remove + Color | v1.2 | 2/2 | Complete | 2026-02-16 |
| 11. Hint Bar + Polish | v1.2 | 6/6 | Complete | 2026-02-16 |
| 12. Leaf Utilities | v1.3 | 2/2 | Complete | 2026-02-16 |
| 13. Rendering Unification | v1.3 | 2/2 | Complete | 2026-02-16 |
| 14. Coordinator Base | v1.3 | 2/2 | Complete | 2026-02-17 |
| 15. Window Base + Cursor | v1.3 | 2/2 | Complete | 2026-02-17 |
| 16. Final Cleanup | v1.3 | 1/1 | Complete | 2026-02-17 |
| 17. Cursor Manager Fixes | v1.3 | 1/1 | Complete | 2026-02-17 |
| 18. Build System | v2.0 | 2/2 | Complete | 2026-02-18 |
| 19. App Lifecycle | v2.0 | 2/2 | Complete | 2026-02-18 |
| 20. Menu Bar Shell | v2.0 | 1/1 | Complete | 2026-02-18 |
| 21. Settings & Prefs | v2.0 | 3/3 | Complete | 2026-02-19 |
| 22. Global Hotkeys | v2.0 | 3/3 | Complete | 2026-02-19 |
| 23. Distribution | v2.0 | 3/3 | Complete | 2026-02-20 |
| 24. Zoom Transform | v2.1 | Complete    | 2026-03-05 | 2026-03-05 |
| 25. Measure Zoom | 2/2 | Complete    | 2026-03-06 | - |
| 26. Guides Zoom | v2.1 | 0/1 | Not started | - |
| 27. Zoom UX Polish | v2.1 | 0/? | Not started | - |
