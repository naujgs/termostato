---
phase: 06-mach-api-proof-of-concept
verified: 2026-05-15T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Confirm 06-VERDICTS.md reflects actual on-device probe run (not synthetic data)"
    expected: "The kern_return_t=0 values, cpu_ticks counts, page counts, resident_size (~79 MB), thread counts (5-6), and timestamps (14:54:09, 14:54:19, 14:54:29) in 06-VERDICTS.md match what was seen on-screen in the debug sheet and in the Xcode console during the physical iOS 18 device run"
    why_human: "The verdicts file documents human-observed probe output from a physical device. No automated test can re-run the probe on iOS 18 hardware or verify that the logged values match what the debug sheet displayed. The plausibility of the data (growing cpu_ticks, varying page counts, ~79 MB resident, 5-6 threads) is consistent with a real run, but final confirmation requires the developer to attest the VERDICTS.md faithfully records what they saw."
---

# Phase 6: Mach API Proof-of-Concept Verification Report

**Phase Goal:** Determine which Mach kernel APIs are accessible under iOS 18 free-sideload sandboxing so Phase 7 knows exactly what to wire up.
**Verified:** 2026-05-15
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A minimal SystemMetrics.swift file exists with C-bridged Mach API calls for host_statistics (CPU) and host_statistics64 (memory) | VERIFIED | File exists at `Termostato/Termostato/SystemMetrics.swift`. Contains `host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ...)` at line 141 and `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` at line 175. Also includes `task_info` (line 210) and `task_threads` (line 239) beyond the minimum stated in this SC. |
| 2 | Running the app on a physical iOS 18 device logs whether each Mach call succeeds or returns KERN_FAILURE / zeroed data | VERIFIED (conditional) | Console logging is implemented: every probe function prints `[Termostato] <api>: kern_return_t=\(result), data=\(rawData)` and the sequence prints `[Termostato] Probe sequence complete. Verdicts: \(self.finalVerdicts)`. The logging code is substantive and wired. Whether it was actually executed on physical hardware is the human-verification item below. |
| 3 | A clear per-API verdict (accessible / blocked / degraded) is documented so Phase 7 knows what to integrate | VERIFIED | `06-VERDICTS.md` exists with a 4-row summary table, 3-sample evidence subsections for all 4 APIs, and a Phase 7 Implications section with explicit GO/no-go per API. All kern_return_t values are actual (0 = KERN_SUCCESS) with real timestamps (14:54:09, 14:54:19, 14:54:29) and plausible raw data. No placeholder tokens found. |
| 4 | If system-wide APIs are blocked, the graceful-fallback path is confirmed as the design decision | VERIFIED | `06-VERDICTS.md` contains `### Graceful Fallback Decision` section. All 4 APIs returned KERN_SUCCESS; the section explicitly states no fallback is needed and references the CPU-02 and MEM-02 fallback language. The conditional is correctly handled: fallback is addressed even though it did not activate. |
| 5 | Each of the 4 Mach APIs has a documented verdict: accessible, degraded, or blocked (from 06-02 must_haves) | VERIFIED | All 4 APIs documented as Accessible in `06-VERDICTS.md` with 3-sample evidence tables. Raw evidence accompanies each verdict: growing cpu_ticks, varying page counts, stable ~79 MB resident, 5-6 threads at 0-2% CPU. Phase 7 planner can read the file alone to make integration decisions. |

**Score:** 5/5 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Termostato/Termostato/SystemMetrics.swift` | Mach API probe logic with four probe functions and verdict classification | VERIFIED | 287 lines. Contains `enum APIVerdict`, `struct MachProbeResult`, `@Observable @MainActor final class SystemMetricsProbe` with all 4 probe methods, `runProbeSequence()`, `cancelProbe()`, majority verdict logic, and `[Termostato]` console logging. No TemperatureViewModel reference (D-01 isolation confirmed). |
| `Termostato/Termostato/MachProbeDebugView.swift` | SwiftUI debug sheet with verdict row cards | VERIFIED | 193 lines. Contains `struct MachProbeDebugView: View`, `@State private var probe = SystemMetricsProbe()`, `ProgressView(value:total:)`, "Sample N of 3" label, "Run Probe" button, `Capsule()` badge, `Color.green`/`Color.yellow`/`Color.red`, `cornerRadius: 12`, `.accessibilityLabel` calls, `probe.cancelProbe()` in `onDisappear`. |
| `Termostato/Termostato/ContentView.swift` | Sheet integration and long-press trigger | VERIFIED | Contains `@State private var showDebugSheet = false`, `.onLongPressGesture { showDebugSheet = true }`, `.sensoryFeedback(.impact, trigger: showDebugSheet)`, `.sheet(isPresented: $showDebugSheet) { MachProbeDebugView() }`. Thermal dashboard is unmodified. |
| `.planning/phases/06-mach-api-proof-of-concept/06-VERDICTS.md` | Per-API verdict report with raw evidence for Phase 7 consumption | VERIFIED | Contains `## Summary` (4-row table), `## Detailed Evidence` with 4 subsections each having 3-sample tables, `## Phase 7 Implications` with go/no-go per API, and `### Graceful Fallback Decision`. References CPU-02 and MEM-02 requirement IDs. Actual kern_return_t values (0 = KERN_SUCCESS) with timestamps and raw sensor data. |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MachProbeDebugView.swift` | `SystemMetrics.swift` | `@State private var probe = SystemMetricsProbe()` | WIRED | Line 10 of MachProbeDebugView.swift instantiates `SystemMetricsProbe()` directly. All probe method calls (`probe.runProbeSequence()`, `probe.cancelProbe()`, `probe.isProbing`, `probe.samplesCompleted`, `probe.results`, `probe.finalVerdicts`) are wired throughout the view body. |
| `ContentView.swift` | `MachProbeDebugView.swift` | `.sheet(isPresented: $showDebugSheet) { MachProbeDebugView() }` | WIRED | Line 145-147 of ContentView.swift. `showDebugSheet` state set by `.onLongPressGesture` on line 27. Sheet modifier on outermost VStack, leaving thermal dashboard intact. |
| `06-VERDICTS.md` | `ROADMAP.md` | Phase 7 reads verdicts to decide which APIs to integrate | VERIFIED | `## Phase 7 Implications` section provides explicit GO decisions for all 4 APIs. Phase 7 goal ("Users can see live CPU and memory readings from all confirmed-accessible data sources") directly references this verdict as its input. |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `MachProbeDebugView.swift` | `probe.results[apiName]` / `probe.finalVerdicts[apiName]` | `SystemMetricsProbe.runProbeSequence()` calling Mach kernel APIs | Yes — `host_statistics`, `host_statistics64`, `task_info`, `task_threads` produce real struct data; verdict classification is based on non-zero check | FLOWING |
| `MachProbeDebugView.swift` | `probe.samplesCompleted` | Incremented in probe Task loop after each sample | Yes — integer counter driven by actual probe iteration | FLOWING |

