# Phase 3: Alerts & Notification System - Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the notification system on top of the confirmed Phase 2 dashboard. Delivers:
- ALRT-01: Request notification permission on first launch; graceful no-permission fallback
- ALRT-02: Local notification fires when thermal state reaches Serious or Critical; cooldown prevents re-fire while state remains elevated
- ALRT-03: Background thermalStateDidChangeNotification triggers alerts when the app is not terminated

This phase does NOT add new dashboard UI elements beyond the permission-denied Settings deep-link banner.

</domain>

<decisions>
## Implementation Decisions

### Notification Content
- **D-01:** Notification **title**: `"iPhone Overheating"` — alert framing, not state name mirroring.
- **D-02:** Notification **body**: `"Thermal state: {level} — performance may be limited"` where `{level}` is the state name (Serious or Critical). Combined format: state + consequence in one line.
- **D-03:** Notification **action**: Add a `"Dismiss"` action button via `UNNotificationCategory`. Tapping the notification body (outside Dismiss) opens the app via standard iOS behavior — no additional "Open" button needed.

### Cooldown Gate
- **D-04:** Cooldown is **shared across foreground/background**. One `lastAlertedState` property on `TemperatureViewModel` tracks which level was last notified. No separate foreground vs background cooldown trackers.
- **D-05:** Cooldown **resets when thermal state drops below threshold** (returns to Nominal or Fair). When state is back below Serious, `lastAlertedState` clears. Next escalation to Serious/Critical fires again. No time-based reset.
- **D-06:** Firing logic (applies to both foreground and background paths):
  - If `thermalState >= Serious` AND `lastAlertedState == nil` → fire notification, set `lastAlertedState = thermalState`
  - If `thermalState >= Serious` AND `lastAlertedState != nil` → skip (still in cooldown)
  - If `thermalState < Serious` → clear `lastAlertedState` (cooldown reset)

### Background Observer
- **D-07:** Register `thermalStateDidChangeNotification` observer in `TemperatureViewModel` (consistent with existing architecture — Phase 1 D-03 established TemperatureViewModel as the sole data pipeline owner). Observer is registered on `init()` and removed on `deinit`.
- **D-08:** Background notification path: `thermalStateDidChangeNotification` fires → read `ProcessInfo.processInfo.thermalState` → apply D-06 gate → schedule `UNUserNotificationCenter` notification if gate passes. Does NOT call `updateThermalState()` (that would append to the ring buffer, confusing session history with background events).

### Permission Request
- **D-09:** Request notification permission in `TemperatureViewModel.startPolling()` (already called on `.active` scenePhase). No separate permission pre-prompt screen — direct `UNUserNotificationCenter.requestAuthorization` call.
- **D-10:** Graceful fallback: if permission denied, the app continues to work (dashboard, polling, history). Notification scheduling calls are silently skipped. No crash, no broken state.

### Permission-Denied Banner
- **D-11:** Show an inline banner **below the thermal state badge** when notification permission is denied. The banner contains a Settings deep-link (`UIApplication.open(UIApplication.openSettingsURLString)`).
- **D-12:** Banner visibility is determined by a `notificationsAuthorized: Bool` property on `TemperatureViewModel` (checked/updated after permission request and on each `startPolling()` call via `UNUserNotificationCenter.getNotificationSettings`).
- **D-13:** Banner persists until permission is granted (re-check in `startPolling()` each time the app foregrounds). No auto-dismiss timer.

### Claude's Discretion
- Exact banner copy and visual styling — should be subtle, not alarming. Something like: "Notifications disabled — tap to open Settings" with a `.secondary` foreground style and a chevron.
- Whether to use `UNNotificationCategory` identifier string — pick a stable constant (e.g., `"thermalAlert"`).
- `UNUserNotificationCenter` delegate setup — if needed to handle foreground notification presentation, Claude decides.
- OSLog vs `print()` for background path logging — Claude picks based on existing Phase 2 pattern (print is fine).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Requirements
- `.planning/REQUIREMENTS.md` — ALRT-01, ALRT-02, ALRT-03 definitions; APNs explicitly Out of Scope; `UNUserNotificationCenter` confirmed as correct approach
- `.planning/ROADMAP.md` — Phase 3 success criteria (4 items that must be TRUE); phase goal statement

### Architecture & Stack
- `CLAUDE.md` (project) — iOS 18+ target; `UserNotifications` framework listed as zero-dependency; background execution constraints; sideloading entitlement limits

### Prior Phase Context
- `.planning/phases/01-foundation-device-validation/01-CONTEXT.md` — D-03 (TemperatureViewModel is the real, persistent ViewModel extended each phase); D-05 (background alerting uses thermalStateDidChangeNotification, not polling)
- `.planning/phases/02-dashboard-ui/02-CONTEXT.md` — D-07 (system appearance, no forced color scheme); D-08 (badge color palette)

### Existing Source Files
- `CoreWatch/CoreWatch/TemperatureViewModel.swift` — Add `lastAlertedState`, `notificationsAuthorized`, `thermalStateDidChangeNotification` observer, and notification scheduling here
- `CoreWatch/CoreWatch/ContentView.swift` — Add permission-denied banner below the badge (between badge and chart)
- `CoreWatch/CoreWatch/CoreWatchApp.swift` — Minimal; no changes expected

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TemperatureViewModel` (`@Observable`, `@MainActor`) — Phase 3 adds: `lastAlertedState: ProcessInfo.ThermalState?`, `notificationsAuthorized: Bool`, background observer registration, and notification scheduling. All additions follow the existing `@MainActor` pattern.
- `updateThermalState()` — Foreground notification check hooks into this method (after updating `thermalState`, before ring buffer append is unaffected).
- `startPolling()` / `stopPolling()` — Permission check (`getNotificationSettings`) runs in `startPolling()` to refresh `notificationsAuthorized` each time the app foregrounds.
- Badge color mapping (`badgeColor` in ContentView) — Permission-denied banner is a new View element in ContentView, not a modification of the badge.

### Established Patterns
- `@Observable` + `@MainActor` on ViewModel — all new properties (`lastAlertedState`, `notificationsAuthorized`) follow this pattern; Swift 6.3 strict concurrency enforced.
- `scenePhase` observer in ContentView — unchanged; Phase 3 does not modify the existing lifecycle hooks.
- `print()` for logging — Phase 2 retained this; Phase 3 can continue or switch to OSLog (Claude's discretion).

### Integration Points
- `TemperatureViewModel.updateThermalState()` — add foreground notification trigger here (reads `lastAlertedState`, fires if gate passes, updates `lastAlertedState`).
- `TemperatureViewModel.init()` — register `thermalStateDidChangeNotification` observer here.
- `ContentView.body` — add permission-denied banner between badge and chart (using `if !viewModel.notificationsAuthorized`).

</code_context>

<specifics>
## Specific Ideas

- Notification title "iPhone Overheating" was chosen over "Serious" or "CoreWatch — Serious" — alert framing over state mirroring.
- Body format: `"Thermal state: Serious — performance may be limited"` — state name is interpolated, not hardcoded.
- Dismiss button added via `UNNotificationCategory`; tapping outside Dismiss (the notification body) opens the app.
- Cooldown is entirely state-level-based, not time-based. No arbitrary N-minute timers.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 03-alerts-notification-system*
*Context gathered: 2026-05-12*
