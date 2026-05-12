# Phase 2: Dashboard UI - Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the foreground dashboard UI on top of the confirmed Phase 1 data pipeline. Delivers:
- DISP-01: Current thermal state displayed prominently with color coding per level
- DISP-02: Session-length step-chart of thermal state changes since app opened

This phase does NOT wire notifications — that is Phase 3.

</domain>

<decisions>
## Implementation Decisions

### Screen Layout
- **D-01:** Large pill/card badge at the top half of the screen. Full-width rounded rectangle with a color fill and the state name in large text. The badge must be glanceable — state visible before the user fully reads it.
- **D-02:** Step-chart fills the lower portion of the screen, below the badge. Badge dominates the upper area; chart is secondary but always visible.

### History Chart
- **D-03:** Chart type is a step-chart (discrete state levels, not a smooth line). Required by ROADMAP DISP-02.
- **D-04:** The chart is not scrollable — it always shows the full session window within its bounds. Old data shifts off the left edge as new readings arrive.

### Ring Buffer
- **D-05:** Fixed-capacity ring buffer of **120 readings** (~60 minutes of history at the 30s polling interval). This is the maximum retained in memory for the chart. When capacity is reached, oldest entries are evicted.
- **D-06:** The ring buffer is session-only — it resets to empty when the app is cold-launched. No persistence.

### Visual Theme
- **D-07:** App follows **system appearance** — standard iOS light/dark mode. Do NOT force dark mode. Color coding for thermal states uses the four defined colors (green / yellow / orange / red) that must read clearly in both light and dark.

### Color Coding (DISP-01 requirement)
- **D-08:** Four distinct colors for the four thermal levels:
  - Nominal → green
  - Fair → yellow
  - Serious → orange
  - Critical → red
  These are applied to both the badge fill and the chart line/area.

### Claude's Discretion
- Chart Y-axis labels — whether to show state names (Nominal/Fair/Serious/Critical) on the Y-axis or just color bands. Claude picks based on Swift Charts readability.
- Chart X-axis — whether to show a time axis or omit it. Claude picks based on chart density at 120-point capacity.
- Exact typography, padding, and spacing — standard SwiftUI defaults are fine; Claude can refine for legibility.
- Animation behavior on new data points — Claude decides whether to animate chart updates.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Requirements
- `.planning/REQUIREMENTS.md` — DISP-01 and DISP-02 requirements for this phase; out-of-scope list (no persistent storage, no numeric °C)
- `.planning/ROADMAP.md` — Phase 2 success criteria (4 items that must be TRUE); "UI hint: yes"

### Architecture & Stack
- `CLAUDE.md` (project) — Full tech stack table; Swift Charts guidance (LineMark / step chart); SwiftUI-only constraint; iOS 18+ target

### Prior Phase Context
- `.planning/phases/01-foundation-device-validation/01-CONTEXT.md` — D-03 establishes TemperatureViewModel as the real ViewModel Phase 2 extends (history array added, not a rewrite); D-04/D-05 polling interval and lifecycle pattern

### Existing Source Files
- `Termostato/Termostato/TemperatureViewModel.swift` — Add history array here. Phase 2 extends this file.
- `Termostato/Termostato/ContentView.swift` — Phase 1 placeholder. Phase 2 replaces the body entirely with the dashboard layout.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TemperatureViewModel` (`@Observable`, `@MainActor`) — add `private(set) var history: [ThermalReading]` (or similar struct) here; `updateThermalState()` appends to it and enforces the 120-entry cap.
- `thermalStateLabel` helper in ContentView — can be moved to ViewModel or kept as a View helper.

### Established Patterns
- `@Observable` + `@MainActor` on the ViewModel — enforced by Swift 6.3 strict concurrency; all history mutations must happen on the main actor.
- `scenePhase` observer pattern (ContentView) — unchanged; Phase 2 adds to the view body but keeps the existing lifecycle hooks.
- `print()` for console logging — Phase 1 used this; Phase 2 can retain or switch to OSLog.

### Integration Points
- `TemperatureViewModel.updateThermalState()` — append to history array here, right after updating `thermalState`.
- `ContentView.body` — replace VStack placeholder with dashboard layout (badge + chart).
- Phase 3 will add `thermalStateDidChangeNotification` observer and notification triggering to the ViewModel; Phase 2 should leave extension points clean.

</code_context>

<specifics>
## Specific Ideas

- The badge should be impossible to misread at a glance: large text, strong color fill, full-width presence.
- Color coding (green/yellow/orange/red) applies to both badge and chart for visual consistency.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-dashboard-ui*
*Context gathered: 2026-05-12*
