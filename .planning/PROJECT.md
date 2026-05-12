# Termostato

## What This Is

Termostato is a personal iOS app (sideloaded, not App Store) that monitors the iPhone's thermal state in real time. It displays the system thermal state level, rendered in a live dashboard with a session-length history chart and push-notification alerts when the device overheats.

## Core Value

The phone's thermal state, always visible at a glance — with an alert before it gets dangerously hot.

## Requirements

### Validated

- [x] App installable via Xcode sideload (no App Store) — *Validated in Phase 1: Foundation & Device Validation*
- [x] Display iOS thermal state level (Nominal / Fair / Serious / Critical) via public API — *Validated in Phase 1: confirmed on physical device via ProcessInfo.thermalState*

### Validated

- [x] Dashboard UI with live thermal state readout and session-length history chart — *Validated in Phase 2: badge + step-chart verified on physical iPhone*

### Validated

- [x] Local notifications when thermal state reaches Serious/Critical, with cooldown and background delivery — *Validated in Phase 3: all four criteria passed on physical device*

### Out of Scope

- App Store distribution — personal sideload only
- Persistent history across sessions — session data only, no on-disk storage for v1
- Android / other platforms — iPhone only
- Numeric °C temperature — IOKit inaccessible under free Apple ID sideloading (confirmed Phase 1)

## Context

- **Target device:** iPhone (any model supported by the iOS version Xcode targets)
- **Dev machine:** MacBook Air, Apple M3, 16 GB RAM
- **Toolchain:** Xcode 26.4.1 + free Apple Developer account (7-day signing)
- **Distribution:** Sideloaded directly via Xcode over USB
- **Data source:** `ProcessInfo.thermalState` (public, 4 levels) — IOKit numeric temperature confirmed blocked under free Apple ID

## Constraints

- **Platform:** iOS only — no cross-platform framework needed
- **Signing:** Free Apple ID → 7-day certificate expiry, must re-install weekly
- **Background execution:** Local notification strategy; full background polling restricted on iOS

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Sideload only (no App Store) | Avoids App Store review | Confirmed — app installed via Xcode free Apple ID (Phase 1) |
| Use private IOKit APIs for numeric temp | Public API only gives 4-level state, not raw °C | BLOCKED — IOKit inaccessible under free Apple ID sideloading (Phase 1). Numeric °C is Out of Scope for v1. |
| Session-length history (not persistent) | Simplifies v1; persistent storage deferred | Confirmed — no CoreData/SQLite planned |
| SwiftUI over UIKit | Single-screen dashboard; SwiftUI declarative model is a better fit | Confirmed — SwiftUI used throughout Phase 1 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

---
*Last updated: 2026-05-13 after Phase 3 completion — v1.0 milestone complete*
