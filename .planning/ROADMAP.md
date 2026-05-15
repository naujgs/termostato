# Roadmap: Termostato

## Milestones

- ✅ **v1.0 MVP** — Phases 1-3 (shipped 2026-05-13)
- ✅ **v1.1 Visual Improvements** — Phases 4-5 (shipped 2026-05-13)
- 🚧 **v1.2 Sensor Research & Data Expansion** — Phases 6-8 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-3) — SHIPPED 2026-05-13</summary>

- [x] **Phase 1: Foundation & Device Validation** — 3/3 plans — confirmed thermalState pipeline + IOKit decision on physical device
- [x] **Phase 2: Dashboard UI** — 1/1 plan — SwiftUI badge + step-chart dashboard verified on device
- [x] **Phase 3: Alerts & Notification System** — 2/2 plans — local notifications with cooldown, background delivery, permission banner

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v1.1 Visual Improvements (Phases 4-5) — SHIPPED 2026-05-13</summary>

- [x] **Phase 4: Polling** — 1/1 plan — polling reduced to 10s, ring buffer expanded to 360 (60 min history)
- [x] **Phase 5: Visual Polish** — 1/1 plan — custom app icon wired into asset catalog, alpha-stripped

Full details: `.planning/milestones/v1.1-ROADMAP.md`

</details>

### 🚧 v1.2 Sensor Research & Data Expansion (In Progress)

**Milestone Goal:** Systematically probe Mach system APIs on iOS 18 under free sideload, implement all confirmed-accessible CPU and memory metrics, and present them in a tabbed dashboard alongside existing thermal state.

- [x] **Phase 6: Mach API Proof-of-Concept** — Validate system-wide CPU and memory APIs on physical device
- [x] **Phase 7: Metrics Integration** — Wire per-process and system-wide metrics into the ViewModel
- [ ] **Phase 8: Dashboard Tabs** — Refactor single-screen layout into TabView with Thermal, CPU, and Memory tabs

## Phase Details

### Phase 6: Mach API Proof-of-Concept
**Goal**: Determine which Mach system APIs (host_statistics, host_statistics64, task_info) return valid data on iOS 18 under free Apple ID sideload
**Depends on**: Phase 5
**Requirements**: CPU-02, MEM-02
**Success Criteria** (what must be TRUE):
  1. A minimal SystemMetrics.swift file exists with C-bridged Mach API calls for host_statistics (CPU) and host_statistics64 (memory)
  2. Running the app on a physical iOS 18 device logs whether each Mach call succeeds or returns KERN_FAILURE / zeroed data
  3. A clear per-API verdict (accessible / blocked / degraded) is documented so Phase 7 knows what to integrate
  4. If system-wide APIs are blocked, the graceful-fallback path (hide system-wide gauge, show per-process only) is confirmed as the design decision
**Plans**: 2 plans
Plans:
- [x] 06-01-PLAN.md — Build probe engine (SystemMetrics.swift) and debug sheet UI (MachProbeDebugView.swift)
- [x] 06-02-PLAN.md — On-device probe checkpoint and verdict documentation (06-VERDICTS.md)

### Phase 7: Metrics Integration
**Goal**: Users can see live CPU and memory readings from all confirmed-accessible data sources
**Depends on**: Phase 6
**Requirements**: CPU-01, MEM-01, CPU-02, MEM-02, DASH-01, DASH-02
**Success Criteria** (what must be TRUE):
  1. User can see Termostato's own CPU usage displayed as a percentage, updating on the polling interval
  2. User can see Termostato's own memory footprint displayed in MB, updating on the polling interval
  3. System-wide CPU % and memory (used/free) are displayed (Phase 6 confirmed all 4 APIs KERN_SUCCESS)
  4. TabView with Thermal, CPU, Memory tabs is implemented (DASH-01, DASH-02 satisfied here per D-03)
**Plans**: 3 plans
Plans:
- [x] 07-01-PLAN.md — Register new Swift files in pbxproj + create MetricsViewModel.swift + reduce TemperatureViewModel polling to 5s
- [x] 07-02-PLAN.md — Create ThermalView.swift, CPUView.swift, MemoryView.swift
- [x] 07-03-PLAN.md — Restructure ContentView to TabView container + on-device human verification

### Phase 8: Dashboard Tabs
**Goal**: Users can navigate between Thermal, CPU, and Memory views using a TabView, with no regression to existing thermal functionality
**Depends on**: Phase 7
**Requirements**: DASH-01, DASH-02
**Success Criteria** (what must be TRUE):
  1. User can switch between Thermal, CPU, and Memory tabs via a TabView at the bottom of the screen
  2. The Thermal tab displays the existing color-coded badge and session-history step-chart exactly as before (no visual or behavioral regression)
  3. The CPU tab displays per-process CPU usage (and system-wide if accessible) with appropriate labeling
  4. The Memory tab displays per-process memory footprint (and system-wide if accessible) with appropriate labeling
  5. Tab selection persists during a session -- switching away and back does not reset data or scroll position
**Plans**: 3 plans
Plans:
- [x] 08-01-PLAN.md — Add selectedTab @State binding to ContentView (SC5)
- [x] 08-02-PLAN.md — On-device SC5 tab persistence UAT checkpoint
- [ ] 08-03-PLAN.md — Requirements and milestone close-out docs

## Progress

**Execution Order:**
Phases execute in numeric order: 6 -> 7 -> 8

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & Device Validation | v1.0 | 3/3 | Complete | 2026-05-12 |
| 2. Dashboard UI | v1.0 | 1/1 | Complete | 2026-05-12 |
| 3. Alerts & Notification System | v1.0 | 2/2 | Complete | 2026-05-13 |
| 4. Polling | v1.1 | 1/1 | Complete | 2026-05-13 |
| 5. Visual Polish | v1.1 | 1/1 | Complete | 2026-05-13 |
| 6. Mach API Proof-of-Concept | v1.2 | 2/2 | Complete | 2026-05-14 |
| 7. Metrics Integration | v1.2 | 3/3 | Complete | 2026-05-15 |
| 8. Dashboard Tabs | v1.2 | 2/3 | In Progress|  |
