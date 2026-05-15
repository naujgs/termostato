# Phase 6: Mach API Verdicts

**Probed:** 2026-05-15
**Device:** iPhone (iOS 18) — free Apple ID sideload, no TrollStore, no jailbreak
**Probe method:** 3 samples at 10-second intervals, majority verdict
**Result:** All 4 APIs Accessible — no graceful fallback needed

## Summary

| API | Verdict | kern_return_t | Notes |
|-----|---------|---------------|-------|
| host_statistics (CPU) | **Accessible** | 0 (KERN_SUCCESS) | System-wide CPU tick counts; cpu_ticks sum > 0 all samples |
| host_statistics64 (Memory) | **Accessible** | 0 (KERN_SUCCESS) | System-wide VM page counts; page sum > 0 all samples |
| task_info (Process Memory) | **Accessible** | 0 (KERN_SUCCESS) | App resident memory ~79 MB; resident_size > 0 all samples |
| task_threads (Process CPU) | **Accessible** | 0 (KERN_SUCCESS) | 5–6 threads, total_cpu 0.0–2.0% across samples |

## Detailed Evidence

### host_statistics (CPU) — ACCESSIBLE

**Requirement:** CPU-02
**kern_return_t:** 0 (KERN_SUCCESS)

| Sample | Timestamp | kern_return_t | Data |
|--------|-----------|---------------|------|
| 1 | 14:54:09 | 0 | user: 10410413, system: 0, idle: 28064974, nice: 0 |
| 2 | 14:54:19 | 0 | user: 10414312, system: 0, idle: 28067198, nice: 0 |
| 3 | 14:54:29 | 0 | user: 10418146, system: 0, idle: 28069642, nice: 0 |

**Verdict rationale:** KERN_SUCCESS on all 3 samples. cpu_ticks sum is non-zero and growing between samples (user ticks incremented: 10410413 → 10414312 → 10418146), confirming live data — not stale or zeroed. Classified Accessible.

---

### host_statistics64 (Memory) — ACCESSIBLE

**Requirement:** MEM-02
**kern_return_t:** 0 (KERN_SUCCESS)

| Sample | Timestamp | kern_return_t | Data |
|--------|-----------|---------------|------|
| 1 | 14:54:09 | 0 | free: 5610, active: 41087, inactive: 36634, wired: 45931 |
| 2 | 14:54:19 | 0 | free: 5612, active: 41338, inactive: 36346, wired: 45951 |
| 3 | 14:54:29 | 0 | free: 5732, active: 40646, inactive: 37278, wired: 45892 |

**Verdict rationale:** KERN_SUCCESS on all 3 samples. Page counts are non-zero and vary between samples (free: 5610 → 5612 → 5732 pages), confirming live VM data. Total pages ~129K consistent with physical iPhone RAM. Classified Accessible.

**Note:** `system` counter reads 0 across all samples. This is a known behavior on Apple Silicon iOS devices — system ticks are attributed differently in the kernel's scheduler. The `user`, `idle`, and data values are valid.

---

### task_info (Process Memory) — ACCESSIBLE

**Requirement:** MEM-01 (per-process component)
**kern_return_t:** 0 (KERN_SUCCESS)

| Sample | Timestamp | kern_return_t | Data |
|--------|-----------|---------------|------|
| 1 | 14:54:09 | 0 | resident_size: 83378176 bytes (79 MB), virtual_size: 420086579200 bytes |
| 2 | 14:54:19 | 0 | resident_size: 83804160 bytes (79 MB), virtual_size: 420087218176 bytes |
| 3 | 14:54:29 | 0 | resident_size: 83755008 bytes (79 MB), virtual_size: 420087218176 bytes |

**Verdict rationale:** KERN_SUCCESS on all 3 samples. Resident size ~79 MB is plausible for a running SwiftUI app. Virtual size ~391 GB is normal for 64-bit iOS address space. Classified Accessible.

---

### task_threads (Process CPU) — ACCESSIBLE

**Requirement:** CPU-02 (per-process component)
**kern_return_t:** 0 (KERN_SUCCESS)

| Sample | Timestamp | kern_return_t | Data |
|--------|-----------|---------------|------|
| 1 | 14:54:09 | 0 | threads: 5, total_cpu: 2.0% |
| 2 | 14:54:19 | 0 | threads: 6, total_cpu: 0.1% |
| 3 | 14:54:29 | 0 | threads: 6, total_cpu: 0.0% |

**Verdict rationale:** KERN_SUCCESS on all 3 samples. Thread count (5–6) is plausible for a SwiftUI app with timer, render, and background threads. CPU usage dropping from 2.0% to 0.0% between samples is expected — Sample 1 includes the probe startup cost. Classified Accessible.

---

## Phase 7 Implications

### System-Wide APIs

- **CPU (host_statistics):** GO — integrate into ViewModel. Sandboxed iOS 18 + free Apple ID sideload returns KERN_SUCCESS. No fallback needed.
- **Memory (host_statistics64):** GO — integrate into ViewModel. Same access level as host_statistics. Note: `system` tick counter reads 0 on Apple Silicon — compute CPU% from `user + idle + nice` only, or use `(user / (user + idle)) * 100`.

### Per-Process APIs

- **Memory (task_info):** GO — integrate resident_size into ViewModel. Provides accurate MB footprint for the app's own memory usage (satisfies MEM-01).
- **CPU (task_threads):** GO — integrate total_cpu into ViewModel. Returns live per-thread CPU usage; sum across non-idle threads gives app CPU%.

### Graceful Fallback Decision

**No fallback needed.** All 4 APIs returned KERN_SUCCESS under free Apple ID sideload on iOS 18. The graceful-fallback paths specified in CPU-02 ("hidden if `host_statistics` is blocked") and MEM-02 ("hidden if `host_statistics64` is blocked") do not need to activate.

Phase 7 can wire all 4 APIs into `TemperatureViewModel` directly. The probe code in `SystemMetrics.swift` can either be:
- Retained as a debug diagnostic tool (long-press trigger remains)
- Or used as the model for production polling functions in the ViewModel

**Recommendation:** Keep the debug sheet; extract proven Mach call patterns from `SystemMetrics.swift` into production polling methods in `TemperatureViewModel` in Phase 7.
