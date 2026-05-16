---
phase: 03-alerts-notification-system
plan: 01
subsystem: notifications
tags: [ios, swift6, usernotifications, thermal, background-observer]

# Dependency graph
requires:
  - phase: 02-dashboard-ui
    provides: TemperatureViewModel with polling, history ring buffer, and scenePhase lifecycle wiring
provides:
  - TemperatureViewModel with full ALRT-01/02/03 notification logic
  - requestNotificationPermission() / refreshNotificationStatus() async methods
  - checkAndFireNotification() cooldown gate (shared foreground/background)
  - thermalStateDidChangeNotification background observer registered in init()
  - scheduleOverheatNotification() local notification scheduling
  - lastAlertedState and notificationsAuthorized as private(set) ViewModel properties
affects:
  - 03-02 (NotificationDelegate + ContentView permission banner will read notificationsAuthorized)

# Tech tracking
tech-stack:
  added: [UserNotifications framework (zero new dependencies — built-in)]
  patterns:
    - nonisolated(unsafe) on block-based observer token to allow deinit access under Swift 6 @Observable
    - Task { @MainActor in } wrapper inside NotificationCenter closure for actor-safe dispatch
    - State-based cooldown gate (lastAlertedState) rather than time-based timer

key-files:
  created: []
  modified:
    - CoreWatch/CoreWatch/TemperatureViewModel.swift

key-decisions:
  - "Used nonisolated(unsafe) on thermalObserver (not just @ObservationIgnored) — Swift 6 deinit cannot access actor-isolated @Observable properties; nonisolated(unsafe) restores plain stored property semantics"
  - "Used Task { @MainActor in } wrapper inside NotificationCenter closure instead of relying on queue: .main — compiler did not accept queue: .main as @MainActor-safe (Assumption A1 in RESEARCH.md proved false)"
  - "scheduleOverheatNotification uses nil trigger (immediate) with fixed identifier thermalAlert — replaces pending rather than stacking"

patterns-established:
  - "Pattern: nonisolated(unsafe) + @ObservationIgnored for block-based NotificationCenter tokens in @Observable @MainActor classes"
  - "Pattern: background observer dispatches to @MainActor via Task { @MainActor [weak self] in } closure wrapper"

requirements-completed:
  - ALRT-01
  - ALRT-02
  - ALRT-03

# Metrics
duration: 12min
completed: 2026-05-12
---

# Phase 3 Plan 01: Alerts & Notification System — ViewModel Logic Summary

**UserNotifications permission, cooldown-gated scheduling, and thermalStateDidChangeNotification background observer wired into TemperatureViewModel under Swift 6.3 strict concurrency**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-12T19:59:00Z
- **Completed:** 2026-05-12T20:11:12Z
- **Tasks:** 1 of 1
- **Files modified:** 1

## Accomplishments

- Added full ALRT-01/02/03 notification logic to TemperatureViewModel without touching ContentView or CoreWatchApp
- Cooldown gate (D-04 through D-06) shared between foreground and background paths via single `lastAlertedState` property
- Swift 6 strict concurrency build succeeds with zero errors and zero warnings
- Background path reads ProcessInfo directly and does not touch the session history ring buffer (D-08 preserved)

## Task Commits

1. **Task 1: Add notification permission, cooldown gate, and background observer** — `2471e9e` (feat)

## Files Created/Modified

- `CoreWatch/CoreWatch/TemperatureViewModel.swift` — Added UserNotifications import, 3 new stored properties, deinit, and 6 new methods covering all ALRT-01/02/03 requirements

## Decisions Made

- **nonisolated(unsafe) required on thermalObserver:** `@ObservationIgnored` alone is insufficient under Swift 6; `deinit` is `nonisolated` and cannot access actor-isolated `@Observable` computed properties even with `@ObservationIgnored`. Adding `nonisolated(unsafe)` restores plain stored property semantics and satisfies the concurrency checker.
- **Task { @MainActor in } closure wrapper:** RESEARCH.md Assumption A1 ("`queue: .main` satisfies @MainActor isolation") proved false at compile time. The Task wrapper is always safe and was pre-coded as the A1 fallback — no design change needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] nonisolated(unsafe) required alongside @ObservationIgnored**
- **Found during:** Task 1, first build attempt
- **Issue:** `@ObservationIgnored` alone did not resolve the Swift 6 concurrency error in deinit: "cannot access property 'thermalObserver' with a non-Sendable type '(any NSObjectProtocol)?' from nonisolated deinit"
- **Fix:** Added `nonisolated(unsafe)` modifier to `thermalObserver` alongside `@ObservationIgnored`; also activated the pre-planned `Task { @MainActor in }` fallback for the observer closure (Assumption A1 in RESEARCH.md was false)
- **Files modified:** CoreWatch/CoreWatch/TemperatureViewModel.swift
- **Verification:** BUILD SUCCEEDED, zero errors, zero concurrency warnings
- **Committed in:** 2471e9e (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug, pre-planned fallback activated)
**Impact on plan:** No scope change. Both the nonisolated(unsafe) fix and Task wrapper were anticipated as fallback paths in RESEARCH.md — the plan explicitly pre-coded both branches.

## Issues Encountered

- Swift 6 compiler rejected `queue: .main` as sufficient for `@MainActor` isolation in the NotificationCenter closure. RESEARCH.md pre-documented this as Assumption A1 with an explicit fallback — activated the `Task { @MainActor [weak self] in }` wrapper as planned.

## Known Stubs

None — all notification logic is fully wired. No placeholder values or TODO markers.

## Threat Flags

No new security surface introduced beyond the plan's threat model. `scheduleOverheatNotification(level:)` derives content exclusively from `ProcessInfo.ThermalState` enum values — no user input. Consistent with T-03-01 (accepted).

## User Setup Required

None — no external service configuration required. Notification permission is requested at runtime via iOS system prompt.

## Next Phase Readiness

- `notificationsAuthorized` and `lastAlertedState` are `private(set)` — ready for ContentView to read
- Plan 02 adds: `NotificationDelegate` (foreground presentation), permission-denied Settings banner in ContentView
- No blockers. Build is clean.

---
*Phase: 03-alerts-notification-system*
*Completed: 2026-05-12*
