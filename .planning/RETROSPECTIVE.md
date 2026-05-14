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

## Milestone: v1.1 — Visual Improvements

**Shipped:** 2026-05-13
**Phases:** 2 | **Plans:** 2 | **Commits:** 8
**Timeline:** 2026-05-13 → 2026-05-13 (1 day)

### What Was Built

- Polling cadence reduced from 30s to 10s; ring buffer expanded from 120 to 360 entries — 60-minute history preserved at 3× resolution
- Custom app icon (1024×1024 opaque RGB PNG) wired into Xcode asset catalog via `Contents.json` `filename` field
- Alpha channel stripped from PNG before commit (ffmpeg `format=rgb24`) — iOS icons must be fully opaque

### What Worked

- **Asset-only delivery for the icon** — no Swift code changes required; the single `filename` field addition to `Contents.json` was sufficient for Xcode to pick up the icon and generate all size variants.
- **Code review catching the alpha issue** — the `gsd-code-reviewer` agent flagged the RGBA alpha channel before verification, preventing a silent Xcode warning. Fixed cleanly in one commit.
- **Two-literal change for polling** — Phase 4 was two numeric literal edits (`30→10`, `120→360`) with zero logic changes. Planning and execution were proportionally lightweight.

### What Was Inefficient

- **Phase 5 directory missing at execute time** — `/gsd-execute-phase 5` was invoked with no phase directory or PLAN.md. The orchestrator had to create both inline before execution could proceed. The planning step (`/gsd-plan-phase 5`) was either skipped or its artifacts weren't committed.
- **REQUIREMENTS.md checkboxes again unchecked** — same issue as v1.0. Both POLL-01 and ICON-01 were done but unchecked at milestone close. Traceability table also showed "TBD" for phase assignments.
- **`sips --deleteProperty hasAlpha` failed on macOS** — the reviewer's suggested fix didn't work; required ffmpeg workaround. Should be documented for future icon work.

### Patterns Established

- Xcode 13+ asset catalog universal format: a single `1024×1024` entry with `"idiom": "universal"` and `"platform": "ios"` is sufficient — Xcode derives all size variants at build time. No need for explicit size entries.
- iOS app icons must be opaque RGB PNG. `sips --deleteProperty hasAlpha` does not work on macOS; use `ffmpeg -vf "format=rgb24" -frames:v 1 -update 1` instead.
- Verify `sips -g hasAlpha <file>` returns `no` before committing icon assets.

### Key Lessons

1. Run `/gsd-plan-phase` before `/gsd-execute-phase` — or confirm the phase directory and PLAN.md exist first.
2. Always check PNG alpha channel when dropping icon assets; `ffmpeg format=rgb24` is the reliable strip method on macOS.
3. Tick REQUIREMENTS.md traceability table entries immediately after phase verification — this is the second milestone this was deferred.

### Cost Observations

- Sessions: 1 session
- Model: Sonnet 4.6 throughout
- Notable: Both phases were trivially small (2 LOC changed + 1 file edited). Overhead from GSD scaffolding was disproportionate to the change size — reasonable for maintaining audit trail, but worth noting for future micro-phases.

---

## Cross-Milestone Trends

| Metric | v1.0 | v1.1 |
|--------|------|------|
| Phases | 3 | 2 |
| Plans | 6 | 2 |
| Swift LOC | 494 | 494 (no change) |
| Timeline | 2 days | 1 day |
| Device verified | ✓ all phases | ✓ all phases |
| Blocking bugs found in UAT | 1 (background process suspension) | 0 |
| Recurring issue | REQUIREMENTS.md checkboxes not ticked | REQUIREMENTS.md checkboxes not ticked |
