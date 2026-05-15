---
phase: 07-metrics-integration
plan: "01"
subsystem: data-layer
tags: [metrics, mach-api, viewmodel, polling, swift6]
dependency_graph:
  requires: []
  provides: [MetricsViewModel, stub-view-files]
  affects: [07-02-PLAN, 07-03-PLAN]
tech_stack:
  added: []
  patterns: [Task.detached+MainActor.run, nonisolated(unsafe)-mach-state, vm_deallocate-defer]
key_files:
  created:
    - Termostato/Termostato/MetricsViewModel.swift
    - Termostato/Termostato/ThermalView.swift
    - Termostato/Termostato/CPUView.swift
    - Termostato/Termostato/MemoryView.swift
  modified:
    - Termostato/Termostato.xcodeproj/project.pbxproj
    - Termostato/Termostato/TemperatureViewModel.swift
decisions:
  - "vm_kernel_page_size replaced with literal 16384 — Swift 6 strict concurrency treats the Darwin global as shared mutable state; literal is correct for arm64 iOS"
  - "Stub view files (ThermalView, CPUView, MemoryView) created to unblock build — registered in pbxproj but bodies implemented in Plan 02"
metrics:
  duration_minutes: 25
  completed_date: "2026-05-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 2
---

# Phase 7 Plan 01: MetricsViewModel and pbxproj Registration Summary

**One-liner:** MetricsViewModel with four nonisolated Mach calls (task_threads, task_info, host_statistics, host_statistics64) polling every 5s via Task.detached, plus all four new Swift files registered in project.pbxproj.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Register 4 new Swift files in project.pbxproj | ca2870f | project.pbxproj |
| 2 | Create MetricsViewModel.swift and reduce TemperatureViewModel to 5s | c0ca77f | MetricsViewModel.swift, TemperatureViewModel.swift, ThermalView.swift, CPUView.swift, MemoryView.swift |

## Verification Results

All acceptance criteria passed:

- `grep "MetricsViewModel.swift in Sources" project.pbxproj` — 1 match (PBXBuildFile) + 1 match (PBXSourcesBuildPhase) = 2 total
- `grep "ThermalView.swift in Sources" project.pbxproj` — 2 matches
- `grep "CPUView.swift in Sources" project.pbxproj` — 2 matches
- `grep "MemoryView.swift in Sources" project.pbxproj` — 2 matches
- `grep "every: 5" TemperatureViewModel.swift` — 1 match (line 111 updated)
- `grep "every: 10" TemperatureViewModel.swift` — 0 matches
- `grep "Task.detached" MetricsViewModel.swift` — 1 match in startPolling()
- `grep "nonisolated(unsafe).*previousCPUTicks" MetricsViewModel.swift` — 1 match
- `grep "vm_deallocate" MetricsViewModel.swift` — 1 match in defer block of readAppCPU
- `grep "await MainActor.run" MetricsViewModel.swift` — 1 match in tick()
- All 5 private(set) properties present (appCPUPercent, appMemoryMB, sysCPUPercent, sysMemoryFreeGB, sysMemoryUsedGB)
- xcodebuild: BUILD SUCCEEDED, 0 errors

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Stub view files created to unblock build**
- **Found during:** Task 2 (first build attempt)
- **Issue:** ThermalView.swift, CPUView.swift, MemoryView.swift were registered in pbxproj (Task 1) but the build system required their physical existence to compile. xcodebuild reported "Build input files cannot be found" for all three.
- **Fix:** Created minimal SwiftUI stub files (each ~8 lines: `struct FooView: View { var body: some View { Text("...") } }`) so the build succeeds. Plan 02 replaces these with full implementations.
- **Files modified:** ThermalView.swift (created), CPUView.swift (created), MemoryView.swift (created)
- **Commit:** c0ca77f

**2. [Rule 1 - Bug] vm_kernel_page_size replaced with literal 16384**
- **Found during:** Task 2 (second build attempt after stubs added)
- **Issue:** `vm_kernel_page_size` is a Darwin C global that Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) flags as "reference to var is not concurrency-safe because it involves shared mutable state" — even inside a `nonisolated` method.
- **Fix:** Replaced `Double(vm_kernel_page_size)` with `let pageSize: Double = 16384`. This is the documented assumption A1 fallback in the plan. iOS arm64 uses 16 KB pages; the literal is correct and runtime-safe.
- **Files modified:** MetricsViewModel.swift (line ~179)
- **Commit:** c0ca77f

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| `Text("Thermal")` | ThermalView.swift | 7 | Placeholder body — full TabView card implemented in Plan 02 |
| `Text("CPU")` | CPUView.swift | 7 | Placeholder body — full CPU metrics card implemented in Plan 02 |
| `Text("Memory")` | MemoryView.swift | 7 | Placeholder body — full memory metrics card implemented in Plan 02 |

These stubs are intentional and tracked. Plan 02 (07-02-PLAN.md) replaces all three with full SwiftUI views consuming MetricsViewModel.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes were introduced. All data flows are device-local Mach kernel reads — same trust boundary as SystemMetrics.swift (Phase 6). T-07-01 (vm_deallocate defer) and T-07-02 (pollingTask cancel) mitigations are present in the implementation.

## Self-Check: PASSED

- `/Users/jgs/workspace/Termostato/Termostato/Termostato/MetricsViewModel.swift` — FOUND
- `/Users/jgs/workspace/Termostato/Termostato/Termostato/ThermalView.swift` — FOUND
- `/Users/jgs/workspace/Termostato/Termostato/Termostato/CPUView.swift` — FOUND
- `/Users/jgs/workspace/Termostato/Termostato/Termostato/MemoryView.swift` — FOUND
- Commit ca2870f — FOUND (Task 1: pbxproj registrations)
- Commit c0ca77f — FOUND (Task 2: MetricsViewModel + stubs + TemperatureViewModel)
