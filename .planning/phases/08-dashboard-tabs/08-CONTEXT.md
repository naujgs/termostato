# Phase 8: Dashboard Tabs - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 8 is a verification and close-out phase. Phase 7 already delivered the core TabView scaffold (ContentView, ThermalView, CPUView, MemoryView, MetricsViewModel) and satisfied SC1–SC4 from the ROADMAP success criteria. Phase 8's job:

1. Add `@State selectedTab` binding to ContentView and verify SC5 (tab selection persists — no data or scroll reset when switching tabs)
2. Run on-device UAT to confirm SC5 passes
3. Mark all 6 v1.2 requirements (CPU-01/02, MEM-01/02, DASH-01/02) as satisfied in REQUIREMENTS.md
4. Update ROADMAP and STATE.md to reflect v1.2 milestone complete
5. Capture Phase 9 seed in ROADMAP (Claude Design UI redesign — all 3 tabs)

Phase 9 (not in scope here) will implement the Claude Design mockups — a full visual redesign of all three tabs (Thermal, CPU, Memory).

</domain>

<decisions>
## Implementation Decisions

### Phase Scope

- **D-01:** Phase 8 is a verification + close-out phase, not a feature phase. Phase 7 delivered SC1–SC4 ahead of schedule (ROADMAP D-03). Phase 8 closes the loop.
- **D-02:** Claude Design mockup implementation is deferred to Phase 9. All 3 tabs (Thermal, CPU, Memory) will be redesigned there.

### Tab Persistence (SC5)

- **D-03:** Add `@State private var selectedTab: Int = 0` to ContentView and bind it to `TabView(selection: $selectedTab)`. This makes selection explicit and observable rather than implicit SwiftUI state, simplifying UAT verification.
- **D-04:** SC5 verification is on-device UAT: switch away from each tab and back, confirm metric values do not reset to "—" and no data loss occurs. Current views have no ScrollView so scroll position is not a concern.

### Requirements Cleanup

- **D-05:** REQUIREMENTS.md gets all 6 v1.2 requirements ticked as satisfied (`[x]`). Traceability table updated: CPU-01/02 → Phase 7, MEM-01/02 → Phase 7, DASH-01/02 → Phase 7 (with note that ROADMAP Phase 7 SC4 is authoritative). Status column: all → Satisfied.
- **D-06:** PROJECT.md Key Decisions table and Validated requirements section are updated to reflect Phase 8 close-out.
- **D-07:** ROADMAP.md Phase 8 plans list updated with actual plan count. Progress table updated: Phase 8 → Complete.

### Claude's Discretion

- Exact `selectedTab` integer values for each tab (0 = Thermal, 1 = CPU, 2 = Memory — standard)
- Whether to add a `TabView` `.tag()` modifier or leave implicit ordering
- Commit message wording for documentation updates

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core Source Files (Phase 7 output)
- `Termostato/Termostato/ContentView.swift` — Current TabView container (54 lines). D-03 adds `@State selectedTab` here.
- `Termostato/Termostato/CPUView.swift` — CPU tab view + MetricCardView component.
- `Termostato/Termostato/MemoryView.swift` — Memory tab view.
- `Termostato/Termostato/ThermalView.swift` — Thermal tab view.
- `Termostato/Termostato/MetricsViewModel.swift` — Mach API polling ViewModel.

### Planning Artifacts
- `.planning/REQUIREMENTS.md` — D-05: all 6 v1.2 requirements need `[x]` marks + traceability update.
- `.planning/ROADMAP.md` — Phase 7 SC4 note (D-03 decision that DASH-01/02 satisfied in Phase 7). Phase 8 progress table update.
- `.planning/PROJECT.md` — Validated requirements section and Key Decisions table updates.
- `.planning/STATE.md` — Session continuity update.
- `.planning/phases/07-metrics-integration/07-VERIFICATION.md` — Evidence for all 6 requirement satisfactions (used to justify REQUIREMENTS.md tick-off).
- `.planning/phases/07-metrics-integration/07-CONTEXT.md` — Prior phase decisions (D-01 through D-15).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ContentView.swift` TabView body — D-03 only adds `@State selectedTab` binding; existing structure unchanged
- `MetricCardView` in CPUView.swift — shared reusable card component, no changes needed in Phase 8

### Established Patterns
- `@Observable @MainActor final class` — ViewModels. No changes to ViewModels in Phase 8.
- `@State private var` for ViewModel ownership in ContentView — `vm` and `metrics` are already `@State`, `selectedTab` follows the same pattern.
- `print("[Termostato] ...")` — logging prefix (no new logging needed in Phase 8)

### Integration Points
- `ContentView.body` — sole change: `TabView` → `TabView(selection: $selectedTab)` + `@State private var selectedTab: Int = 0`
- No new files needed for Phase 8

</code_context>

<specifics>
## Specific Ideas

- Phase 9 will implement Claude Design mockups — a full visual redesign of all 3 tabs (Thermal, CPU, Memory). Researcher for Phase 9 should prompt the user to share the Claude Design artifacts at that time.
- SC5 UAT: switching between the 3 tabs while the app is polling — metric cards should hold their last-read values, not flash back to "—".

</specifics>

<deferred>
## Deferred Ideas

- **Phase 9: Claude Design UI Redesign** — Full visual redesign of all 3 tabs (Thermal, CPU, Memory) using Claude Design mockups. Scope confirmed: all 3 tabs. Not in Phase 8.
- Rolling history charts for CPU/Memory — deferred to v1.3+ (CPU-03, MEM-03)
- Battery display — deferred to v1.3+ (BATT-01, BATT-02)

</deferred>

---

*Phase: 08-dashboard-tabs*
*Context gathered: 2026-05-15*
