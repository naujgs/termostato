# Phase 1: Foundation & Device Validation - Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove the thermal data pipeline on the physical device under free Apple ID signing. No UI beyond what is needed to validate behavior. Deliver: the real `TemperatureViewModel` (`@Observable`, `@MainActor`) with `ProcessInfo.thermalState` polling wired to a 30-second `Timer`, scenePhase lifecycle observer that cancels/recreates the timer on background/foreground transitions, a minimal IOKit probe that runs once on-device to produce the definitive blocked/not-blocked decision record, and a written decision record.

This phase does NOT build the dashboard UI — that is Phase 2.

</domain>

<decisions>
## Implementation Decisions

### IOKit Probe
- **D-01:** Include a minimal IOKit probe (~5 lines) that attempts to read the temperature key on the physical device. The probe runs once on launch, logs its result to console, then the decision record is written from real observed data.
- **D-02:** The IOKit probe code is **removed after Phase 1** once the decision record is captured. Phase 2 starts clean with no dead IOKit code. No `#if DEBUG` gate — just delete it.

### Architecture (Code Reuse Intent)
- **D-03:** Phase 1 creates the **real `TemperatureViewModel`** (`@Observable`, `@MainActor`) that Phase 2 extends — not a throwaway spike. The ViewModel stub includes: `thermalState: ProcessInfo.ThermalState`, a `Timer`-based polling mechanism, and scenePhase wiring. Phase 2 adds the history array and chart data; Phase 3 adds notification triggering. No rewrite between phases.

### Polling Interval
- **D-04:** Poll `ProcessInfo.thermalState` every **30 seconds** while foregrounded. Thermal state changes on the order of minutes; 30s is conservative, battery-friendly, and sets the Phase 2 chart update cadence.
- **D-05:** Polling is foreground-only. When backgrounded, the timer is cancelled. Background thermal escalation is handled in Phase 3 via `thermalStateDidChangeNotification` (event-driven, not polling).

### ScenePhase Lifecycle
- **D-06:** Use SwiftUI `@Environment(\.scenePhase)` + `.onChange(of:)` in the root View to detect foreground/background transitions. No UIKit lifecycle hooks.
- **D-07:** On `.background`: cancel the `Timer` (invalidate). On `.active`: create a new `Timer`. Cancel-and-recreate pattern — no stored mutable timer reference across state transitions.

### Claude's Discretion
- Bridging header setup for IOKit (if needed) — Claude decides approach
- Console logging format for Phase 1 validation output — `print()` is fine for a spike; OSLog can wait for Phase 2
- Xcode project settings (bundle ID format, display name, signing team) — use `com.{user}.CoreWatch` convention

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Requirements
- `.planning/REQUIREMENTS.md` — Definitive requirement list for v1; confirms IOKit is Out of Scope, Phase 1 maps to INST-01
- `.planning/ROADMAP.md` — Phase 1 success criteria (4 items that must be TRUE); phase dependencies

### Architecture & Stack
- `CLAUDE.md` (project) — Full tech stack table (Xcode 26.4.1, Swift 6.3, iOS 18+ target, SwiftUI only), IOKit entitlement analysis, private API tier summary, sideloading mechanics

### Key External Decisions
No external ADRs. All constraints captured in REQUIREMENTS.md and CLAUDE.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project. No existing Swift files.

### Established Patterns
- None yet. Phase 1 establishes the first patterns: `@Observable` ViewModel, `@MainActor` enforcement, SwiftUI `scenePhase` lifecycle.

### Integration Points
- `TemperatureViewModel` (created in Phase 1) → extended in Phase 2 with history array and chart data
- `scenePhase` observer (created in Phase 1) → Phase 3 adds `thermalStateDidChangeNotification` observer alongside it

</code_context>

<specifics>
## Specific Ideas

- The IOKit probe should log whether the key returns a value or silently returns nil/error — this exact log output becomes the decision record for success criterion #3
- Phase 1's ViewModel need not be complete — just enough to validate: `thermalState` property updated on each timer tick, logged to console

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-foundation-device-validation*
*Context gathered: 2026-05-12*
