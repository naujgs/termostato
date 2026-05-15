# Phase 6: Mach API Proof-of-Concept - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 06-mach-api-proof-of-concept
**Areas discussed:** Probe architecture, On-device reporting, Verdict criteria, Documentation output

---

## Probe Architecture

| Option | Description | Selected |
|--------|-------------|----------|
| Separate SystemMetrics.swift | New file alongside TemperatureViewModel. Clean separation — probe code is isolated, easy to delete or evolve. | ✓ |
| Extend TemperatureViewModel | Add probe methods directly to the existing ViewModel. Fewer files, but mixes experimental with shipped code. | |
| You decide | Claude picks the best structure. | |

**User's choice:** Separate SystemMetrics.swift
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Swift-only with unsafeMutablePointer | Call Mach APIs directly from Swift via Darwin module. No bridging header needed. | |
| Bridging header with C wrapper | Thin C functions + bridging header. Cleaner Swift code but adds 2 files. | |
| You decide | Claude picks based on best practices. | ✓ |

**User's choice:** You decide — following best engineering conventions, taking a scalable solution
**Notes:** User wants Claude to choose the most maintainable approach

---

| Option | Description | Selected |
|--------|-------------|----------|
| Probe all three APIs | host_statistics, host_statistics64, AND task_info. Covers everything Phase 7 might need. | ✓ |
| System-wide only | Only host_statistics and host_statistics64. Per-process tested in Phase 7. | |
| You decide | Claude determines probe scope. | |

**User's choice:** Probe all three APIs
**Notes:** None

---

## On-Device Reporting

| Option | Description | Selected |
|--------|-------------|----------|
| Console logs only | Print to Xcode console. Requires tethered device. | |
| Temporary debug screen | SwiftUI view showing per-API status in the app. Readable on device without Xcode. | ✓ |
| Both | Console logs + on-screen summary. | |

**User's choice:** Temporary debug screen
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Separate sheet | .sheet() overlay triggered by hidden gesture/button. Dashboard stays intact. | ✓ |
| Replace main view | Swap ContentView temporarily. Simpler but dashboard unavailable. | |
| New tab | Early TabView with Thermal + Debug tabs. Head start on Phase 8. | |

**User's choice:** Separate sheet
**Notes:** None

---

## Verdict Criteria

| Option | Description | Selected |
|--------|-------------|----------|
| Three-tier (accessible/degraded/blocked) | Most nuanced classification. | ✓ |
| Two-tier (works/doesn't) | Simpler but less informative. | |
| You decide | Claude determines classification. | |

**User's choice:** Three-tier (accessible/degraded/blocked)
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Single call | One call per API. Fast but may miss intermittent failures. | |
| 3 samples over 30 seconds | 10s spacing matching polling interval. Majority verdict. | ✓ |
| You decide | Claude picks sample count. | |

**User's choice:** 3 samples over 30 seconds
**Notes:** None

---

## Documentation Output

| Option | Description | Selected |
|--------|-------------|----------|
| Markdown in .planning/ | Structured 06-VERDICTS.md in phase directory. Phase 7 planner reads it. | ✓ |
| Inline code comments | Verdicts as comments in SystemMetrics.swift. | |
| Both | Markdown report + code comments. | |
| You decide | Claude picks documentation approach. | |

**User's choice:** Markdown in .planning/
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Verdicts + raw evidence | Include return codes, sample values, timestamps alongside each verdict. | ✓ |
| Verdicts only | Just the final classification per API. | |
| You decide | Claude determines detail level. | |

**User's choice:** Verdicts + raw evidence
**Notes:** None

---

## Claude's Discretion

- C bridge approach (Swift-only vs bridging header) — user deferred to best engineering conventions
- Internal SystemMetrics.swift structure (method signatures, return types, error handling)
- Debug sheet layout and visual design
- Probe sequence trigger mechanism
- Console logging format

## Deferred Ideas

None — discussion stayed within phase scope
