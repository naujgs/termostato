# Requirements: Termostato

**Defined:** 2026-05-14
**Core Value:** The phone's thermal state, always visible at a glance — with an alert before it gets dangerously hot.

## v1.2 Requirements

Requirements for Sensor Research & Data Expansion milestone. Each maps to roadmap phases.

### CPU Metrics

- [ ] **CPU-01**: User can see Termostato's own CPU usage as a percentage gauge
- [ ] **CPU-02**: User can see system-wide CPU usage if the iOS 18 sandbox permits (graceful fallback to hidden if `host_statistics` is blocked)

### Memory Metrics

- [ ] **MEM-01**: User can see Termostato's memory footprint in MB
- [ ] **MEM-02**: User can see system-wide memory usage (free/used) if the iOS 18 sandbox permits (graceful fallback to hidden if `host_statistics64` is blocked)

### Dashboard Layout

- [ ] **DASH-01**: User can switch between Thermal, CPU, and Memory tabs
- [ ] **DASH-02**: Existing thermal state badge and step-chart remain functional in the Thermal tab (no regression)

## Future Requirements (v1.3+)

- **CPU-03**: Rolling history chart for CPU usage over session
- **MEM-03**: Rolling history chart for memory usage over session
- **BATT-01**: Battery level % and charge state display
- **BATT-02**: Battery level history chart
- **THERM-01**: State duration display ("Serious for 4 min")
- **THERM-02**: "Back to Nominal" recovery notification
- **HIST-01**: Persistent session history across app restarts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Numeric °C temperature | IOKit blocked by AMFI under free Apple ID; TrollStore requires iOS ≤17.0 (device is iOS 18) |
| GPU utilization | No public runtime API exists on iOS |
| Per-core CPU breakdown | Unnecessary complexity for personal monitoring tool |
| Battery features | User decision — deferred to v1.3+ |
| System-wide CPU/memory as hard requirement | Sandbox may block; implemented as best-effort with graceful fallback |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CPU-01 | — | Pending |
| CPU-02 | — | Pending |
| MEM-01 | — | Pending |
| MEM-02 | — | Pending |
| DASH-01 | — | Pending |
| DASH-02 | — | Pending |

**Coverage:**
- v1.2 requirements: 6 total
- Mapped to phases: 0
- Unmapped: 6 ⚠️

---
*Requirements defined: 2026-05-14*
*Last updated: 2026-05-14 after initial definition*
