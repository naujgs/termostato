# Termostato — Retrospective

## Milestone: v1.0 — MVP

**Shipped:** 2026-05-13
**Phases:** 3 | **Plans:** 6 | **Commits:** 47
**Timeline:** 2026-05-11 → 2026-05-13 (2 days)

### What Was Built

- Xcode project scaffold with Swift 6.3 strict concurrency and IOKit bridging header
- `TemperatureViewModel` — `@Observable @MainActor` 30s polling pipeline via `ProcessInfo.thermalState`
- IOKit numeric temperature probe: confirmed blocked by AMFI under free Apple ID, decision documented, probe removed
- SwiftUI dashboard: color-coded thermal badge (green/yellow/orange/red) + session-length step-chart (Swift Charts, 120-entry ring buffer)
- Full notification system: `UNUserNotificationCenter` permission request, cooldown-gated scheduling, `thermalStateDidChangeNotification` background observer, `beginBackgroundTask` for ~30s background execution window
- `NotificationDelegate` for foreground notification delivery; permission-denied banner with Settings deep-link
- All four Phase 3 criteria verified on physical iPhone

### What Worked

- **IOKit spike-first approach** — proving the highest-risk component (private API) in Phase 1 before building UI was the right call. The blocked IOKit result was discovered early with zero rework cost.
- **Device testing at each phase** — catching real iOS behaviors (process suspension, thermal simulation quirks) at each checkpoint prevented late-stage surprises.
- **Swift 6 strict concurrency from day one** — made the background observer and `@MainActor` isolation clean and compiler-enforced rather than a retrofit problem.
- **`thermalStateDidChangeNotification` + `beginBackgroundTask`** — the combination of event-driven notification and explicit background execution window worked correctly on device without any background mode declarations.

### What Was Inefficient

- **REQUIREMENTS.md checkbox tracking** — DISP-01, DISP-02, and INST-01 were validated on device but checkboxes weren't ticked during phase execution. Required manual correction at milestone close.
- **Background notification test procedure** — Criterion 3 required multiple attempts because the cooldown state from foreground testing blocked the background notification. Better test isolation between criteria would save time.
- **`beginBackgroundTask` fix discovered during UAT** — the background execution gap could have been caught during planning if the iOS process suspension model was more explicitly modeled in the Phase 3 plan.

### Patterns Established

- IOKit private API access requires `systemgroup.com.apple.powerlog` entitlement — unavailable under free Apple ID sideloading. Future projects should not plan on numeric temperature without TrollStore or developer account.
- `@Observable @MainActor` ViewModel + `nonisolated(unsafe)` for observer tokens is the Swift 6-safe pattern for `NotificationCenter` observers in `deinit`.
- `beginBackgroundTask` needs no `UIBackgroundModes` Info.plist entry — always available, grants ~30s execution window.
- Xcode thermal state simulation (`Debug → Simulate Thermal State`) must be used BEFORE backgrounding the app for background notification testing; cooldown state carries across foreground/background.

### Key Lessons

1. Plan for process suspension explicitly in any phase involving background behavior — don't assume observers will fire.
2. Test criteria in isolation for UAT: reset thermal state to Nominal between each criterion.
3. Tick requirement checkboxes in the REQUIREMENTS.md traceability table immediately after each phase verification — don't defer to milestone close.
4. For sideloaded personal apps, local notifications + `beginBackgroundTask` is the correct and sufficient alerting stack. APNs adds zero value here.

### Cost Observations

- Sessions: ~3 focused sessions over 2 days
- Model: Sonnet 4.6 throughout
- Notable: Phase 1 IOKit spike saved potentially significant rework by front-loading the highest-risk decision

---

## Cross-Milestone Trends

| Metric | v1.0 |
|--------|------|
| Phases | 3 |
| Plans | 6 |
| Swift LOC | 494 |
| Timeline | 2 days |
| Device verified | ✓ all phases |
| Blocking bugs found in UAT | 1 (background process suspension) |
