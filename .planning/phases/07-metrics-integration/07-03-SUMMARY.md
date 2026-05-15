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
    - Termostato/Termostato/ContentView.swift
decisions:
  - "ContentView owns both @State VMs (vm + metrics); tab views receive them as parameters only — consistent with Plan 02 D-07 decision"
  - "scenePhase .active/.background drives both VM start/stop together (D-10) — no double-start possible due to existing guards in both VMs (T-07-07 mitigation verified)"
metrics:
  duration_minutes: 5
  completed_date: "2026-05-15"
  tasks_completed: 1
  tasks_total: 2
  files_created: 0
  files_modified: 1
---

# Phase 7 Plan 03: ContentView TabView Wiring Summary

**One-liner:** ContentView replaced from single-screen VStack to pure TabView container owning both TemperatureViewModel and MetricsViewModel, wiring all three tabs and both VM lifecycles; awaiting on-device human verification.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace ContentView with TabView container | 9ec23a1 | ContentView.swift |

## Task 2 Status

Task 2 is a `checkpoint:human-verify` gate. Automated work is complete. Human must build and install to physical iOS 18 device via Xcode to verify all 18 verification points (tab navigation, CPU live data, Memory live data, Thermal regression, background/foreground cycle).

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

## Deviations from Plan

None — Task 1 executed exactly as written. ContentView rewritten verbatim from plan's interface specification.

## Known Stubs

None. ContentView is a complete TabView container. All three tab views (ThermalView, CPUView, MemoryView) are fully implemented (confirmed in Plan 02 SUMMARY).

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes. ContentView is a pure UI wiring file. T-07-07 (double-start guard) and T-07-08 (stopPolling on background) mitigations are present in the implementation.

## Self-Check: PASSED

- `/Users/jgs/workspace/Termostato/Termostato/Termostato/ContentView.swift` — FOUND (52 lines, TabView implementation)
- Commit 9ec23a1 — Task 1: ContentView TabView wiring
