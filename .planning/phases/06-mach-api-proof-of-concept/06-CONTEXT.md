# Phase 6: Mach API Proof-of-Concept - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Determine which Mach system APIs (`host_statistics`, `host_statistics64`, `task_info`) return valid data on iOS 18 under free Apple ID sideload. This is a validation phase — build minimal probe code, run on a physical device, and produce a per-API verdict document that Phase 7 consumes to decide what to integrate.

</domain>

<decisions>
## Implementation Decisions

### Probe Architecture
- **D-01:** Create a separate `SystemMetrics.swift` file for all Mach API probe code. Do not extend TemperatureViewModel — keep probe logic isolated from shipped thermal code.
- **D-02:** Probe all three APIs in one pass: `host_statistics` (system CPU), `host_statistics64` (system memory), and `task_info` (per-process CPU/memory). This covers everything Phase 7 might need.

### C Bridge Approach
- **D-03:** Claude's Discretion — choose the best engineering approach (Swift-only via `withUnsafeMutablePointer` or bridging header with C wrapper) based on conventions and scalability. User wants the most maintainable, scalable solution.

### On-Device Reporting
- **D-04:** Add a temporary debug screen as a SwiftUI `.sheet()` overlay showing per-API status (accessible/degraded/blocked with color coding). Thermal dashboard stays intact underneath.
- **D-05:** The debug sheet is triggered by a hidden gesture or button — it is throwaway UI for Phase 6 validation only.

### Verdict Criteria
- **D-06:** Use three-tier classification: **Accessible** (KERN_SUCCESS + non-zero plausible data), **Degraded** (KERN_SUCCESS but zeroed or stale data), **Blocked** (KERN_FAILURE or other error code).
- **D-07:** Take 3 samples per API over 30 seconds (10s spacing, matching the existing polling interval). Final verdict = majority result across the 3 samples.

### Documentation Output
- **D-08:** Write a structured verdict report as `06-VERDICTS.md` in the phase directory (`.planning/phases/06-mach-api-proof-of-concept/`). Phase 7 planner reads this to know which APIs to wire up.
- **D-09:** Include raw evidence alongside each verdict: `kern_return_t` codes, actual sample data values, and timestamps. Not just the final classification.

### Claude's Discretion
- Internal structure of SystemMetrics.swift (method signatures, return types, error handling patterns)
- Debug sheet layout and visual design (as long as it shows per-API status clearly)
- How the 3-sample probe sequence is triggered (automatic on sheet open, manual button, etc.)
- Console logging format and verbosity

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Context
- `CLAUDE.md` — Tech stack (Swift 6.3, SwiftUI, Xcode 26.4.1), private API constraints, IOKit background
- `.planning/PROJECT.md` — Key decisions table, IOKit blocked confirmation, current architecture
- `.planning/REQUIREMENTS.md` — CPU-02 and MEM-02 requirement definitions, graceful fallback constraint

### Existing Code
- `CoreWatch/CoreWatch/TemperatureViewModel.swift` — Current ViewModel pattern (@Observable, @MainActor, polling timer, ring buffer)
- `CoreWatch/CoreWatch/ContentView.swift` — Current SwiftUI view structure, .sheet() integration point

### Phase Dependencies
- `.planning/ROADMAP.md` §Phase 6 — Success criteria, depends on Phase 5, requirement mapping

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TemperatureViewModel`: Established `@Observable @MainActor` pattern with `Timer.publish` polling — SystemMetrics can follow the same concurrency model
- `ContentView`: Single VStack layout with `.onChange(of: scenePhase)` lifecycle — `.sheet()` modifier integrates naturally here

### Established Patterns
- **Polling**: 10s `Timer.publish` interval with `startPolling()`/`stopPolling()` lifecycle
- **Concurrency**: `@MainActor` isolation on ViewModel, `Task { @MainActor in }` for async work
- **State observation**: `@Observable` macro with `private(set)` published properties
- **Console logging**: `print("[CoreWatch] ...")` format for debug output

### Integration Points
- `ContentView.body` — Add `.sheet()` modifier for debug overlay
- New `SystemMetrics.swift` file in same directory as TemperatureViewModel.swift
- Bridging header (if C wrapper approach chosen) at project root level

</code_context>

<specifics>
## Specific Ideas

- The 3-sample probe at 10s intervals aligns with the existing polling cadence, making it easy to reuse the timing pattern
- Debug sheet should show color-coded status per API (green/yellow/red mapping to accessible/degraded/blocked)
- Verdict document must be detailed enough that Phase 7 planner can make go/no-go decisions per API without re-running the probe

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-mach-api-proof-of-concept*
*Context gathered: 2026-05-15*
