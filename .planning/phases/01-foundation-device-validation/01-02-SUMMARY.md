---
phase: 01-foundation-device-validation
plan: 02
subsystem: core-data-pipeline
tags: [viewmodel, thermalstate, combine, iokit, scenePhase, swift6]
dependency_graph:
  requires: [01-01]
  provides: [TemperatureViewModel, ContentView-lifecycle]
  affects: [02-01, 03-01]
tech_stack:
  added: []
  patterns: [MVVM-Observable, Combine-Timer-cancel-recreate, scenePhase-lifecycle]
key_files:
  created:
    - CoreWatch/CoreWatch/TemperatureViewModel.swift
  modified:
    - CoreWatch/CoreWatch/ContentView.swift
    - CoreWatch/CoreWatch.xcodeproj/project.pbxproj
decisions:
  - "Used [self] instead of [weak self] in Combine sink — @MainActor final class has no retain cycle risk; AnyCancellable cancels on deinit"
  - "IOServiceMatching returns Unmanaged<CFMutableDictionary>? in Swift 6 bridging — must call takeRetainedValue() before passing to IOServiceGetMatchingService"
metrics:
  duration_minutes: 2
  completed_date: "2026-05-11T22:41:56Z"
  tasks_completed: 2
  files_changed: 3
---

# Phase 01 Plan 02: TemperatureViewModel and scenePhase Lifecycle Summary

**One-liner:** @Observable @MainActor ViewModel with 30s Combine Timer polling, cancel-and-recreate pattern, one-shot IOKit probe, and ContentView scenePhase wiring via @Environment.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Implement TemperatureViewModel | f7c76eb | TemperatureViewModel.swift (created), project.pbxproj |
| 2 | Wire ContentView scenePhase lifecycle | 66ba3f9 | ContentView.swift |

## What Was Built

### TemperatureViewModel (`CoreWatch/CoreWatch/TemperatureViewModel.swift`)

- `@Observable @MainActor final class` — Swift 6 strict concurrency safe
- `thermalState: ProcessInfo.ThermalState` published property, initially `.nominal`
- `startPolling()` — cancels any existing timer then creates fresh `Timer.publish(every: 30)` Combine sink; immediately calls `updateThermalState()` so UI is populated without 30s wait
- `stopPolling()` — cancels and nils the `AnyCancellable`; no background polling per D-05
- `probeIOKit()` — one-shot IOKit probe called from `init()`; logs result to console; marked for deletion after Phase 1 per D-01/D-02
- Added to Xcode project Sources build phase in `project.pbxproj`

### ContentView (`CoreWatch/CoreWatch/ContentView.swift`)

- `@State private var viewModel = TemperatureViewModel()` per D-03
- `@Environment(\.scenePhase)` per D-06 — no UIKit lifecycle hooks
- `.onChange(of: scenePhase)` calls `startPolling()` on `.active`, `stopPolling()` on `.background`
- `.onAppear` starts polling immediately (`.onChange` does not fire for the initial `scenePhase` value)
- Phase 1 placeholder `VStack` body — Phase 2 replaces without touching lifecycle wiring

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] IOServiceMatching Unmanaged wrapper**
- **Found during:** Task 1 build
- **Issue:** `IOServiceMatching` bridged to Swift as returning `Unmanaged<CFMutableDictionary>?`, not `CFDictionary` directly. The plan's code passed `matching` directly to `IOServiceGetMatchingService` which expects `CFDictionary`.
- **Fix:** Called `matchingUnmanaged.takeRetainedValue()` to extract the `CFMutableDictionary` before passing to `IOServiceGetMatchingService`. CFMutableDictionary is a subtype of CFDictionary so no cast needed.
- **Files modified:** `CoreWatch/CoreWatch/TemperatureViewModel.swift`
- **Commit:** f7c76eb

**2. [Rule 1 - Bug] Removed `[weak self]` from Combine sink**
- **Found during:** Task 1 implementation (preemptive — noted in plan's important_context)
- **Issue:** Swift 6 strict concurrency disallows weak references to `@MainActor`-isolated actors in some contexts; `[weak self]` on a `final class` with `AnyCancellable` also provides no retain-cycle benefit since the cancellable is stored on the same object.
- **Fix:** Used `[self]` capture to satisfy Swift 6 compiler while preserving correct semantics.
- **Files modified:** `CoreWatch/CoreWatch/TemperatureViewModel.swift`
- **Commit:** f7c76eb

## Known Stubs

- `ContentView` body is a placeholder `VStack` with static text — intentional per plan. Phase 2 plan replaces this with the full dashboard UI.
- IOKit probe (`probeIOKit()` and its `init()` call) is deliberately present as Phase 1 diagnostic code. Plan D-01/D-02 require it be deleted before Phase 2.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes were introduced beyond what the plan's threat model covers.

## Verification Results

- BUILD SUCCEEDED (iOS 18 arm64, Swift 6, SWIFT_STRICT_CONCURRENCY=complete)
- Zero Swift 6 concurrency errors
- No UIKit imports in either file
- All grep acceptance criteria passed for both tasks

## Self-Check: PASSED
