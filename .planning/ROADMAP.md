# Roadmap: Termostato

## Milestones

- ✅ **v1.0 MVP** — Phases 1–3 (shipped 2026-05-13)
- ⏳ **v1.1 Visual Improvements** — Phases 4–5 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1–3) — SHIPPED 2026-05-13</summary>

- [x] **Phase 1: Foundation & Device Validation** — 3/3 plans — confirmed thermalState pipeline + IOKit decision on physical device
- [x] **Phase 2: Dashboard UI** — 1/1 plan — SwiftUI badge + step-chart dashboard verified on device
- [x] **Phase 3: Alerts & Notification System** — 2/2 plans — local notifications with cooldown, background delivery, permission banner

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

### v1.1 Visual Improvements

- [ ] **Phase 4: Polling** — Reduce Timer.publish from 30s → 10s, update maxHistory from 120 → 360, update chart label
- [ ] **Phase 5: Visual Polish** — Add custom app icon (1024×1024 PNG asset drop-in)

## Phase Details

### Phase 4: Polling
**Goal**: App polls thermal state every 10 seconds and retains a full 60-minute step-chart history
**Depends on**: Phase 3 (v1.0 complete)
**Requirements**: POLL-01
**Success Criteria** (what must be TRUE):
  1. Thermal state reading visibly updates every 10 seconds (observable via chart density vs. the previous 30s cadence)
  2. Step-chart history retains 360 data points — history window remains 60 minutes at the new 10s interval
  3. Chart label reflects the correct 60-minute window description (no stale "2 hour" or "120-entry" text)
**Plans**: 1 plan

Plans:
- [x] 04-01-PLAN.md — Update polling interval (30s→10s) and ring-buffer capacity (120→360) in TemperatureViewModel.swift

### Phase 5: Visual Polish
**Goal**: App displays a custom icon on the home screen — the Xcode placeholder is replaced
**Depends on**: Phase 4
**Requirements**: ICON-01
**Success Criteria** (what must be TRUE):
  1. Home screen and app switcher show the custom icon — the Xcode placeholder grid is no longer visible
  2. No Swift code changes required — delivery is a single 1024×1024 PNG dropped into AppIcon.appiconset
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & Device Validation | v1.0 | 3/3 | Complete | 2026-05-12 |
| 2. Dashboard UI | v1.0 | 1/1 | Complete | 2026-05-12 |
| 3. Alerts & Notification System | v1.0 | 2/2 | Complete | 2026-05-13 |
| 4. Polling | v1.1 | 0/1 | Not started | - |
| 5. Visual Polish | v1.1 | 0/1 | Not started | - |
