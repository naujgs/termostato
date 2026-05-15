# Roadmap: Termostato

## Milestones

- ✅ **v1.0 MVP** — Phases 1-3 (shipped 2026-05-13)
- ✅ **v1.1 Visual Improvements** — Phases 4-5 (shipped 2026-05-13)
- ✅ **v1.2 Sensor Research & Data Expansion** — Phases 6-8 (shipped 2026-05-15)

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

<details>
<summary>✅ v1.2 Sensor Research & Data Expansion (Phases 6-8) — SHIPPED 2026-05-15</summary>

**Milestone Goal:** Systematically probe Mach system APIs on iOS 18 under free sideload, implement all confirmed-accessible CPU and memory metrics, and present them in a tabbed dashboard alongside existing thermal state.

- [x] **Phase 6: Mach API Proof-of-Concept** — Validate system-wide CPU and memory APIs on physical device
- [x] **Phase 7: Metrics Integration** — Wire per-process and system-wide metrics into the ViewModel
- [x] **Phase 8: Dashboard Tabs** — Refactor single-screen layout into TabView with Thermal, CPU, and Memory tabs

Full details: `.planning/milestones/v1.2-ROADMAP.md`

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & Device Validation | v1.0 | 3/3 | Complete | 2026-05-12 |
| 2. Dashboard UI | v1.0 | 1/1 | Complete | 2026-05-12 |
| 3. Alerts & Notification System | v1.0 | 2/2 | Complete | 2026-05-13 |
| 4. Polling | v1.1 | 1/1 | Complete | 2026-05-13 |
| 5. Visual Polish | v1.1 | 1/1 | Complete | 2026-05-13 |
| 6. Mach API Proof-of-Concept | v1.2 | 2/2 | Complete | 2026-05-14 |
| 7. Metrics Integration | v1.2 | 3/3 | Complete | 2026-05-15 |
| 8. Dashboard Tabs | v1.2 | 3/3 | Complete | 2026-05-15 |

*Full phase details archived in `.planning/milestones/`*
