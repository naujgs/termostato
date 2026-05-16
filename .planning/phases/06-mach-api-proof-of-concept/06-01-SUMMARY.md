---
phase: 06-mach-api-proof-of-concept
plan: 01
subsystem: system-metrics-probe
tags: [mach-api, probe, debug-ui, swiftui, ios]
dependency_graph:
  requires: []
  provides: [SystemMetricsProbe, MachProbeDebugView, debug-sheet-trigger]
  affects: [ContentView]
tech_stack:
  added: []
  patterns:
    - "@Observable @MainActor class following TemperatureViewModel pattern"
    - "withUnsafeMutablePointer + withMemoryRebound for Mach C API calls in Swift"
    - "defer block for vm_deallocate after task_threads to prevent mach port leak"
    - "MemoryLayout<T>.size / MemoryLayout<natural_t>.size for Mach struct count (C macros don't bridge to Swift)"
key_files:
  created:
    - CoreWatch/CoreWatch/SystemMetrics.swift
    - CoreWatch/CoreWatch/MachProbeDebugView.swift
  modified:
    - CoreWatch/CoreWatch/ContentView.swift
    - CoreWatch/CoreWatch.xcodeproj/project.pbxproj
decisions:
  - "Used MemoryLayout<T>.size / MemoryLayout<natural_t>.size instead of MACH_TASK_BASIC_INFO_COUNT and THREAD_BASIC_INFO_COUNT — both are sizeof()-based C macros that don't bridge to Swift"
  - "Both new Swift files manually added to project.pbxproj (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase) since Xcode project file requires explicit registration"
metrics:
  duration: "~20 minutes"
  completed: "2026-05-15"
  tasks_completed: 2
  files_changed: 4
---

# Phase 06 Plan 01: Mach API Probe Engine + Debug Sheet Summary

**One-liner:** Mach API probe engine with 4 probe functions, 3-sample verdict sequencing, and a SwiftUI debug sheet triggered by long-pressing the app title.

---

## What Was Built

### SystemMetrics.swift (probe engine)

`SystemMetricsProbe` is an `@Observable @MainActor` class (isolated from `TemperatureViewModel` per D-01) with:

- **`APIVerdict` enum** — `accessible`, `degraded`, `blocked`, `pending` (D-06 three-tier classification)
- **`MachProbeResult` struct** — `id`, `api`, `kernReturn`, `verdict`, `rawData`, `timestamp` (D-09 raw evidence)
- **4 probe methods:**
  - `probeSystemCPU()` — `host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ...)`; accessible if cpu_ticks sum > 0
  - `probeSystemMemory()` — `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)`; accessible if page count sum > 0
  - `probeTaskMemory()` — `task_info(mach_task_self_, MACH_TASK_BASIC_INFO, ...)`; accessible if resident_size > 0
  - `probeTaskCPU()` — `task_threads(mach_task_self_, ...)` + `THREAD_BASIC_INFO` per thread; `vm_deallocate` in `defer` block (T-06-02 mitigation)
- **`runProbeSequence()`** — 3 samples at 10-second intervals via `Task.sleep(for: .seconds(10))`; majority verdict computed after all samples
- **`cancelProbe()`** — cancels in-flight Task, resets `isProbing`
- Console logging: `[CoreWatch]` prefix on every probe call and sequence completion

### MachProbeDebugView.swift (debug sheet)

SwiftUI sheet implementing the 06-UI-SPEC contract:

- `NavigationStack` with "Mach API Probe" inline title and "Done" toolbar button
- **Progress section** — `ProgressView(value:total:)` linear bar + "Sample N of 3" label; hidden when not probing
- **Verdict list** — `ForEach` over `SystemMetricsProbe.allAPIs`; each row is a `VerdictRowView` card
- **`VerdictRowView`** — `RoundedRectangle(cornerRadius: 12)` card with API name, verdict badge, kern_return_t text, raw data, timestamp
- **`VerdictBadgeView`** — `Capsule()` pill with green/yellow/red/`tertiarySystemFill` fill; text color per UI-SPEC badge rules; `.accessibilityLabel`
- **"Run Probe" button** — `.borderedProminent`, disabled during probe, label switches to "Probing..." with `ProgressView()` spinner
- `onDisappear` calls `probe.cancelProbe()`

### ContentView.swift (sheet trigger)

- `@State private var showDebugSheet = false`
- `.onLongPressGesture { showDebugSheet = true }` on "CoreWatch" title
- `.sensoryFeedback(.impact, trigger: showDebugSheet)` haptic on trigger
- `.sheet(isPresented: $showDebugSheet) { MachProbeDebugView() }` on outermost VStack

---

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create SystemMetrics.swift | `1675658` | SystemMetrics.swift |
| 2 | Create MachProbeDebugView + wire ContentView | `c56f460` | MachProbeDebugView.swift, ContentView.swift, SystemMetrics.swift (fix), project.pbxproj |

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] C macros MACH_TASK_BASIC_INFO_COUNT and THREAD_BASIC_INFO_COUNT not bridged to Swift**
- **Found during:** Task 2 build verification (also affects Task 1 code)
- **Issue:** Both constants are defined as `sizeof(T) / sizeof(natural_t)` C macros — Swift cannot import C `sizeof`-based macros from bridging headers, causing "cannot find in scope" errors
- **Fix:** Replaced with `MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size` and `MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size` respectively — semantically identical, Swift-native
- **Files modified:** `CoreWatch/CoreWatch/SystemMetrics.swift`
- **Commit:** `c56f460`

**2. [Rule 3 - Blocking] New Swift files not registered in Xcode project**
- **Found during:** Task 2 build verification
- **Issue:** `SystemMetrics.swift` and `MachProbeDebugView.swift` were created as filesystem files but not added to `project.pbxproj` — Xcode ignores files not in the project graph, causing "cannot find MachProbeDebugView in scope" build error
- **Fix:** Manually added both files to `project.pbxproj` — PBXBuildFile, PBXFileReference, PBXGroup children, and PBXSourcesBuildPhase entries
- **Files modified:** `CoreWatch/CoreWatch.xcodeproj/project.pbxproj`
- **Commit:** `c56f460`

---

## Threat Model Coverage

| Threat ID | Disposition | Implemented |
|-----------|-------------|-------------|
| T-06-01 | accept | No mitigation needed — system metrics are non-sensitive |
| T-06-02 | mitigate | `vm_deallocate` in `defer` block after every `task_threads` call |
| T-06-03 | accept | All calls use public `mach_host_self()` / `mach_task_self_`; no private entitlements |

---

## Known Stubs

None — all probe functions return real data structures. Debug sheet displays actual probe results. No placeholder data flows to UI.

---

## Next Steps (Plan 06-02)

The next plan is an on-device checkpoint: install the app on a physical iOS 18 device, trigger the debug sheet, run the probe sequence, and document verdicts in `06-VERDICTS.md`. The Simulator cannot reproduce iOS 18 sandbox restrictions on Mach APIs — device testing is mandatory.

---

## Self-Check: PASSED

| Item | Status |
|------|--------|
| SystemMetrics.swift exists | FOUND |
| MachProbeDebugView.swift exists | FOUND |
| 06-01-SUMMARY.md exists | FOUND |
| commit 1675658 (Task 1) | FOUND |
| commit c56f460 (Task 2) | FOUND |
