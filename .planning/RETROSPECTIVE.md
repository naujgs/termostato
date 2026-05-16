# CoreWatch — Retrospective

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

---

## Milestone: v1.2 — Sensor Research & Data Expansion

**Shipped:** 2026-05-15
**Phases:** 3 (06–08) | **Plans:** 8 | **Commits:** 45
**Timeline:** 2026-05-15 → 2026-05-15 (1 day)

### What Was Built

- `SystemMetrics.swift` — Mach API probe engine with `host_statistics`, `host_statistics64`, `task_info`, `task_threads` calls bridged from C; 3-sample verdict sequencing; `MachProbeDebugView` debug sheet (long-press title to open)
- `06-VERDICTS.md` — on-device evidence that all 4 Mach APIs return `KERN_SUCCESS` under free Apple ID sideload on iOS 18; graceful-fallback design confirmed unnecessary
- `MetricsViewModel` — `@Observable @MainActor` class polling App CPU%, System CPU%, App Memory MB, System Memory free/used GB every 5s via `Task.detached` + nonisolated Mach calls
- `ThermalView`, `CPUView`, `MemoryView` — three dedicated tab content views with metric cards
- `ContentView` refactored from single-screen VStack to `TabView(selection: $selectedTab)` container — explicit `@State private var selectedTab: Int = 0` binding with `.tag(0/1/2)` per tab
- SC5 verified on device: tab selection persists within session, no metric resets, no chart clears, no debug sheet regression
- `#if DEBUG` guards around all `print` statements in both ViewModels; `onChange(of: scenePhase)` guarded on `oldPhase == .background`

### What Worked

- **Proof-of-concept-first for Mach APIs** — Phase 6 ran a dedicated probe before committing to implementation. Discovering that all 4 APIs return `KERN_SUCCESS` (vs the expected graceful-fallback) was a positive surprise that simplified Phase 7 significantly.
- **Human checkpoint for UAT** — the `autonomous: false` checkpoint plan for on-device verification (Phases 07-03 and 08-02) worked well as a forcing function. Having a structured 7-step test sequence prevented vague "it looks fine" approvals.
- **Code review catching real issues post-execution** — `gsd-code-reviewer` found the `onChange` false-positive (firing on `inactive→active` not just `background→active`). Not a regression, but a pre-existing behaviour worth fixing before it caused a bug report.
- **REQUIREMENTS.md checkboxes correct at milestone close** — for the first time across all three milestones, traceability was correct without manual correction. Phase 08-03's doc-close plan handled it atomically.

### What Was Inefficient

- **Worktree contention on Wave 1** — parallel worktree dispatch for a single-plan wave caused a lock collision (`null` branch artifact left behind). Single-plan waves don't need parallelism; the overhead added friction with no benefit.
- **`One-liner:` placeholder in MILESTONES.md** — Phases 06 and 07 summaries used a different heading format than expected by `summary-extract`. Required manual fix at milestone close. Consistent one-liner frontmatter in all summaries would prevent this.
- **DASH-01/02 traceability confusion** — these requirements were initially attributed to Phase 8 in REQUIREMENTS.md but actually satisfied in Phase 7 (per 07-CONTEXT.md D-03). Required a correction commit in 08-03. A clearer rule about where requirements get credited at plan time would avoid this.

### Patterns Established

- **Mach API access under free Apple ID sideload on iOS 18:** `host_statistics`, `host_statistics64`, `task_info`, `task_threads` all return `KERN_SUCCESS`. No special entitlements required. `host_statistics` tick counter reads 0 on Apple Silicon — compute CPU% from `user + idle + nice` fields only.
- **`MemoryLayout<T>.size` instead of C macros:** `MACH_TASK_BASIC_INFO_COUNT` and `THREAD_BASIC_INFO_COUNT` don't bridge to Swift — use `MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size`.
- **Explicit `TabView(selection:)` is the testable pattern:** implicit SwiftUI tab selection is hard to verify; `@State private var selectedTab: Int = 0` + `.tag(N)` makes SC criteria concrete.
- **`onChange(of:)` two-argument form:** use `onChange(of: scenePhase) { old, new in }` and guard on `old == .background` to avoid firing `startPolling()` on transient inactive→active transitions.

### Key Lessons

1. Single-plan waves should skip worktree isolation — the overhead is pure friction with no parallelism benefit.
2. Every SUMMARY.md should include a `**One-liner:**` field in its body (not just the heading) so `summary-extract` can find it reliably.
3. Attribute requirements to the phase where they are *first satisfied*, not the phase where they are *closed in docs*. Decide this at plan time, not closeout time.
4. The Mach API probe-first pattern is reusable: whenever a private or undocumented API is involved, build a debug-sheet probe in its own phase before wiring it into production code.

### Cost Observations

- Sessions: 1 focused session
- Model: Sonnet 4.6 throughout
- Notable: The proof-of-concept phase (Phase 6) resolved the highest-risk unknown (API access) before any production code was written — same pattern that paid off in v1.0 with IOKit. Front-loading unknowns continues to be the highest-ROI planning decision.

---

## Cross-Milestone Trends

| Metric | v1.0 | v1.1 | v1.2 |
|--------|------|------|------|
| Phases | 3 | 2 | 3 |
| Plans | 6 | 2 | 8 |
| Swift LOC | 494 | 494 | 1,369 |
| Timeline | 2 days | 1 day | 1 day |
| Device verified | ✓ all phases | ✓ all phases | ✓ all phases |
| Blocking bugs found in UAT | 1 (background process suspension) | 0 | 0 |
| REQUIREMENTS.md correct at close | ✗ manual fix needed | ✗ manual fix needed | ✓ first time clean |
| Recurring pattern | Spike high-risk APIs first | — | Spike high-risk APIs first |
