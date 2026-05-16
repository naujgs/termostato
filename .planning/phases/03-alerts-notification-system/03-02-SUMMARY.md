---
phase: 03-alerts-notification-system
plan: "02"
subsystem: notifications
tags: [swift, ios, usernotifications, delegate, swiftui, phase-complete]
dependency_graph:
  requires:
    - 03-01-SUMMARY.md
  provides:
    - foreground notification delivery via UNUserNotificationCenterDelegate
    - permission-denied banner with Settings deep-link
    - complete Phase 3 notification system (ALRT-01, ALRT-02, ALRT-03)
  affects:
    - CoreWatch/CoreWatch/NotificationDelegate.swift
    - CoreWatch/CoreWatch/CoreWatchApp.swift
    - CoreWatch/CoreWatch/ContentView.swift
tech_stack:
  added:
    - UNUserNotificationCenterDelegate (NSObject subclass, nonisolated methods)
    - "@State NotificationDelegate retained in App struct (strong reference lifetime pattern)"
    - "@Environment(\\.openURL) for Settings deep-link from SwiftUI"
    - UIKit import in ContentView for UIApplication.openSettingsURLString
  patterns:
    - Delegate retained via @State to prevent weak-reference deallocation (Pitfall 6)
    - nonisolated delegate methods for Swift 6 conformance from non-isolated class
    - Conditional banner driven by viewModel.notificationsAuthorized (@Observable binding)
key_files:
  created:
    - CoreWatch/CoreWatch/NotificationDelegate.swift
  modified:
    - CoreWatch/CoreWatch/CoreWatchApp.swift
    - CoreWatch/CoreWatch/ContentView.swift
decisions:
  - "nonisolated on both UNUserNotificationCenterDelegate methods — Swift 6 requires this for conformance from a non-isolated class (RESEARCH.md Pattern 5)"
  - "@State used to retain NotificationDelegate in App struct — UNUserNotificationCenter.delegate is weak; must be strongly held to avoid deallocation"
  - "openSettingsURLString via @Environment(\\.openURL) — pure SwiftUI approach, no UIKit scene access needed"
  - "All four Phase 3 on-device acceptance criteria PASSED (approved by user after physical device testing)"
metrics:
  duration_minutes: 0
  completed_date: "2026-05-12"
  tasks_completed: 3
  files_changed: 3
requirements_satisfied:
  - ALRT-01
  - ALRT-02
  - ALRT-03
---

# Phase 03 Plan 02: Notification Delivery Infrastructure and Permission Banner Summary

**One-liner:** UNUserNotificationCenterDelegate wired into CoreWatchApp via @State retention, with permission-denied banner in ContentView using @Environment(\.openURL) Settings deep-link — completes Phase 3 notification system.

## What Was Built

### Task 1: NotificationDelegate + CoreWatchApp wiring (commit 5c3804b)

Created `NotificationDelegate.swift` — a minimal `NSObject` conforming to `UNUserNotificationCenterDelegate`. Without this, iOS silently drops notifications while the app is in the foreground (RESEARCH.md Pitfall 2). Both delegate methods are `nonisolated` to satisfy Swift 6 conformance from a non-isolated class.

Updated `CoreWatchApp.swift` to retain `NotificationDelegate` as `@State` and assign it as `UNUserNotificationCenter.current().delegate` in `.onAppear`. This prevents the delegate from being deallocated (RESEARCH.md Pitfall 6 — the property is weak on `UNUserNotificationCenter`).

Key implementation details:
- `willPresent` returns `[.banner, .sound]` — `.alert` is deprecated since iOS 14
- `didReceive` calls `completionHandler()` and does nothing else; standard iOS tap behavior handles app foregrounding
- Delegate set in `.onAppear` on `WindowGroup`, before `ContentView` fully renders

### Task 2: Permission-denied banner in ContentView (commit e978d51)

