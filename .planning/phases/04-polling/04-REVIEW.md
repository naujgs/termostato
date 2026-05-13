---
phase: 04-polling
reviewed: 2026-05-13T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - Termostato/Termostato/TemperatureViewModel.swift
findings:
  critical: 0
  warning: 3
  info: 1
  total: 4
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-05-13
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

Reviewed the single changed file `TemperatureViewModel.swift`, which is the core MVVM data pipeline for Termostato. The file implements thermal state polling, session history ring buffer management, background task handling, and local notification delivery.

The overall structure is sound. Swift 6 / `@MainActor` isolation is applied consistently, `@ObservationIgnored` + `nonisolated(unsafe)` are used correctly for the observer token and background task ID, and the notification cooldown gate (D-06) is in place.

Three warnings were found: a retain cycle in the timer sink closure, a logic gap in the severity escalation path, and a subtle expiration handler bug in `stopPolling`. One info item was found: the polling interval is a magic number, which is especially relevant given phase 4's focus on making the interval configurable.

No critical security or data-loss issues were found.

---

## Warnings

### WR-01: Retain cycle — timer sink captures `self` strongly

**File:** `Termostato/Termostato/TemperatureViewModel.swift:113`
**Issue:** The `.sink` closure on the timer publisher captures `self` strongly via `[self]`. `timerCancellable` is stored on `self`, creating a cycle: `self` → `timerCancellable` → closure → `self`. The `AnyCancellable` is cancelled in `stopPolling`, which breaks the cycle while the app is running — but if `stopPolling` is never called (e.g., the view is dismissed without the scenePhase observer firing), the ViewModel will leak. Every other closure in the file uses `[weak self]`.

**Fix:**
```swift
// Line 113 — change [self] to [weak self]
.sink { [weak self] _ in
    self?.updateThermalState()
}
```

---

### WR-02: Severity escalation not re-notified — `lastAlertedState` gate only checks `nil`

**File:** `Termostato/Termostato/TemperatureViewModel.swift:210-214` and `236`
**Issue:** The cooldown gate is `guard lastAlertedState == nil else { return }`. If the device escalates from `.serious` to `.critical`, the gate blocks the second notification because `lastAlertedState` is already set (to `.serious`), not `nil`. The user is never informed of the more severe thermal condition.

**Fix:** Compare the new state's severity against the last alerted state rather than checking for `nil`:
```swift
// In checkAndFireNotification() and handleBackgroundThermalChange()
// Replace:
guard lastAlertedState == nil else { return }

// With:
if let last = lastAlertedState, last.rawValue >= state.rawValue {
    // Same or lower severity already notified — skip.
    return
}
// lastAlertedState = state  (this line stays)
```
This allows a `.critical` notification to fire even when `.serious` was already notified, while still preventing duplicate same-level alerts.

---

### WR-03: Background task expiration handler re-reads `self.backgroundTaskID` instead of capturing the task constant

**File:** `Termostato/Termostato/TemperatureViewModel.swift:129-135`
**Issue:** The expiration handler reads `self.backgroundTaskID` at call time rather than capturing the specific task ID that was just created. If `stopPolling` were called a second time before the expiration fires, `self.backgroundTaskID` would hold the newer task's ID, and the expiration handler would end the wrong task (the newer one), leaving the original task handle dangling until iOS forcibly terminates it.

```swift
// Current — re-reads self.backgroundTaskID at expiration time:
let task = UIApplication.shared.beginBackgroundTask(withName: "ThermalMonitor") { [weak self] in
    guard let self else { return }
    let id = self.backgroundTaskID          // BUG: may be a different task's ID by now
    UIApplication.shared.endBackgroundTask(id)
    self.backgroundTaskID = .invalid
}
```

**Fix:** Capture the `task` value directly in the expiration closure. Use a local `var` with a placeholder, or restructure so the just-created ID is passed into the closure:
```swift
var taskID: UIBackgroundTaskIdentifier = .invalid
taskID = UIApplication.shared.beginBackgroundTask(withName: "ThermalMonitor") { [weak self] in
    UIApplication.shared.endBackgroundTask(taskID)
    self?.backgroundTaskID = .invalid
}
backgroundTaskID = taskID
```

---

## Info

### IN-01: Polling interval is a magic number — critical for phase 4 configurability

**File:** `Termostato/Termostato/TemperatureViewModel.swift:111`
**Issue:** The polling interval `10` (seconds) is a hardcoded literal. Phase 4's goal is to make the polling interval configurable. The interval should be a named constant or a stored property so it can be changed from a single definition site.

**Fix:**
```swift
// Add near the top of the class alongside maxHistory:
private static let defaultPollingInterval: TimeInterval = 10

// Line 111 — use the constant:
timerCancellable = Timer.publish(every: Self.defaultPollingInterval, on: .main, in: .common)
```
If phase 4 makes the interval user-selectable, promote this to a non-static stored property and call `startPolling()` whenever it changes to recreate the timer with the new interval (which the cancel-and-recreate pattern already supports cleanly).

---

_Reviewed: 2026-05-13_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
