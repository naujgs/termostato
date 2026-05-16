---
phase: 08-dashboard-tabs
reviewed: 2026-05-15T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - CoreWatch/CoreWatch/ContentView.swift
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-05-15
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

`ContentView.swift` is a clean, minimal SwiftUI entry-point for the three-tab dashboard. It correctly owns both ViewModels as `@State`, wires scenePhase lifecycle to both ViewModels uniformly, and uses an explicit `selectedTab` binding (satisfying the SC5 testability requirement noted in D-03). No security or critical correctness issues were found.

One warning is raised: `startPolling()` is called redundantly on every `.active` scene transition even when the app is returning from merely being inactive (e.g., notification centre swipe, incoming call), not only from a true background→foreground transition. This can produce double-polling bursts and a second spurious `requestNotificationPermission()` prompt attempt each time the app re-enters `.active` from `.inactive`. Two informational items cover a `print` debug artifact and a missing accessibility hint for the `TabView`.

## Warnings

### WR-01: `startPolling()` called on every `.active` transition including `.inactive → .active`

**File:** `CoreWatch/CoreWatch/ContentView.swift:37-39`

**Issue:** The `onChange(of: scenePhase)` handler calls `vm.startPolling()` and `metrics.startPolling()` whenever `newPhase == .active`. iOS routes `inactive → active` (e.g., user dismisses Notification Centre, answers a call) through this same case, so polling is restarted — and `requestNotificationPermission()` / `refreshNotificationStatus()` are re-fired — on every such transition, not just on true `background → active` returns. Both `startPolling()` implementations do cancel the previous timer/task before creating a new one, so there is no runaway accumulation, but the unnecessary cancel-and-recreate adds jitter to the 5-second polling cadence and re-triggers the permission prompt path on `.active` returns from `.inactive`.

**Fix:** Guard on the previous phase to distinguish a genuine background→active return:

```swift
.onChange(of: scenePhase) { oldPhase, newPhase in
    switch newPhase {
    case .active:
        // Only restart polling when returning from background, not from inactive.
        if oldPhase == .background {
            vm.startPolling()
            metrics.startPolling()
        }
    case .background:
        vm.stopPolling()
        metrics.stopPolling()
    case .inactive:
        break
    @unknown default:
        break
    }
}
```

The `oldPhase` parameter is already available in the two-argument `onChange` closure — no API change is required.

## Info

### IN-01: `onAppear` and `onChange` both call `startPolling()` without coordination

**File:** `CoreWatch/CoreWatch/ContentView.swift:49-52`

**Issue:** `onAppear` calls `startPolling()` for both ViewModels unconditionally, and the `onChange(of: scenePhase)` handler also calls `startPolling()` when the phase is `.active`. On first launch the sequence is `onAppear` fires (polling starts), then immediately `scenePhase` becomes `.active` (polling is restarted). This double-start on cold launch is benign because both `startPolling()` implementations cancel the prior timer/task before creating a new one, but it is redundant and can be surprising to a future reader. The `onAppear` guard can be removed if `scenePhase` reliably delivers `.active` on first launch — which it does on iOS 14+.

**Fix:** Remove the `onAppear` block and rely solely on the `onChange(of: scenePhase)` handler (with the `oldPhase == .background` guard from WR-01 removed for the first `.active` delivery, or by keeping the `onAppear` but removing the `startPolling` call from `onChange` for the `.inactive → .active` case):

```swift
// Option A: drop onAppear entirely — scenePhase delivers .active on first render.
// Option B: keep onAppear, apply WR-01 fix so onChange only fires on background→active.
```

Either option removes the guaranteed double-start on cold launch.

### IN-02: Leftover `print` debug artifacts in ViewModels called from ContentView lifecycle

**File:** `CoreWatch/CoreWatch/ContentView.swift:38-39` (triggers prints in TemperatureViewModel.swift:120, MetricsViewModel.swift:54)

**Issue:** Every `startPolling()` / `stopPolling()` call — driven by `ContentView` — emits `print` statements to the console (e.g., `[CoreWatch] Polling started.`, `[CoreWatch] thermalState = nominal` every 5 seconds). These are benign for a sideloaded personal app but produce continuous console noise in production builds and are a code quality concern for any shared or archived build.

**Fix:** Wrap with a debug compile condition or remove before any distribution build:

```swift
#if DEBUG
print("[CoreWatch] Polling started.")
#endif
```

---

_Reviewed: 2026-05-15_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
