---
phase: 08-dashboard-tabs
fixed_at: 2026-05-15T00:00:00Z
review_path: .planning/phases/08-dashboard-tabs/08-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 2
skipped: 1
status: partial
---

# Phase 8: Code Review Fix Report

**Fixed at:** 2026-05-15
**Source review:** `.planning/phases/08-dashboard-tabs/08-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 3
- Fixed: 2 (WR-01 fixed in prior pass; IN-02 fixed in this pass)
- Skipped: 1 (IN-01 resolved as side-effect of WR-01 fix)

## Fixed Issues

### WR-01: `startPolling()` called on every `.active` transition including `.inactive → .active`

**Files modified:** `Termostato/Termostato/ContentView.swift`
**Commit:** b34269a
**Applied fix:** Changed the `onChange(of: scenePhase)` closure from `{ _, newPhase in` to `{ oldPhase, newPhase in }` and added an `if oldPhase == .background` guard inside the `.active` case. Polling (and the associated `requestNotificationPermission` / `refreshNotificationStatus` call path) now only restarts on a genuine background→active return, not on every `inactive→active` transition such as Notification Centre dismissal or call end. Fixed in a prior pass.

### IN-02: Leftover `print` debug artifacts in ViewModels called from ContentView lifecycle

**Files modified:** `Termostato/Termostato/TemperatureViewModel.swift`, `Termostato/Termostato/MetricsViewModel.swift`
**Commit:** 793c277
**Applied fix:** Wrapped all `print(...)` statements in both ViewModels with `#if DEBUG` / `#endif` guards. This covers all call sites: `startPolling`, `stopPolling`, `updateThermalState`, `requestNotificationPermission`, `checkAndFireNotification`, `handleBackgroundThermalChange`, and `scheduleOverheatNotification` in `TemperatureViewModel.swift`; and `startPolling` / `stopPolling` in `MetricsViewModel.swift`.

## Skipped Issues

### IN-01: `onAppear` and `onChange` both call `startPolling()` without coordination

**File:** `Termostato/Termostato/ContentView.swift:49-52`
**Reason:** Resolved as a side-effect of the WR-01 fix (commit b34269a). With the `oldPhase == .background` guard in place, `onChange` no longer fires `startPolling()` on cold launch (where `oldPhase == .inactive`). The `onAppear` block handles initial startup exclusively; `onChange` handles background→active restarts exclusively. There is no longer a double-start on cold launch. The REVIEW.md explicitly identifies "Option B: keep onAppear, apply WR-01 fix" as a valid resolution — that is the current state of the code.

---

_Fixed: 2026-05-15_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
