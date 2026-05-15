# Phase 7: Metrics Integration - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire all 4 confirmed-accessible Mach APIs into a live dashboard:
- App CPU% (`task_threads`) — satisfies CPU-01
- App Memory MB (`task_info`) — satisfies MEM-01
- System CPU% (`host_statistics`) — accessible per Phase 6, display alongside app CPU
- System Memory free/used GB (`host_statistics64`) — accessible per Phase 6, display alongside app memory

ContentView is restructured from a single VStack to a TabView with 3 tabs (Thermal, CPU, Memory).
TemperatureViewModel polling interval is reduced from 10s to 5s.

</domain>

<decisions>
## Implementation Decisions

### Dashboard Structure

- **D-01:** Phase 7 introduces TabView with 3 tabs: **Thermal**, **CPU**, **Memory**. ContentView becomes the TabView container. Existing thermal content (badge + chart) moves into a new `ThermalView` sub-view.
- **D-02:** Debug sheet trigger (long-press on "Termostato" title) moves into `ThermalView` with the rest of the thermal content. Behavior unchanged, just relocated.
- **D-03:** DASH-01 and DASH-02 (from REQUIREMENTS.md, Phase 8) are satisfied here — the TabView restructure happens in Phase 7, not Phase 8.

### Metric Display Format

- **D-04:** CPU tab shows two metric cards: **App CPU** (%) and **System CPU** (%). Each card: large number centered, label above. Same visual style — `RoundedRectangle` card matching the thermal badge aesthetic.
- **D-05:** Memory tab shows two metric cards: **App Memory** (MB, from `task_info` resident_size) and **System Memory** (free / used in GB, from `host_statistics64` page counts × page size). Same card format as CPU tab.
- **D-06:** No history charts in Phase 7 for CPU/memory. Rolling history charts are deferred to v1.3+ (CPU-03, MEM-03). Only live current-value display.

### ViewModel Architecture

- **D-07:** Create a new `MetricsViewModel.swift` — separate `@Observable @MainActor` class. Does NOT extend `TemperatureViewModel`. `ContentView` holds both via `@State`:
  ```swift
  @State private var vm = TemperatureViewModel()
  @State private var metrics = MetricsViewModel()
  ```
- **D-08:** MetricsViewModel exposes these published properties:
  - `appCPUPercent: Double` — app CPU % from `task_threads`
  - `appMemoryMB: Int` — app resident memory MB from `task_info`
  - `sysCPUPercent: Double` — system CPU % from `host_statistics` (user / (user + idle) — system ticks are 0 on Apple Silicon)
  - `sysMemoryFreeGB: Double` — free memory in GB from `host_statistics64`
  - `sysMemoryUsedGB: Double` — used memory in GB (active + wired pages × page size)
- **D-09:** MetricsViewModel polling interval: **5 seconds**. TemperatureViewModel polling interval also reduced from 10s → 5s as part of this phase.
- **D-10:** MetricsViewModel lifecycle mirrors TemperatureViewModel — `startPolling()` / `stopPolling()` called together from ContentView's `scenePhase` observer.

### Main-thread Mach Fix (CR-01)

- **D-11:** MetricsViewModel's Mach call methods are `nonisolated`. Polling runs via `Task.detached(priority: .userInitiated)` with `Task.sleep(for: .seconds(5))` between ticks. Results marshal back to `@MainActor` via `await MainActor.run { }` to update published properties.
- **D-12:** This pattern is used in MetricsViewModel only. SystemMetricsProbe in `SystemMetrics.swift` (debug probe) is NOT changed — the probe is intentionally kept as-is for debug use.

### Polling Formula — CPU (Apple Silicon)

- **D-13:** System CPU% = `(user_ticks_delta / (user_ticks_delta + idle_ticks_delta)) × 100`. The `system` tick counter reads 0 on Apple Silicon (confirmed Phase 6). Use user and idle deltas only. Store previous tick snapshot to compute delta between polls.
- **D-14:** App CPU% = sum of `cpu_usage / TH_USAGE_SCALE × 100` across non-idle threads (same formula as `probeTaskCPU()` in SystemMetrics.swift — extract this pattern directly).

### Mach Call Patterns

- **D-15:** Extract Mach call implementations directly from `SystemMetrics.swift` probe methods — they are proven correct and KERN_SUCCESS confirmed. Do NOT rewrite from scratch.

### Claude's Discretion

