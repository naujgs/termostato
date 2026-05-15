---
phase: 07-metrics-integration
verified: 2026-05-15T00:00:00Z
status: human_needed
score: 4/4
overrides_applied: 0
human_verification:
  - test: "Launch app on physical iOS 18 device. Wait 5 seconds. Confirm App CPU card on CPU tab shows a non-zero percentage (e.g. '4.2%')."
    expected: "App CPU card updates from '—' to a non-zero value within 5 seconds of launch."
    why_human: "CPU polling result is a live Mach kernel read (task_threads). Cannot verify on-device numeric output from static analysis. On-device sign-off was documented in 07-03-SUMMARY.md ('approved'), but this verifier did not witness it directly."
  - test: "On the Memory tab, confirm all three cards (App Memory, Memory Free, Memory Used) show non-zero values after the first poll (~5s)."
    expected: "App Memory ~79 MB integer, Memory Free non-zero GB, Memory Used non-zero GB."
    why_human: "Memory readings depend on live host_statistics64 Mach call on device. Same reasoning as above."
  - test: "On the Thermal tab, long-press 'Termostato' title. Confirm MachProbeDebugView debug sheet appears, then dismiss it."
    expected: "Debug sheet opens, content visible, closes on swipe-down — no regression."
    why_human: "Sheet presentation is a runtime UI behavior that requires physical interaction."
---

# Phase 7: Metrics Integration — Verification Report

