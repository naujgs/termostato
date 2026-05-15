# Phase 7: Metrics Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 07-metrics-integration
**Areas discussed:** Dashboard structure, Metric display format, ViewModel architecture, Main-thread Mach fix

---

## Dashboard structure

| Option | Description | Selected |
|--------|-------------|----------|
| TabView now in Phase 7 | Restructure ContentView to TabView with 3 tabs: Thermal (existing badge+chart), CPU (new), Memory (new). Aligns with locked STATE.md decision. | ✓ |
| Metrics inline, tabs in Phase 8 | Add CPU/memory readings below the thermal chart in the existing VStack. Phase 8 (DASH-01) restructures to TabView. | |

**User's choice:** TabView now in Phase 7

---

| Option | Description | Selected |
|--------|-------------|----------|
| Move to ThermalView title | Long-press on 'Termostato' title stays, just moves with the title into ThermalView. No behavior change. | ✓ |
| Keep in ContentView (tab bar level) | Long-press on the TabView container or a tab bar item. | |

**User's choice:** Debug sheet trigger moves to ThermalView

---

## Metric display format

| Option | Description | Selected |
|--------|-------------|----------|
| Large number + label | Prominent number with label above. Matches thermal badge directness. No extra components needed. | ✓ |
| Progress bar + number | Horizontal progress bar (0-100%) with value beside it. | |

**User's choice:** Large number + label (CPU tab)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Large number + label | Same style as CPU tab: big MB number for App Memory, free/used MB for System Memory. Consistent across tabs. | ✓ |
| Number + sublabel details | App memory as MB, system memory shows free/used as secondary text below the main number. | |

**User's choice:** Large number + label (Memory tab)

---

## ViewModel architecture

| Option | Description | Selected |
|--------|-------------|----------|
| Extend TemperatureViewModel | Add CPU/memory properties and updateMetrics() to existing ViewModel. Reuses Timer.publish. | |
| New MetricsViewModel | Separate @Observable class with its own polling timer. | ✓ |

**User's choice:** New MetricsViewModel

---

| Option | Description | Selected |
|--------|-------------|----------|
| Same 10s interval | Consistent update rate, simple to reason about. | |
| 5s for everything | Applied universally — MetricsViewModel AND TemperatureViewModel both at 5s. | ✓ |

**User's choice:** 5s interval applied to everything, including TemperatureViewModel (currently 10s)
**Notes:** User specified 5s interval for all polling across the app, not just MetricsViewModel.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Both VMs start/stop together | ContentView scenePhase observer calls start/stop on both. | ✓ |
| MetricsViewModel stops differently | Only thermal needs background activity. | |

**User's choice:** Both start/stop together on scenePhase changes

---

## Main-thread Mach fix

| Option | Description | Selected |
|--------|-------------|----------|
| Fix in Phase 7 | nonisolated Mach methods + Task.detached polling + MainActor.run for result marshaling. | ✓ |
| Keep on main thread | Mach calls are fast (<1ms). Acceptable for personal tool. | |

**User's choice:** Fix in Phase 7 — nonisolated + Task.detached pattern

---

## Claude's Discretion

- Tab bar icon SF Symbols
- Exact number formatting (decimal places)
- Card padding, spacing, typography
- Empty/loading state before first poll

## Deferred Ideas

- Rolling history charts for CPU/memory — v1.3+ (CPU-03, MEM-03)
- Battery level display — v1.3+ (BATT-01, BATT-02)
- State duration display — v1.3+ (THERM-01)
