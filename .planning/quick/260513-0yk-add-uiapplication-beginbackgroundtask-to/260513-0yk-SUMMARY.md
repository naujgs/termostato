---
phase: quick
plan: 260513-0yk
subsystem: background-execution
tags: [background-task, UIKit, thermal-observer, notifications]
tech-stack:
  added: [UIKit (UIApplication.shared.beginBackgroundTask)]
  patterns: [nonisolated(unsafe) stored property for UIBackgroundTaskIdentifier]
key-files:
  modified:
    - CoreWatch/CoreWatch/TemperatureViewModel.swift
decisions:
  - "backgroundTaskID declared nonisolated(unsafe) matching thermalObserver pattern already in file"
  - "UIApplication.shared access is safe from @MainActor context — both startPolling/stopPolling called on main actor via ContentView scenePhase observer"
  - "No Info.plist UIBackgroundModes entry needed — beginBackgroundTask requires no declaration"
metrics:
  duration: "< 5 min"
  completed: "2026-05-12"
  tasks: 1
  files: 1
---

# Quick Task 260513-0yk: Add UIBackgroundTask lifecycle to TemperatureViewModel Summary

**One-liner:** `beginBackgroundTask` requested in `stopPolling()` and ended in `startPolling()` so the `thermalStateDidChangeNotification` observer stays live during the iOS ~30s background execution window.

## What Was Done

Added `UIApplication.beginBackgroundTask` / `endBackgroundTask` lifecycle to `TemperatureViewModel` so that when the app backgrounds and `stopPolling()` cancels the timer, iOS grants ~30 seconds of execution time for the `thermalStateDidChangeNotification` observer to fire and schedule a local notification.

### Changes to `TemperatureViewModel.swift`

1. Added `import UIKit` (line 5).
2. Added `@ObservationIgnored nonisolated(unsafe) private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid` stored property using the same Swift 6 annotation pattern as `thermalObserver`.
3. `stopPolling()` now calls `UIApplication.shared.beginBackgroundTask(withName: "ThermalMonitor")` with a defensive expiration handler that ends the task and resets the ID to `.invalid`.
4. `startPolling()` now calls `UIApplication.shared.endBackgroundTask(backgroundTaskID)` at entry if a task is active, clearing the ID before restarting the timer.

## Verification

- `grep -n "beginBackgroundTask\|endBackgroundTask\|backgroundTaskID"` returns hits in property declaration, `startPolling()`, and `stopPolling()`.
- `grep -n "import UIKit"` returns line 5.
- `xcodebuild` reports `BUILD SUCCEEDED` with zero `error:` lines.

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Hash | Message |
|------|---------|
| 34216e8 | fix(03): request background task on scene backgrounding so thermal observer stays live |

## Self-Check: PASSED

- File exists: `CoreWatch/CoreWatch/TemperatureViewModel.swift` — FOUND
- Commit 34216e8 — FOUND