**Phase Goal:** Users can see live CPU and memory readings from all confirmed-accessible data sources
**Verified:** 2026-05-15
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can see Termostato's own CPU usage displayed as a percentage, updating on the polling interval | VERIFIED | `CPUView.swift` renders `metrics.appCPUPercent` via `MetricCardView`. `MetricsViewModel.readAppCPU()` calls `task_threads` loop with `KERN_SUCCESS` guard. Polling via `Task.detached` every 5s confirmed. User on-device sign-off in 07-03-SUMMARY.md ("all 18 verification points passed"). |
| 2 | User can see Termostato's own memory footprint displayed in MB, updating on the polling interval | VERIFIED | `MemoryView.swift` renders `metrics.appMemoryMB` (e.g. "79 MB"). `MetricsViewModel.readAppMemory()` calls `task_info(MACH_TASK_BASIC_INFO)` with `KERN_SUCCESS` guard. On-device sign-off confirms non-zero values. |
| 3 | System-wide CPU % and memory (used/free) are displayed (Phase 6 confirmed all 4 APIs KERN_SUCCESS) | VERIFIED | `CPUView.swift` renders `metrics.sysCPUPercent`. `MemoryView.swift` renders `metrics.sysMemoryFreeGB` and `metrics.sysMemoryUsedGB`. `MetricsViewModel.readSystemCPU()` calls `host_statistics(HOST_CPU_LOAD_INFO)`. `readSystemMemory()` calls `host_statistics64(HOST_VM_INFO64)`. Graceful fallback: values display "—" when zero (before first delta poll or if blocked). |
| 4 | TabView with Thermal, CPU, Memory tabs is implemented (DASH-01, DASH-02 satisfied here per D-03) | VERIFIED | `ContentView.swift` is a pure `TabView` container (52 lines). Three tabs: `ThermalView(viewModel: vm)`, `CPUView(metrics: metrics)`, `MemoryView(metrics: metrics)`. No `VStack` as body. Tab icons: thermometer.medium, cpu, memorychip. On-device navigation confirmed in 07-03-SUMMARY.md. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Termostato/Termostato/MetricsViewModel.swift` | Live CPU and memory polling ViewModel | VERIFIED | 185 lines. All 5 `private(set)` properties present. `Task.detached` polling, `await MainActor.run` marshalling, `nonisolated(unsafe) previousCPUTicks`, `vm_deallocate` defer in `readAppCPU()`. |
| `Termostato/Termostato/ThermalView.swift` | Thermal tab content extracted from ContentView | VERIFIED | 172 lines. Full extraction: badge, chart, permission banner, debug sheet trigger. `var viewModel: TemperatureViewModel` (not `@State` — passes ownership correctly). `MachProbeDebugView` sheet wired. |
| `Termostato/Termostato/CPUView.swift` | CPU tab with App CPU% and System CPU% metric cards | VERIFIED | 86 lines. Two `MetricCardView` cards rendering `appCPUPercent` and `sysCPUPercent`. `MetricCardView` reusable component defined here. No history charts. |
| `Termostato/Termostato/MemoryView.swift` | Memory tab with App Memory MB and System Memory GB metric cards | VERIFIED | 46 lines. Three `MetricCardView` cards rendering `appMemoryMB`, `sysMemoryFreeGB`, `sysMemoryUsedGB`. No history charts. |
| `Termostato/Termostato/ContentView.swift` | TabView container wiring all three tabs and both ViewModel lifecycles | VERIFIED | 54 lines. Owns `@State private var vm = TemperatureViewModel()` and `@State private var metrics = MetricsViewModel()`. `scenePhase` drives both VM lifecycles. `onAppear` starts both. No residual VStack, badgeColor, showDebugSheet, or helper computed properties. |
| `Termostato/Termostato.xcodeproj/project.pbxproj` | Xcode project file with all 4 new files registered | VERIFIED | All 4 files registered: PBXBuildFile (lines 18-21), PBXSourcesBuildPhase (lines 177-180). Correct `AA000011-AA000014` ID scheme. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MetricsViewModel.readSystemCPU()` | `previousCPUTicks` | `nonisolated(unsafe) private var` | WIRED | Line 38: `nonisolated(unsafe) private var previousCPUTicks: (user: UInt32, idle: UInt32) = (0, 0)`. Mutated in `readSystemCPU()` lines 150-151. |
| `MetricsViewModel.tick()` | `@MainActor` properties | `await MainActor.run { }` | WIRED | Lines 73-79: all 5 properties assigned inside `await MainActor.run { }` block. |
| `ContentView.scenePhase observer` | `vm.startPolling() + metrics.startPolling()` | `.onChange(of: scenePhase) { .active }` | WIRED | Lines 30-43: `.onChange` calls both `vm.startPolling()` and `metrics.startPolling()` in `.active` case. `.background` calls both `stopPolling()`. |
| `ContentView` | `ThermalView` | `ThermalView(viewModel: vm)` | WIRED | Line 16: `ThermalView(viewModel: vm)`. |
| `ContentView` | `CPUView` | `CPUView(metrics: metrics)` | WIRED | Line 20: `CPUView(metrics: metrics)`. |
| `ContentView` | `MemoryView` | `MemoryView(metrics: metrics)` | WIRED | Line 24: `MemoryView(metrics: metrics)`. |
| `ThermalView` | `TemperatureViewModel` | `var viewModel: TemperatureViewModel` | WIRED | Line 9: parameter declaration. Renders `viewModel.thermalState`, `viewModel.notificationsAuthorized`, `viewModel.history` throughout. |
| `CPUView` | `MetricsViewModel` | `var metrics: MetricsViewModel` | WIRED | Line 6: parameter declaration. Renders `metrics.appCPUPercent` (line 19) and `metrics.sysCPUPercent` (line 28). |
| `MemoryView` | `MetricsViewModel` | `var metrics: MetricsViewModel` | WIRED | Line 6: parameter declaration. Renders `metrics.appMemoryMB` (line 19), `metrics.sysMemoryFreeGB` (line 28), `metrics.sysMemoryUsedGB` (line 37). |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `CPUView` | `metrics.appCPUPercent` | `MetricsViewModel.readAppCPU()` via `task_threads` | Yes — Mach kernel read, `KERN_SUCCESS` guard, fallback 0.0 | FLOWING |
| `CPUView` | `metrics.sysCPUPercent` | `MetricsViewModel.readSystemCPU()` via `host_statistics(HOST_CPU_LOAD_INFO)` | Yes — delta formula from cpu_ticks; first poll returns 0.0 by design | FLOWING |
| `MemoryView` | `metrics.appMemoryMB` | `MetricsViewModel.readAppMemory()` via `task_info(MACH_TASK_BASIC_INFO)` | Yes — `resident_size / 1024 / 1024` | FLOWING |
| `MemoryView` | `metrics.sysMemoryFreeGB` | `MetricsViewModel.readSystemMemory()` via `host_statistics64(HOST_VM_INFO64)` | Yes — `free_count × 16384 / 1_073_741_824` | FLOWING |
| `MemoryView` | `metrics.sysMemoryUsedGB` | `MetricsViewModel.readSystemMemory()` | Yes — `(active_count + wire_count) × 16384 / 1_073_741_824` | FLOWING |
| `ThermalView` | `viewModel.thermalState` | `TemperatureViewModel` via `ProcessInfo.thermalState` polling | Yes — existing polling infrastructure, unchanged | FLOWING |

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry points on this machine (iOS app requires physical device + Xcode). On-device verification was performed by the developer in Plan 03 Task 2 (human checkpoint); all 18 verification points passed per 07-03-SUMMARY.md.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CPU-01 | 07-01, 07-02, 07-03 | User can see Termostato's own CPU usage as a percentage gauge | SATISFIED | `CPUView` "App CPU" card reads `metrics.appCPUPercent` from `readAppCPU()` via `task_threads`. On-device confirmed. |
| CPU-02 | 07-01, 07-02, 07-03 | User can see system-wide CPU usage (graceful fallback to hidden if blocked) | SATISFIED | `CPUView` "System CPU" card reads `metrics.sysCPUPercent` from `readSystemCPU()` via `host_statistics`. Shows "—" when 0 (graceful fallback). On-device confirmed. |
| MEM-01 | 07-01, 07-02, 07-03 | User can see Termostato's memory footprint in MB | SATISFIED | `MemoryView` "App Memory" card reads `metrics.appMemoryMB` from `readAppMemory()` via `task_info`. On-device ~79 MB confirmed. |
| MEM-02 | 07-01, 07-02, 07-03 | User can see system-wide memory usage (graceful fallback to hidden if blocked) | SATISFIED | `MemoryView` "Memory Free" and "Memory Used" cards read `sysMemoryFreeGB`/`sysMemoryUsedGB` from `readSystemMemory()` via `host_statistics64`. Shows "—" when 0. On-device confirmed. |
| DASH-01 | 07-02, 07-03 | User can switch between Thermal, CPU, and Memory tabs | SATISFIED | `ContentView` is a `TabView` with three tabs. On-device navigation confirmed. Note: REQUIREMENTS.md traceability table maps this to Phase 8, but ROADMAP Phase 7 SC4 explicitly states "DASH-01, DASH-02 satisfied here per D-03" — ROADMAP is authoritative. |
| DASH-02 | 07-02, 07-03 | Existing thermal badge and step-chart remain functional in Thermal tab (no regression) | SATISFIED | `ThermalView` is a verbatim extraction of the original ContentView body. Badge, chart, permission banner, and debug sheet all preserved. On-device regression check passed. |