Added a conditional inline banner to `ContentView.swift` between the thermal state badge and the `Spacer().frame(height: 32)`. The banner:
- Renders when `viewModel.notificationsAuthorized == false`
- Shows a `bell.slash` SF Symbol and "Notifications disabled — tap to open Settings" text
- Tapping opens iOS Settings to the app's notification settings page via `@Environment(\.openURL)` + `UIApplication.openSettingsURLString`
- Disappears automatically when permission is granted (re-check happens in `startPolling()` on each foreground, implemented in Plan 01)

Layout order in VStack after this change:
1. App title
2. Thermal state badge (RoundedRectangle block)
3. Permission-denied banner (conditional — new)
4. `Spacer().frame(height: 32)`
5. Chart or empty state
6. `Spacer()` (fill)

### Task 3: On-device Phase 3 acceptance verification (human checkpoint — APPROVED)

All four Phase 3 success criteria verified on physical device:

| Criterion | Status | Notes |
|-----------|--------|-------|
| Criterion 1 — Permission request + denied banner (ALRT-01) | PASSED | Dialog appeared on first launch; banner shown after denial; Settings deep-link worked; banner disappeared after granting permission |
| Criterion 2 — Foreground notification with cooldown (ALRT-02) | PASSED | Banner appeared at Critical/Serious; no second notification during 60s cooldown window; notification fired again after Nominal reset |
| Criterion 3 — Background notification (ALRT-03) | PASSED | Notification delivered while app backgrounded; required beginBackgroundTask fix applied in quick task 260513-0yk |
| Criterion 4 — Settings deep-link (D-11) | PASSED | Verified as part of Criterion 1 |

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | 5c3804b | feat(03-02): create NotificationDelegate and wire into CoreWatchApp |
| Task 2 | e978d51 | feat(03-02): add permission-denied banner to ContentView |
| Quick fix (pre-plan) | 34216e8 | fix(03): request background task on scene backgrounding so thermal observer stays live |

## Deviations from Plan

### Auto-fixed Issues (applied as quick task before plan execution)

**1. [Rule 1 - Bug] beginBackgroundTask needed for background thermal observer**
- **Found during:** On-device testing (Criterion 3 pre-verification)
- **Issue:** `thermalStateDidChangeNotification` observer was being suspended when the app backgrounded because iOS treats apps without an active background task as suspended. The observer would not fire until the app was foregrounded again.
- **Fix:** Added `UIApplication.shared.beginBackgroundTask` call in `stopPolling()` via quick task 260513-0yk. This holds a background execution slot long enough for the notification observer to fire.
- **Files modified:** `CoreWatch/CoreWatch/TemperatureViewModel.swift`
- **Commit:** 34216e8

None of the other plan tasks required deviation — all three files matched the plan spec exactly as written.

## Known Stubs

None. All data flows are wired to live `@Observable` ViewModel state. No placeholder values or hardcoded display data exist in the modified files.

## Threat Surface Scan

No new security-relevant surface introduced beyond what the plan's `<threat_model>` covers:
- T-03-05: NotificationDelegate.didReceive — accepts only app-defined response identifiers
- T-03-06: Permission-denied banner — discloses only non-sensitive notification status
- T-03-07: openURL(Settings) — user-initiated only, behind a Button tap

No additional threat flags.

## Phase 3 Completion Status

Phase 03 (alerts-notification-system) is **COMPLETE**.

All three requirements satisfied:
- **ALRT-01:** Permission request fires on first launch; denied state shows inline banner with Settings deep-link
- **ALRT-02:** Notification fires at Serious/Critical with 60-second cooldown; foreground delivery works via NotificationDelegate
- **ALRT-03:** Background thermalStateDidChangeNotification observer delivers notification when app is backgrounded (with beginBackgroundTask fix)

## Self-Check: PASSED

Files verified:
- `CoreWatch/CoreWatch/NotificationDelegate.swift` — EXISTS
- `CoreWatch/CoreWatch/CoreWatchApp.swift` — contains `notificationDelegate` @State + delegate assignment
- `CoreWatch/CoreWatch/ContentView.swift` — contains `notificationsAuthorized` conditional banner

Commits verified:
- `5c3804b` — EXISTS in git log
- `e978d51` — EXISTS in git log
- `34216e8` — EXISTS in git log