- Tab bar icon system images (SF Symbols) — use standard iOS symbols appropriate for thermal/CPU/memory
- Exact number formatting (e.g. "4.2%" vs "4%", "79 MB" vs "79.3 MB")
- Card padding, spacing, and typography — follow existing `ContentView` patterns (16pt horizontal padding, .largeTitle for the number, .headline for the label)
- Empty/loading state for CPU/memory cards before first poll completes

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Code (primary references)
- `Termostato/Termostato/TemperatureViewModel.swift` — `@Observable @MainActor` polling pattern, Timer.publish, ring buffer, `startPolling()`/`stopPolling()` lifecycle. Phase 7 adds Mach calls following this established pattern.
- `Termostato/Termostato/ContentView.swift` — Current single-VStack layout; Phase 7 restructures to TabView. Read this to understand what moves where.
- `Termostato/Termostato/SystemMetrics.swift` — All 4 Mach call implementations (`probeSystemCPU`, `probeSystemMemory`, `probeTaskMemory`, `probeTaskCPU`). Extract patterns from here — do NOT rewrite.

### Planning Artifacts
- `.planning/phases/06-mach-api-proof-of-concept/06-VERDICTS.md` — Per-API verdicts and data samples. Confirms all 4 APIs KERN_SUCCESS. Apple Silicon system-tick note in host_statistics section.
- `.planning/REQUIREMENTS.md` — CPU-01, MEM-01 (Phase 7 requirements). CPU-02, MEM-02 (accessible per Phase 6 — also wired in Phase 7).
- `.planning/ROADMAP.md` §Phase 7 — Success criteria, dependency on Phase 6.
- `CLAUDE.md` — Tech stack, Swift 6.3 strict concurrency rules, private API constraints.

### Xcode Project
- `Termostato/Termostato.xcodeproj/project.pbxproj` — New Swift files MUST be manually registered (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase entries). This was required for SystemMetrics.swift and MachProbeDebugView.swift in Phase 6 — same process for MetricsViewModel.swift and any new view files.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RoundedRectangle(cornerRadius: 20)` badge: the thermal badge pattern (fill + overlay Text) can be directly reused for CPU/memory metric cards
- `TemperatureViewModel` polling lifecycle (`startPolling`/`stopPolling` + scenePhase observer in ContentView): MetricsViewModel follows this same pattern
- SystemMetrics.swift Mach probe methods: direct source for `nonisolated` Mach call implementations in MetricsViewModel

### Established Patterns
- `@Observable @MainActor final class` — ViewModel pattern. MetricsViewModel follows this.
- `print("[Termostato] ...")` — Console logging prefix convention
- `private(set) var` — Published properties exposed read-only to views
- `@ObservationIgnored nonisolated(unsafe) private var` — For non-observable stored references (timer handle, etc.)
- `withUnsafeMutablePointer + withMemoryRebound` — Mach API Swift bridging pattern (confirmed in SystemMetrics.swift)
- `MemoryLayout<T>.size / MemoryLayout<natural_t>.size` — Swift-safe count computation (C macros don't bridge)

### Integration Points
- `ContentView.body` — Replace outer VStack with TabView; add `@State private var metrics = MetricsViewModel()`
- `ContentView.onChange(of: scenePhase)` — Add `metrics.startPolling()` / `metrics.stopPolling()` calls
- New files to register in project.pbxproj: `MetricsViewModel.swift`, `CPUView.swift`, `MemoryView.swift`, `ThermalView.swift`

</code_context>

<specifics>
## Specific Ideas

- User wants 5s polling interval applied everywhere — both TemperatureViewModel AND MetricsViewModel. TemperatureViewModel currently has `Timer.publish(every: 10, ...)` at line 111 — change to `every: 5`.
- CPU delta formula must store previous tick snapshot between polls to compute delta. MetricsViewModel needs a `private var previousCPUTicks: (user: UInt32, idle: UInt32) = (0, 0)` property.
- System memory: convert page counts to GB using `vm_kernel_page_size` (or fixed 16384 bytes for Apple Silicon — confirmed from probe data: ~129K pages × 4K page size ≈ 6 GB total, consistent with 6 GB iPhone RAM).

</specifics>

<deferred>
## Deferred Ideas

- Rolling history charts for CPU and memory — deferred to v1.3+ (CPU-03, MEM-03 requirements)
- Battery level display — deferred to v1.3+ (BATT-01, BATT-02)
- State duration display ("Serious for 4 min") — deferred to v1.3+ (THERM-01)

</deferred>

---

*Phase: 07-metrics-integration*
*Context gathered: 2026-05-15*
