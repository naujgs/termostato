---
phase: 07-metrics-integration
plan: "03"
subsystem: ui-wiring
tags: [tabview, swiftui, wiring, lifecycle, checkpoint]
dependency_graph:
  requires: [07-01, 07-02]
  provides: [ContentView-TabView, dual-vm-lifecycle]
  affects: []
tech_stack:
  added: []
  patterns: [tabview-container, dual-viewmodel-scenePhase-lifecycle]
key_files:
  created: []
  modified:
    - CoreWatch/CoreWatch/ContentView.swift
decisions:
  - "ContentView owns both @State VMs (vm + metrics); tab views receive them as parameters only — consistent with Plan 02 D-07 decision"
  - "scenePhase .active/.background drives both VM start/stop together (D-10) — no double-start possible due to existing guards in both VMs (T-07-07 mitigation verified)"
metrics:
  duration_minutes: 30
  completed_date: "2026-05-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 4
---

# Phase 7 Plan 03: ContentView TabView Wiring Summary

**One-liner:** ContentView replaced from single-screen VStack to pure TabView container owning both TemperatureViewModel and MetricsViewModel, wiring all three tabs and both VM lifecycles; all 18 on-device verification points passed.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace ContentView with TabView container | 9ec23a1 | ContentView.swift |
| bonus | Add localized tooltips to metric cards and thermal badge | d6b1d2d | CPUView.swift, MemoryView.swift, ThermalView.swift |
| 2 | On-device verification — all 3 tabs display live data, Thermal tab regression-free | (checkpoint) | — |

## Task 2 Status

Task 2 (`checkpoint:human-verify`) is complete. User deployed to physical iOS 18 device via Xcode and confirmed all 18 verification points passed ("approved").

## Verification Results

All Task 1 acceptance criteria passed:

- `grep "TabView" ContentView.swift` — structural TabView block present (line 15)
- `grep "ThermalView(viewModel: vm)"` — 1 match
- `grep "CPUView(metrics: metrics)"` — 1 match
- `grep "MemoryView(metrics: metrics)"` — 1 match
- `grep "metrics.startPolling"` — 2 matches (onAppear + .active case)
- `grep "metrics.stopPolling"` — 1 match (.background case)
- `grep "badgeColor\|badgeTextColor\|thermalStateLabel\|showDebugSheet\|VStack"` — 0 matches
- xcodebuild: BUILD SUCCEEDED, 0 errors

All 18 Task 2 on-device verification points passed (user sign-off: "approved"):
- Tab navigation (points 1-5): all three tabs visible and navigable
- CPU tab (points 6-8): App CPU non-zero after 5s, System CPU non-zero after 10s, values update every ~5s
- Memory tab (points 9-11): App Memory ~79 MB, Memory Free and Memory Used show non-zero GB values
- Thermal tab regression (points 12-15): badge, chart, long-press debug sheet all functional
- Background/foreground cycle (points 16-18): polling resumes within 5s, console log confirmed

## Deviations from Plan

### Bonus Addition

**[Bonus - Enhancement] Add localized tooltips to metric cards and thermal badge**
- **Found during:** Post-Task 1, pre-checkpoint
- **Issue:** Metric cards lacked contextual labels to help users understand what each value represents
- **Fix:** Added `.help()` tooltip modifiers to all metric cards in CPUView, MemoryView, and the thermal badge in ThermalView with localized strings
- **Files modified:** CoreWatch/CoreWatch/CPUView.swift, CoreWatch/CoreWatch/MemoryView.swift, CoreWatch/CoreWatch/ThermalView.swift
- **Commit:** d6b1d2d

## Known Stubs

None. ContentView is a complete TabView container. All three tab views (ThermalView, CPUView, MemoryView) are fully implemented (confirmed in Plan 02 SUMMARY).

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes. ContentView is a pure UI wiring file. T-07-07 (double-start guard) and T-07-08 (stopPolling on background) mitigations are present in the implementation.

## Self-Check: PASSED

- `/Users/jgs/workspace/CoreWatch/CoreWatch/CoreWatch/ContentView.swift` — FOUND (52 lines, TabView implementation)
- Commit 9ec23a1 — Task 1: ContentView TabView wiring
- Commit d6b1d2d — Bonus: localized tooltips on metric cards and thermal badge
- Task 2: on-device verification complete, all 18 points approved by user