---

## Behavioral Spot-Checks

Step 7b: SKIPPED for Simulator — the probe engine requires physical iOS 18 hardware to produce meaningful results. The app's entry point is Xcode-deployed, not CLI-runnable. Probe behavior was validated by the human on-device run documented in `06-VERDICTS.md`. The implementation code is substantive (not a stub) and all 4 Mach API calls are wired to kernel functions through the bridging header.

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CPU-02 | 06-01-PLAN.md, 06-02-PLAN.md | User can see system-wide CPU usage if iOS 18 sandbox permits (graceful fallback to hidden if `host_statistics` is blocked) | SATISFIED | `host_statistics` probe confirmed Accessible on iOS 18 free sideload. `06-VERDICTS.md` documents GO for Phase 7 integration. Graceful fallback confirmed not needed. |
| MEM-02 | 06-01-PLAN.md, 06-02-PLAN.md | User can see system-wide memory usage if iOS 18 sandbox permits (graceful fallback to hidden if `host_statistics64` is blocked) | SATISFIED | `host_statistics64` probe confirmed Accessible on iOS 18 free sideload. `06-VERDICTS.md` documents GO for Phase 7 integration. Graceful fallback confirmed not needed. |

**Orphaned requirements check:** REQUIREMENTS.md maps CPU-02 and MEM-02 to Phase 6 — both are claimed by both plans. No orphaned requirements. MEM-01 and CPU-01 are mapped to Phase 7 — correctly deferred.

**Note on task_info / task_threads:** The probe also covers `task_info` (per-process memory) and `task_threads` (per-process CPU), which are probed as groundwork for CPU-01 and MEM-01 in Phase 7. These are not phase 6 requirements but their probe verdicts are included in `06-VERDICTS.md` as bonus evidence for Phase 7. The `06-VERDICTS.md` attributes `task_info` to MEM-01 (per-process component) — this is accurate, though MEM-01 is formally a Phase 7 requirement.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

All three modified files are free of TODO/FIXME/HACK/placeholder comments and hollow implementations. No empty return stubs found. All state variables feed real Mach kernel data through to rendered UI.

---

## Human Verification Required

### 1. Confirm 06-VERDICTS.md reflects actual on-device probe output

**Test:** Review `06-VERDICTS.md` and confirm the raw values match what you observed in the Xcode console and debug sheet during the physical iOS 18 device run on 2026-05-15.

Specifically confirm:
- cpu_ticks user values (10410413, 10414312, 10418146) appeared in `[Termostato] host_statistics CPU:` console lines at ~10-second intervals
- Page counts (free ~5610-5732, active ~40646-41338) appeared in `[Termostato] host_statistics64 Memory:` lines
- Resident size ~79 MB appeared in `[Termostato] task_info Memory:` lines
- Thread count 5-6 and cpu% 0.0-2.0% appeared in `[Termostato] task_threads CPU:` lines
- The debug sheet showed green "Accessible" badges for all 4 rows after 3 samples completed

**Expected:** Developer confirms the VERDICTS.md data matches what was observed on-device, or notes any discrepancy.

**Why human:** The verdicts file is the primary deliverable of this phase. Its values come from a one-time physical device run that cannot be re-executed by the verifier. Programmatic checks can confirm the file structure and plausibility of values, but authenticity of the data (that it reflects an actual iOS 18 sandbox probe, not synthesized values) requires human attestation.

---

## Gaps Summary

No gaps found. All 5 observable truths are verified, all 4 artifacts pass all three verification levels (existence, substantive, wired), key links are intact, and no anti-patterns were detected. The phase goal is achieved: Phase 7 has a clear per-API verdict for all 4 Mach kernel APIs under iOS 18 free-sideload conditions.

The single human-verification item is an attestation check — the developer confirming that `06-VERDICTS.md` faithfully records the on-device probe output. This does not indicate a gap in the implementation, only a boundary that automated verification cannot cross.

---

_Verified: 2026-05-15_
_Verifier: Claude (gsd-verifier)_
