---
phase: 06-mach-api-proof-of-concept
plan: 02
subsystem: mach-api-verdicts
tags: [mach-api, probe, on-device, validation, verdicts]
dependency_graph:
  requires: [SystemMetricsProbe, MachProbeDebugView]
  provides: [06-VERDICTS.md]
  affects: [Phase 7 planning]
tech_stack:
  added: []
  patterns: []
key_files:
  created:
    - .planning/phases/06-mach-api-proof-of-concept/06-VERDICTS.md
  modified: []
decisions:
  - "All 4 Mach APIs returned KERN_SUCCESS on iOS 18 free Apple ID sideload — no graceful fallback needed"
  - "host_statistics system tick counter reads 0 on Apple Silicon — compute CPU% from user+idle+nice only"
  - "Phase 7 should extract Mach call patterns from SystemMetrics.swift into TemperatureViewModel production methods"
metrics:
  duration: "~35 seconds (probe run)"
  completed: "2026-05-15"
  tasks_completed: 2
  files_changed: 1
---

# Phase 06 Plan 02: On-Device Probe Run & Verdict Documentation

**One-liner:** All 4 Mach APIs (host_statistics, host_statistics64, task_info, task_threads) are Accessible under free Apple ID sideload on iOS 18 — Phase 7 can wire all without fallback.

---

## What Was Built

`06-VERDICTS.md` with per-API verdicts from a physical iPhone (iOS 18) running the probe under free Apple ID sideload conditions. The document includes 3-sample evidence tables, verdict rationale, and Phase 7 go/no-go decisions per API.

## Key Findings

| API | Verdict | kern_return_t |
|-----|---------|---------------|
| host_statistics (CPU) | Accessible | 0 (KERN_SUCCESS) |
| host_statistics64 (Memory) | Accessible | 0 (KERN_SUCCESS) |
| task_info (Process Memory) | Accessible | 0 (KERN_SUCCESS) |
| task_threads (Process CPU) | Accessible | 0 (KERN_SUCCESS) |

**Critical finding:** The iOS sandbox does NOT block these Mach APIs for sideloaded apps. This was not guaranteed before testing — the probe was designed assuming possible KERN_FAILURE returns.

**Apple Silicon note:** `host_statistics` `system` tick counter reads 0. CPU% calculation in Phase 7 must use `user / (user + idle)` ratio, not include system ticks.

## Issues Encountered

None. All APIs returned KERN_SUCCESS on every sample. The debug sheet rendered correctly, haptic feedback fired on long-press trigger, and progress bar tracked all 3 samples.

## Self-Check

- [x] 06-VERDICTS.md exists with 4-row summary table
- [x] Each API has a 3-sample evidence table with raw kern_return_t values
- [x] Phase 7 Implications section has go/no-go per API
- [x] Graceful Fallback Decision confirmed not needed
- [x] CPU-02 and MEM-02 requirement IDs referenced
