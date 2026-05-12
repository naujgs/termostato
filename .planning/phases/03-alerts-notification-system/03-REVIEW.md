---
phase: 03-alerts-notification-system
reviewed: 2026-05-12T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - Termostato/Termostato/ContentView.swift
  - Termostato/Termostato/NotificationDelegate.swift
  - Termostato/Termostato/TemperatureViewModel.swift
  - Termostato/Termostato/TermostatoApp.swift
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-05-12
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Four files were reviewed covering the Phase 3 alerts and notification system implementation. No critical (security or crash) issues were found. The code is generally well-structured and follows the project's MVVM + `@Observable` + `@MainActor` conventions.

Three warnings were identified: a retain cycle in the polling timer sink, a double-invocation of `startPolling()` on cold launch, and a cooldown design gap that silently suppresses critical-level alerts when the device escalates from serious to critical. Three informational items cover a missing error log on notification scheduling failure, unnecessary repeated permission requests, and a semantic mismatch in the `@State` wrapper on `NotificationDelegate`.

## Warnings

### WR-01: Retain Cycle in Timer Sink Capture

**File:** `Termostato/Termostato/TemperatureViewModel.swift:113`
**Issue:** The `.sink` closure captures `self` strongly (`[self]`). `timerCancellable` (stored in `self`) holds the `AnyCancellable`, which holds the closure, which holds `self`. This creates a retain cycle: `TemperatureViewModel` will never be deallocated while polling is active. Since the ViewModel lives for the session this is low-risk in practice, but it is a latent memory issue and violates Swift's recommended capture pattern.
**Fix:**
```swift
timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        self?.updateThermalState()
    }
```

### WR-02: Double startPolling() Call on Cold Launch

**File:** `Termostato/Termostato/ContentView.swift:123-137`
**Issue:** On cold launch, both `.onAppear` (line 136) and `.onChange(of: scenePhase)` (line 126, when phase transitions to `.active`) call `startPolling()`. The timer cancel-and-recreate guard prevents a double timer, but `updateThermalState()` is called twice in rapid succession, and two pairs of unstructured `Task { await requestNotificationPermission() }` and `Task { await refreshNotificationStatus() }` are spawned concurrently. The first reading and permission requests are duplicated on every app launch.
**Fix:** Remove the `.onAppear` call — `scenePhase` transitioning to `.active` is sufficient and fires on launch:
```swift
// Remove this block:
.onAppear {
    viewModel.startPolling()
}
```
The `.onChange(of: scenePhase)` handler already covers the initial activation.

### WR-03: Critical Alert Suppressed When Escalating from Serious to Critical

**File:** `Termostato/Termostato/TemperatureViewModel.swift:205-224`
**Issue:** The cooldown gate (`guard lastAlertedState == nil else { return }`) uses a single `nil` / non-`nil` flag, not a level comparison. If the device enters `.serious` (fires notification, sets `lastAlertedState = .serious`) and then escalates to `.critical` without ever dropping below serious, the critical state never generates a notification. The user who set up alerts specifically for critical heat is silently unnotified. This may be intentional per D-06, but the plan does not explicitly state that critical should be suppressed by a prior serious alert.
**Fix:** If critical should always produce its own notification regardless of a prior serious alert, change the gate to compare levels:
```swift
private func checkAndFireNotification() {
    let state = thermalState
    let isElevated = (state == .serious || state == .critical)

    if isElevated {
        // Allow re-notification if state escalated to a higher level
        if let alerted = lastAlertedState, alerted.rawValue >= state.rawValue {
            return   // same or higher level already notified
        }
        lastAlertedState = state
        guard notificationsAuthorized else { return }
        let levelName = (state == .serious) ? "Serious" : "Critical"
        scheduleOverheatNotification(level: levelName)
    } else {
        lastAlertedState = nil
    }
}
```
Apply the same change to `handleBackgroundThermalChange()`. If one-alert-per-elevation-period is the intended behavior, add a comment clarifying that critical is intentionally suppressed by a prior serious alert.

## Info

### IN-01: Notification Scheduling Error Silently Dropped

**File:** `Termostato/Termostato/TemperatureViewModel.swift:262`
**Issue:** `try? await UNUserNotificationCenter.current().add(request)` silently discards any scheduling error. While the `notificationsAuthorized` guard above should prevent reaching this call without permission, other errors (e.g., content policy violations, identifier length limits) would be invisibly dropped.
**Fix:** Log the error instead of discarding it:
```swift
do {
    try await UNUserNotificationCenter.current().add(request)
    print("[Termostato] Overheating notification scheduled for \(level).")
} catch {
    print("[Termostato] Failed to schedule notification: \(error)")
}
```

### IN-02: requestNotificationPermission Called on Every Foreground

**File:** `Termostato/Termostato/TemperatureViewModel.swift:118`
**Issue:** `startPolling()` calls both `requestNotificationPermission()` and `refreshNotificationStatus()` on every foreground activation. `requestAuthorization` is idempotent after the first grant/denial (iOS returns cached status), but it spawns two unstructured `Task` instances and makes an unnecessary system call on each activation. `refreshNotificationStatus()` already reads the current settings authorizationStatus, which is sufficient.
**Fix:** Remove the `requestNotificationPermission()` call from `startPolling()` and call it only once, at init time or on first launch. Keep `refreshNotificationStatus()` in `startPolling()` to detect user changes in Settings:
```swift
// In init():
Task { await requestNotificationPermission() }

// In startPolling() — remove this line:
Task { await requestNotificationPermission() }
// Keep only:
Task { await refreshNotificationStatus() }
```

### IN-03: @State Used for Non-Observable Reference Type in TermostatoApp

**File:** `Termostato/Termostato/TermostatoApp.swift:9`
**Issue:** `@State private var notificationDelegate = NotificationDelegate()` uses `@State` to hold a non-`@Observable` `NSObject` subclass. `@State` on a reference type in SwiftUI's `App` struct works for lifetime retention in practice, but it is semantically incorrect — `@State` is intended for value types or `@Observable` reference types. A plain stored property achieves the intended lifetime without the semantic confusion:
```swift
// Replace:
@State private var notificationDelegate = NotificationDelegate()

// With:
private let notificationDelegate = NotificationDelegate()
```
Since `App` structs are retained for the application lifetime, `let` is sufficient to keep the delegate alive.

---

_Reviewed: 2026-05-12_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