**Note on REQUIREMENTS.md traceability:** The traceability table in REQUIREMENTS.md maps DASH-01 and DASH-02 to Phase 8. However, ROADMAP.md Phase 7 requirements explicitly lists DASH-01 and DASH-02, and Phase 7 Success Criteria SC4 states: "TabView with Thermal, CPU, Memory tabs is implemented (DASH-01, DASH-02 satisfied here per D-03)." The ROADMAP is the authoritative planning document — the REQUIREMENTS.md traceability table predates this reassignment and is stale. DASH-01 and DASH-02 are satisfied by Phase 7. Phase 8 in ROADMAP retains the same requirements but adds additional criteria (SC5: tab selection persistence) that go beyond what Phase 7 delivered.

**Orphaned requirements check:** REQUIREMENTS.md lists no additional IDs mapped to Phase 7 beyond those covered by the plans. CPU-02 and MEM-02 were originally scoped to Phase 6 in the traceability table but are also listed in Phase 7 plans and ROADMAP — they are now fully satisfied (Phase 6 confirmed KERN_SUCCESS, Phase 7 wired them into the UI).

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None found | — | — | — |

No TODO/FIXME/placeholder comments in any of the five key files. No empty implementations. No hardcoded empty arrays or stubs. The stubs created in Plan 01 (Text("Thermal") etc.) were replaced in Plan 02, confirmed by file content inspection.

The `vm_kernel_page_size` → `16384` literal substitution in `readSystemMemory()` (line 179) is documented as an intentional decision (Swift 6 strict concurrency constraint, assumption A1 fallback). It is correct for iOS arm64. Not an anti-pattern.

### Human Verification Required

Three items require on-device confirmation. Note: The developer already provided sign-off in Plan 03 Task 2 (all 18 points "approved"). These items are flagged here because this verifier cannot independently attest to live on-device behavior from static analysis alone.

#### 1. App CPU Display — Live Value on Device

**Test:** Launch app on physical iOS 18 device. Navigate to the CPU tab. Wait 5 seconds for the first poll.
**Expected:** "App CPU" card transitions from "—" to a non-zero percentage (e.g. "4.2%"). Value updates again after ~5 more seconds.
**Why human:** Numeric value from `task_threads` Mach call on running iOS process. Cannot verify from static code inspection. Developer sign-off documented in 07-03-SUMMARY.md.

#### 2. Memory Tab — All Three Cards Show Non-Zero Values

**Test:** Navigate to the Memory tab. Wait 5 seconds.
**Expected:** "App Memory" shows integer MB (~79 MB), "Memory Free" shows non-zero GB, "Memory Used" shows non-zero GB.
**Why human:** Values depend on live `host_statistics64` Mach call. Developer sign-off documented in 07-03-SUMMARY.md.

#### 3. Thermal Tab Debug Sheet Regression Check

**Test:** Navigate to the Thermal tab. Long-press "Termostato" title. Confirm `MachProbeDebugView` sheet opens. Dismiss by swiping down.
**Expected:** Debug sheet opens with Mach probe data. Dismiss returns to Thermal tab. Badge and chart remain functional.
**Why human:** Sheet presentation requires physical interaction. Developer sign-off documented in 07-03-SUMMARY.md.

### Gaps Summary

No gaps. All four success criteria from ROADMAP.md are verified at the code level. All six requirement IDs (CPU-01, CPU-02, MEM-01, MEM-02, DASH-01, DASH-02) have implementation evidence. No stubs, missing artifacts, or broken key links found.

The `human_needed` status reflects that three behaviors (live metric values, memory readings, debug sheet on-device) can only be fully attested through physical device testing. The developer's sign-off in 07-03-SUMMARY.md ("approved" on all 18 points) satisfies the human gate for the purposes of phase sign-off if the project owner accepts the SUMMARY attestation as sufficient evidence.

---

_Verified: 2026-05-15_
_Verifier: Claude (gsd-verifier)_
