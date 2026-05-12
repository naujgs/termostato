# Roadmap: Termostato

## Overview

Termostato ships in three phases derived from its six v1 requirements. Phase 1 is a device validation spike — the data pipeline must be proven on the actual target device before any UI is built, because the highest-risk component (IOKit private API) fails silently. Phase 2 builds the foreground dashboard on top of the confirmed data pipeline. Phase 3 wires the notification system to the dashboard. The three phases compose a fully working sideloaded thermal monitor with background alerts.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation & Device Validation** - Prove the data pipeline on the actual device; confirm thermalState reads under free-account provisioning
- [ ] **Phase 2: Dashboard UI** - Build the foreground display: thermal state badge, session history chart
- [ ] **Phase 3: Alerts & Notification System** - Wire notification permission, foreground threshold alerts, and background thermalStateDidChangeNotification alerts

## Phase Details

### Phase 1: Foundation & Device Validation
**Goal**: The thermal data pipeline is running on the target device and confirmed working under free Apple ID signing
**Depends on**: Nothing (first phase)
**Requirements**: INST-01
**Success Criteria** (what must be TRUE):
  1. The app builds in Xcode and installs onto the owner's iPhone via USB without App Store submission
  2. `ProcessInfo.thermalState` returns a valid value and logs to console with each poll cycle
  3. A written decision record exists stating whether IOKit returns data or is silently blocked (determining whether a graceful "–°C" fallback is needed)
  4. The data pipeline runs while the app is foregrounded and pauses when it is backgrounded (scenePhase observer confirmed)
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Xcode project scaffold: iOS 18.0 target, Swift 6.3 strict concurrency, bridging header for IOKit
- [x] 01-02-PLAN.md — TemperatureViewModel (@Observable, @MainActor, 30s polling) + scenePhase lifecycle wiring + IOKit probe
- [x] 01-03-PLAN.md — On-device validation checkpoint + DECISION-IOKIT.md record + probe code removal

### Phase 2: Dashboard UI
**Goal**: Users can see the current thermal state and session history at a glance on the live dashboard
**Depends on**: Phase 1
**Requirements**: DISP-01, DISP-02
**Success Criteria** (what must be TRUE):
  1. The current thermal state (Nominal / Fair / Serious / Critical) is displayed prominently with a distinct color for each level (green / yellow / orange / red)
  2. A step-chart of thermal state changes since the app was opened is visible and updates in real time
  3. The chart reads from a fixed-capacity ring buffer — it does not grow unboundedly and does not degrade in frame rate after extended use
  4. All data shown is session-only: closing and reopening the app starts a fresh history with no prior data shown
**Plans**: 1 plan

Plans:
- [ ] 02-01-PLAN.md — Extend TemperatureViewModel with ThermalReading ring buffer + replace ContentView with badge + step-chart dashboard

### Phase 3: Alerts & Notification System
**Goal**: Users receive a notification when their device thermal state reaches Serious or Critical, whether the app is foregrounded or backgrounded
**Depends on**: Phase 2
**Requirements**: ALRT-01, ALRT-02, ALRT-03
**Success Criteria** (what must be TRUE):
  1. On first launch, the app requests notification permission; if denied, the app degrades gracefully (no crash, no broken state)
  2. A local notification fires when thermal state reaches Serious or Critical; it does not re-fire while state remains elevated (cooldown enforced)
  3. When the app is backgrounded (not terminated), a thermal state escalation to Serious or Critical still triggers a notification via thermalStateDidChangeNotification
  4. A Settings deep-link banner appears when notification permission is denied, guiding the user to re-enable it
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Device Validation | 0/3 | Not started | - |
| 2. Dashboard UI | 0/1 | Not started | - |
| 3. Alerts & Notification System | 0/? | Not started | - |
